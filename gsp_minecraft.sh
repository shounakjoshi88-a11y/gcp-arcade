#!/usr/bin/env bash
# =============================================================================
#  "Create and Configure Virtual Machines"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19095).
#
#  Sets up a Minecraft server on a Compute Engine instance: a customized VM
#  with a 50 GB SSD data disk and a static external IP, the headless JRE and
#  the Minecraft server itself, a firewall rule for the game port, a backup
#  script on a cron schedule, and startup/shutdown scripts in the metadata.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_minecraft.sh
#     chmod +x gsp_minecraft.sh
#     ./gsp_minecraft.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       the lab's zone (asked for)
#     --region REGION   region (default: derived from the zone)
#     --image IMAGE     the boot disk image family (default: from the project)
#     --task N          run only task N (1-6)
#     --yes             do not pause for the checkpoints
#     --stop-vm         also stop the VM at the end, the way the lab does
#     -h, --help        this help
#
#  CHECKPOINTS (100 points, 20 each):
#     1. Create the VM and prepare the data disk
#     2. Install the Java Runtime Environment (JRE) and the Minecraft server
#     3. Allow client traffic
#     4. Schedule regular backups
#     5. Server maintenance
#
#  NOTES:
#   * The zone is injected by the lab per run, so the script asks for it.
#   * The steps that run INSIDE the VM are uploaded with gcloud compute scp
#     and run over one SSH session, so the environment variables survive
#     from one step to the next.
# =============================================================================

set -uo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

step() { printf "\n%s%s== %s%s\n" "$C_CYAN" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf "  %s[OK]%s   %s\n"   "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "  %s[WARN]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "  %s[FAIL]%s %s\n" "$C_RED"    "$C_RESET" "$*"; }
info() { printf "  %s[INFO]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
dim()  { printf "  %s%s%s\n"          "$C_DIM"    "$*"       "$C_RESET"; }

FAILURES=0
note_fail() { err "$1"; FAILURES=$((FAILURES + 1)); }

PROJECT_OVERRIDE=""
ZONE_OVERRIDE=""
REGION_OVERRIDE=""
IMAGE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
STOP_VM=0

usage() {
  cat <<'USAGE_END'
Create and Configure Virtual Machines (Minecraft server)

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_minecraft.sh
   chmod +x gsp_minecraft.sh
   ./gsp_minecraft.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       the lab's zone (asked for)
   --region REGION   region (default: derived from the zone)
   --image IMAGE     the boot disk image family (default: from the project)
   --task N          run only task N (1-6)
   --yes             do not pause for the checkpoints
   --stop-vm         also stop the VM at the end, the way the lab does
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)    ZONE_OVERRIDE="$2";    shift 2 ;;
    --region)  REGION_OVERRIDE="$2";  shift 2 ;;
    --image)   IMAGE_OVERRIDE="$2";   shift 2 ;;
    --task)    ONLY_TASK="$2";        shift 2 ;;
    --yes)     ASSUME_YES=1;          shift ;;
    --stop-vm) STOP_VM=1;             shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# project
# ---------------------------------------------------------------------------
PROJECT_ID="$PROJECT_OVERRIDE"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
fi
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  err "No GCP project resolved. Pass --project ID"
  exit 1
fi

# ---------------------------------------------------------------------------
# the lab's zone
# ---------------------------------------------------------------------------
detect_zone_from_metadata() {
  local meta
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  [ -z "$meta" ] && return 1
  printf '%s' "$meta" | grep -oE '\b[a-z]+-[a-z]+[0-9]-[a-z]\b' | head -1
}

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""

if [ -z "$ZONE_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  META_ZONE="$(detect_zone_from_metadata || true)"
  echo ""
  warn "the lab assigns the zone per lab run - it cannot be read from the project"
  dim "  it is on your lab setup panel (Zone)."
  if [ -n "$META_ZONE" ]; then
    dim "  the project metadata mentions: $META_ZONE"
  fi
  printf "  %sZone%s  [%s]: " "$C_BOLD" "$C_RESET" "${META_ZONE:-${GCP_ZONE:-us-central1-a}}"
  read -r ans
  ZONE_OVERRIDE="${ans:-${META_ZONE:-${GCP_ZONE:-us-central1-a}}}"
  echo ""
fi

ZONE="${ZONE_OVERRIDE:-${GCP_ZONE:-us-central1-a}}"
REGION="${REGION_OVERRIDE:-${ZONE%-*}}"

resolve_image() {
  if [ -n "$IMAGE_OVERRIDE" ]; then echo "$IMAGE_OVERRIDE"; return 0; fi
  local meta found
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  if [ -n "$meta" ]; then
    found="$(printf '%s' "$meta" | grep -oE 'debian-[0-9]+(-[a-z]+)?' | head -1)"
    if [ -n "$found" ]; then echo "$found"; return 0; fi
  fi
  echo "debian-12"
}
IMAGE="$(resolve_image)"

# ---------------------------------------------------------------------------
# names
# ---------------------------------------------------------------------------
VM="mc-server"
DISK="minecraft-disk"
ADDRESS="mc-server-ip"
RULE="minecraft-rule"
TAG="minecraft-server"
PORT="25565"
BUCKET_SUFFIX="minecraft-backup"
JAR_URL="https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar"
STARTUP_URL="https://storage.googleapis.com/cloud-training/archinfra/mcserver/startup.sh"
SHUTDOWN_URL="https://storage.googleapis.com/cloud-training/archinfra/mcserver/shutdown.sh"
MOUNT_DIR="/home/minecraft"
DISK_PATH="/dev/disk/by-id/google-minecraft-disk"

WORKDIR="${GSP_MC_WORKDIR:-$HOME/gsp-minecraft}"

printf "%s%s  Create and Configure Virtual Machines - Minecraft server%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %sregion=%s  %simage=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$REGION" "$C_DIM" "$IMAGE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
instance_exists() {
  gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}
disk_exists() {
  gcloud compute disks describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}
address_exists() {
  gcloud compute addresses describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}
rule_exists() {
  gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}
bucket_exists() {
  gcloud storage buckets describe "gs://$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

# Upload a script to the VM and run it there over one SSH session.
run_on_vm() {  # $1 = local file, $2 = remote path
  local remote="$2"
  if ! gcloud compute scp "$1" "$VM:$remote" --zone "$ZONE" --project "$PROJECT_ID" \
         --quiet >/dev/null 2>&1; then
    err "could not copy $1 to the VM"
    return 1
  fi
  gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT_ID" --quiet \
    --command="bash $remote" 2>&1
  return $?
}

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
step "Preflight checks"

if ! command -v gcloud >/dev/null 2>&1; then
  err "gcloud not found on PATH. Run this inside Google Cloud Shell."
  exit 1
fi
ok "gcloud is available"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
ok "project: $PROJECT_ID"

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - the zone may be wrong, use --zone"
fi

mkdir -p "$WORKDIR" || { err "cannot create $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# Task 1 - the VM, the data disk and the static IP
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create the VM"

  if address_exists "$ADDRESS" "$REGION"; then
    ok "the static IP $ADDRESS already exists"
  else
    if gcloud compute addresses create "$ADDRESS" --region="$REGION" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "reserved the static external IP $ADDRESS"
    else
      note_fail "could not reserve $ADDRESS"
      return 1
    fi
  fi

  IP_ADDR="$(gcloud compute addresses describe "$ADDRESS" --region="$REGION" \
              --project "$PROJECT_ID" --format="value(address)" 2>/dev/null)"
  ok "the static IP is $IP_ADDR"

  if instance_exists "$VM" "$ZONE"; then
    ok "$VM already exists in $ZONE"
    return 0
  fi

  # a leftover disk from an earlier run would make --create-disk fail
  if disk_exists "$DISK" "$ZONE"; then
    warn "the disk $DISK already exists - recreating it blank"
    gcloud compute disks delete "$DISK" --zone "$ZONE" --project "$PROJECT_ID" \
      --quiet >/dev/null 2>&1 && ok "deleted the old $DISK"
  fi

  info "creating $VM (e2-medium, a 10 GB boot disk and a 50 GB SSD data disk)"
  if gcloud compute instances create "$VM" \
       --zone="$ZONE" --project "$PROJECT_ID" \
       --machine-type=e2-medium \
       --network-interface="address=$IP_ADDR,network-tier=PREMIUM,subnet=default" \
       --metadata=enable-oslogin=true \
       --scopes="https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.read_write" \
       --tags="$TAG" \
       --create-disk="auto-delete=yes,boot=yes,device-name=$VM,image=projects/debian-cloud/global/images/family/$IMAGE,mode=rw,size=10,type=pd-balanced" \
       --create-disk="device-name=$DISK,mode=rw,name=$DISK,size=50,type=pd-ssd" \
       --quiet >/dev/null 2>&1; then
    ok "created $VM"
  else
    note_fail "could not create $VM"
    return 1
  fi

  info "waiting for $VM to start"
  local i
  for i in $(seq 1 60); do
    if gcloud compute instances describe "$VM" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      ok "$VM is RUNNING"
      return 0
    fi
    sleep 5
  done
  warn "$VM did not report RUNNING in time"
}

# ---------------------------------------------------------------------------
# Task 2 - format and mount the data disk
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Prepare the data disk"

  if ! instance_exists "$VM" "$ZONE"; then
    err "$VM does not exist - run task 1 first"
    return 1
  fi

  cat > "$WORKDIR/prepare_disk.sh" <<EOF
#!/bin/bash
set -u
sudo mkdir -p $MOUNT_DIR

# format it, but only if it has no filesystem yet
if ! blkid $DISK_PATH >/dev/null 2>&1; then
  echo "formatting $DISK_PATH"
  sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DISK_PATH
else
  echo "$DISK_PATH already has a filesystem - keeping it"
fi

# mount it, but only if it is not mounted already
if ! mountpoint -q $MOUNT_DIR; then
  echo "mounting $DISK_PATH on $MOUNT_DIR"
  sudo mount -o discard,defaults $DISK_PATH $MOUNT_DIR
else
  echo "$MOUNT_DIR is already mounted"
fi

echo "--- the mount point ---"
df -h $MOUNT_DIR | tail -2
ls -l $MOUNT_DIR
EOF

  info "running the disk preparation on $VM"
  OUT="$(run_on_vm "$WORKDIR/prepare_disk.sh" /tmp/prepare_disk.sh)"
  printf '%s\n' "$OUT" | sed 's/^/    /'

  if printf '%s' "$OUT" | grep -qi "already mounted\|mounting"; then
    ok "the data disk is prepared and mounted on $MOUNT_DIR"
  else
    note_fail "the disk preparation did not report success"
  fi

  pause_for_check 2 "Create the VM and prepare the data disk"
}

# ---------------------------------------------------------------------------
# Task 3 - the JRE and the Minecraft server
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Install and run the Minecraft server"

  if ! instance_exists "$VM" "$ZONE"; then
    err "$VM does not exist - run task 1 first"
    return 1
  fi

  cat > "$WORKDIR/install_mc.sh" <<EOF
#!/bin/bash
set -u
sudo apt-get update -y
sudo apt-get install -y default-jre-headless wget screen

cd $MOUNT_DIR

if [ ! -f server.jar ]; then
  echo "downloading the Minecraft server"
  sudo wget -q $JAR_URL
else
  echo "server.jar is already there"
fi

# The first run creates server.properties and eula.txt, then stops because
# the EULA has not been accepted yet.
if [ ! -f eula.txt ]; then
  sudo timeout 120s java -Xmx1024M -Xms1024M -jar server.jar nogui || true
fi

echo "eula=true" | sudo tee eula.txt >/dev/null
echo "the EULA is accepted"

# screen keeps the server running when the SSH session ends
if pgrep -f "server.jar" >/dev/null 2>&1; then
  echo "the server is already running"
else
  echo "starting the server in a screen session"
  sudo screen -dmS mcs java -Xmx1024M -Xms1024M -jar server.jar nogui
fi

echo "waiting for the server to finish starting"
for i in \$(seq 1 60); do
  sudo screen -S mcs -X hardcopy -h /tmp/mcs.log >/dev/null 2>&1 || true
  if grep -q "Done (" /tmp/mcs.log 2>/dev/null; then
    echo "the server is up"
    break
  fi
  sleep 5
done

echo "--- the files ---"
sudo ls -l $MOUNT_DIR
echo "--- the running process ---"
pgrep -af "server.jar" || echo "the server process is not running"
EOF

  info "installing the JRE and the Minecraft server on $VM (a few minutes)"
  OUT="$(run_on_vm "$WORKDIR/install_mc.sh" /tmp/install_mc.sh)"
  printf '%s\n' "$OUT" | tail -40 | sed 's/^/    /'

  if printf '%s' "$OUT" | grep -q "the server is up\|the server is already running"; then
    ok "the Minecraft server is running"
  elif printf '%s' "$OUT" | grep -q "server.jar"; then
    warn "server.jar is installed, but the server did not report that it is up"
    dim "  check it with:  gcloud compute ssh $VM --zone=$ZONE --command='sudo screen -r mcs'"
  else
    note_fail "the installation did not complete"
  fi

  pause_for_check 3 "Install the Java Runtime Environment (JRE) and the Minecraft server"
}

# ---------------------------------------------------------------------------
# Task 4 - the firewall rule
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Allow client traffic"

  if rule_exists "$RULE"; then
    ok "the firewall rule $RULE already exists"
  else
    if gcloud compute firewall-rules create "$RULE" \
         --network=default --direction=INGRESS --priority=1000 \
         --action=ALLOW --rules="tcp:$PORT" --source-ranges="0.0.0.0/0" \
         --target-tags="$TAG" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $RULE (tcp:$PORT -> tag $TAG)"
    else
      note_fail "could not create $RULE"
      return 1
    fi
  fi

  dim ""
  dim "  the server address is: $IP_ADDR"
  dim "  you can test it at: https://mcsrvstat.us/server/$IP_ADDR"

  pause_for_check 4 "Allow client traffic"
}

# ---------------------------------------------------------------------------
# Task 5 - the backups
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Schedule regular backups"

  if ! instance_exists "$VM" "$ZONE"; then
    err "$VM does not exist - run task 1 first"
    return 1
  fi

  BUCKET="$PROJECT_ID-$BUCKET_SUFFIX"
  if bucket_exists "$BUCKET"; then
    ok "the bucket gs://$BUCKET already exists"
  else
    if gcloud storage buckets create "gs://$BUCKET" --project="$PROJECT_ID" \
         --location=US --uniform-bucket-level-access >/dev/null 2>&1; then
      ok "created the bucket gs://$BUCKET"
    else
      note_fail "could not create gs://$BUCKET"
      dim "  bucket names are global - try another project name"
      return 1
    fi
  fi

  cat > "$WORKDIR/backups.sh" <<EOF
#!/bin/bash
set -u
PROJECT_ID=\$(curl -s -H "Metadata-Flavor: Google" \\
  http://metadata.google.internal/computeMetadata/v1/project/project-id)
export YOUR_BUCKET_NAME="\$PROJECT_ID"
echo "YOUR_BUCKET_NAME=\$YOUR_BUCKET_NAME"

# make the variable permanent for future sessions
grep -q YOUR_BUCKET_NAME /root/.profile 2>/dev/null || \\
  echo "export YOUR_BUCKET_NAME=\$YOUR_BUCKET_NAME" | sudo tee -a /root/.profile >/dev/null

# the backup script, exactly as the lab gives it
sudo bash -c 'cat > $MOUNT_DIR/backup.sh' << 'BACKUP_SCRIPT'
#!/bin/bash
screen -r mcs -X stuff '/save-all\\n/save-off\\n'
/usr/bin/gcloud storage cp -R \${BASH_SOURCE%/*}/world gs://\${YOUR_BUCKET_NAME}-minecraft-backup/\$(date "+%Y%m%d-%H%M%S")-world
screen -r mcs -X stuff '/save-on\\n'
BACKUP_SCRIPT

sudo chmod 755 $MOUNT_DIR/backup.sh
echo "the backup script is in place"

# run it once, so the bucket really holds a backup
cd $MOUNT_DIR
sudo -E timeout 300 ./backup.sh
echo "the backup finished"

# schedule it every 4 hours
sudo crontab -l 2>/dev/null | grep -v 'YOUR_BUCKET_NAME=' | grep -v '$MOUNT_DIR/backup.sh' > /tmp/cron.new || true
echo "YOUR_BUCKET_NAME=\$YOUR_BUCKET_NAME" >> /tmp/cron.new
echo "0 */4 * * * $MOUNT_DIR/backup.sh" >> /tmp/cron.new
sudo crontab /tmp/cron.new
echo "--- the crontab ---"
sudo crontab -l
EOF

  info "setting up the backups on $VM"
  OUT="$(run_on_vm "$WORKDIR/backups.sh" /tmp/backups.sh)"
  printf '%s\n' "$OUT" | sed 's/^/    /'

  if printf '%s' "$OUT" | grep -q "0 \*/4 \* \* \*"; then
    ok "the backup job is scheduled every 4 hours"
  else
    note_fail "the cron job was not added"
  fi

  info "checking the bucket"
  gcloud storage ls "gs://$BUCKET" --project="$PROJECT_ID" 2>/dev/null | sed 's/^/      /'
  if gcloud storage ls "gs://$BUCKET" --project="$PROJECT_ID" 2>/dev/null | grep -q "world"; then
    ok "the backup is in the bucket"
  else
    warn "the bucket does not show a world folder yet"
    dim "  the first backup can take a minute - check gs://$BUCKET"
  fi

  pause_for_check 5 "Schedule regular backups"
}

# ---------------------------------------------------------------------------
# Task 6 - server maintenance
# ---------------------------------------------------------------------------
task6() {
  step "Task 6 - Server maintenance"

  if instance_exists "$VM" "$ZONE"; then
    info "stopping the Minecraft server"
    gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT_ID" --quiet \
      --command="sudo screen -r -X stuff '/stop\\n' >/dev/null 2>&1; sleep 5; pgrep -f server.jar >/dev/null && sudo screen -S mcs -X stuff '/stop\\n' || true" \
      >/dev/null 2>&1
    ok "the Minecraft server has been asked to stop"
  fi

  info "adding the startup and shutdown scripts to the instance metadata"
  if gcloud compute instances add-metadata "$VM" \
       --metadata "startup-script-url=$STARTUP_URL,shutdown-script-url=$SHUTDOWN_URL,project-id=$PROJECT_ID" \
       --zone="$ZONE" --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "startup-script-url and shutdown-script-url are set"
  else
    note_fail "could not add the metadata"
    return 1
  fi

  dim ""
  dim "  startup-script-url  -> mounts the disk and starts the server in screen"
  dim "  shutdown-script-url -> stops the server gracefully before the VM stops"

  if [ "$STOP_VM" = "1" ]; then
    info "stopping $VM, the way the lab does"
    gcloud compute instances stop "$VM" --zone="$ZONE" --project="$PROJECT_ID" \
      --quiet >/dev/null 2>&1 && ok "$VM is stopped"
  else
    cat <<EOF

  ${C_DIM}The lab also stops the VM for maintenance. The script leaves it running${C_RESET}
  ${C_DIM}so the earlier checkpoints stay valid. To stop it too, run:${C_RESET}
    ${C_CYAN}./gsp_minecraft.sh --stop-vm${C_RESET}
  ${C_DIM}or stop it by hand:${C_RESET}
    ${C_CYAN}gcloud compute instances stop $VM --zone=$ZONE${C_RESET}

EOF
  fi

  pause_for_check 6 "Server maintenance"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  3) task3 ;;
  4) task4 ;;
  5) task5 ;;
  6) task6 ;;
  "")
    task1
    task2
    task3
    task4
    task5
    task6
    ;;
  *)
    err "--task must be between 1 and 6"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project     : $PROJECT_ID"
echo "  Zone        : $ZONE   (region $REGION)"
echo "  VM          : $VM  e2-medium, tag $TAG"
echo "  Data disk   : $DISK  50 GB pd-ssd, mounted on $MOUNT_DIR"
echo "  Static IP   : $ADDRESS = $IP_ADDR"
echo "  Firewall    : $RULE  tcp:$PORT -> $TAG"
echo "  Bucket      : gs://$PROJECT_ID-$BUCKET_SUFFIX"
echo "  Backups     : 0 */4 * * * $MOUNT_DIR/backup.sh"
echo ""
echo "  Checkpoints:"
echo "    1. Create the VM and prepare the data disk                             (20)"
echo "    2. Install the Java Runtime Environment (JRE) and the Minecraft server  (20)"
echo "    3. Allow client traffic                                                (20)"
echo "    4. Schedule regular backups                                             (20)"
echo "    5. Server maintenance                                                   (20)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  The server address is $IP_ADDR - test it at https://mcsrvstat.us/server/$IP_ADDR"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
