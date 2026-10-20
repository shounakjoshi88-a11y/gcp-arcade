#!/usr/bin/env bash
# =============================================================================
#  "Create Virtual Machines"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19090).
#
#  Creates the three VMs the lab asks for:
#    utility-vm   a shared-core e2-medium with no external IP
#    utility-wm   a Windows Server 2025 e2-standard-2 on an SSD boot disk
#    utility-cm   a custom machine type with 2 vCPU and 4 GB
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_create_vms.sh
#     chmod +x gsp_create_vms.sh
#     ./gsp_create_vms.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       the lab's zone (asked for)
#     --region REGION   region (default: derived from the zone)
#     --image IMAGE     the Linux boot disk image family (default: from the project)
#     --cores N         cores for the custom machine type (default: 2)
#     --memory MB       memory for the custom machine type (default: 4096)
#     --windows-family F  the Windows image family (default: resolved at run time)
#     --task N          run only task N (1-3)
#     --yes             do not pause for the checkpoints
#     --no-verify       skip the SSH checks
#     -h, --help        this help
#
#  CHECKPOINTS (100 points):
#     1. Create a utility virtual machine   (30)
#     2. Create a Windows virtual machine   (30)
#     3. Create a custom virtual machine    (40)
#
#  NOTES:
#   * The zone is injected by the lab per run, so the script asks for it.
#   * The Windows image family is resolved at run time, because Google
#     renames those families between releases.
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
WINDOWS_FAMILY_OVERRIDE=""
CORES=2
MEMORY_MB=4096
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Create Virtual Machines

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_create_vms.sh
   chmod +x gsp_create_vms.sh
   ./gsp_create_vms.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       the lab's zone (asked for)
   --region REGION   region (default: derived from the zone)
   --image IMAGE     the Linux boot disk image family (default: from the project)
   --cores N         cores for the custom machine type (default: 2)
   --memory MB       memory for the custom machine type (default: 4096)
   --windows-family F  the Windows image family (default: resolved at run time)
   --task N          run only task N (1-3)
   --yes             do not pause for the checkpoints
   --no-verify       skip the SSH checks
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)        PROJECT_OVERRIDE="$2";        shift 2 ;;
    --zone)           ZONE_OVERRIDE="$2";           shift 2 ;;
    --region)         REGION_OVERRIDE="$2";         shift 2 ;;
    --image)          IMAGE_OVERRIDE="$2";          shift 2 ;;
    --cores)          CORES="$2";                    shift 2 ;;
    --memory)         MEMORY_MB="$2";                shift 2 ;;
    --windows-family) WINDOWS_FAMILY_OVERRIDE="$2"; shift 2 ;;
    --task)           ONLY_TASK="$2";               shift 2 ;;
    --yes)            ASSUME_YES=1;                 shift ;;
    --no-verify)      DO_VERIFY=0;                  shift ;;
    -h|--help)        usage ;;
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

# ---------------------------------------------------------------------------
# images
# ---------------------------------------------------------------------------
resolve_linux_image() {
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
IMAGE="$(resolve_linux_image)"

# Google renames the Windows image families between releases, so the family
# is looked up instead of hardcoded.
resolve_windows_family() {
  if [ -n "$WINDOWS_FAMILY_OVERRIDE" ]; then echo "$WINDOWS_FAMILY_OVERRIDE"; return 0; fi
  local f
  for f in windows-2025 windows-2025-datacenter-core windows-2022 windows-2019; do
    if gcloud compute images describe-from-family "$f" \
         --project windows-cloud --zone "$ZONE" >/dev/null 2>&1; then
      echo "$f"
      return 0
    fi
  done
  gcloud compute images list --project windows-cloud \
    --filter="family:windows-2025" --format="value(family)" 2>/dev/null | head -1
}
WINDOWS_FAMILY="$(resolve_windows_family)"
if [ -z "$WINDOWS_FAMILY" ]; then
  WINDOWS_FAMILY="windows-2025"
  warn "could not look up the Windows image family, falling back to $WINDOWS_FAMILY"
fi

# ---------------------------------------------------------------------------
# names
# ---------------------------------------------------------------------------
VM_UTIL="utility-vm"
VM_WIN="utility-wm"
VM_CUSTOM="utility-cm"

# The console's "Series E2" + "Custom" + 2 cores + 4 GB is e2-custom-2-4096.
# The gcloud flags --custom-cpu / --custom-memory build the type off the
# DEFAULT machine type, which is n1-standard-1 - so they alone would give
# n1-custom-2-4096 and the lab would not score it. The family has to be
# spelled out.
MT_UTIL="e2-medium"
MT_WIN="e2-standard-2"
MT_CUSTOM="e2-custom-${CORES}-${MEMORY_MB}"

printf "%s%s  Create Virtual Machines%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %sregion=%s  %simage=%s  %swindows=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$REGION" "$C_DIM" "$IMAGE" \
  "$C_DIM" "$WINDOWS_FAMILY" "$C_RESET"
printf "  %smachine types:%s %s (%s), %s (%s), %s (%s cores / %s MB)%s\n" \
  "$C_DIM" "$C_DIM" "$VM_UTIL" "$MT_UTIL" "$VM_WIN" "$MT_WIN" "$VM_CUSTOM" \
  "$CORES" "$MEMORY_MB" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
instance_exists() {
  gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}
rule_exists() {
  gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}
network_exists() {
  gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
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

instance_machine_type() {  # $1 = instance name
  gcloud compute instances describe "$1" --zone "$ZONE" --project "$PROJECT_ID" \
    --format="value(machineType)" 2>/dev/null | sed 's|.*/||'
}

# A machine type cannot be changed while the instance runs, so an instance
# with the wrong one has to be replaced.
ensure_machine_type() {  # $1 = instance name, $2 = wanted machine type
  local have
  [ -z "$2" ] && return 0
  have="$(instance_machine_type "$1")"
  if [ -n "$have" ] && [ "$have" != "$2" ]; then
    warn "$1 has machine type '$have' but the lab wants '$2'"
    info "deleting it - the machine type of a running instance cannot be changed"
    if gcloud compute instances delete "$1" --zone "$ZONE" --project "$PROJECT_ID" \
         --quiet >/dev/null 2>&1; then
      ok "deleted $1"
    else
      note_fail "could not delete $1 - delete it by hand and re-run"
      return 1
    fi
  fi
  return 0
}

# Print what the lab grader would look at, so it can be compared with the
# console's Details page.
show_vm() {  # $1 = instance name
  local name="$1" disk img disk_type disk_size ip tags
  disk="$(gcloud compute instances describe "$name" --zone "$ZONE" --project "$PROJECT_ID" \
          --flatten="disks" --format="value(disks.source)" 2>/dev/null | head -1 | sed 's|.*/||')"
  img=""; disk_type=""; disk_size=""
  if [ -n "$disk" ]; then
    img="$(gcloud compute disks describe "$disk" --zone "$ZONE" --project "$PROJECT_ID" \
           --format="value(sourceImage)" 2>/dev/null | sed 's|.*/||')"
    disk_type="$(gcloud compute disks describe "$disk" --zone "$ZONE" --project "$PROJECT_ID" \
                --format="value(type)" 2>/dev/null | sed 's|.*/||')"
    disk_size="$(gcloud compute disks describe "$disk" --zone "$ZONE" --project "$PROJECT_ID" \
                --format="value(sizeGb)" 2>/dev/null)"
  fi
  ip="$(gcloud compute instances describe "$name" --zone "$ZONE" --project "$PROJECT_ID" \
       --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"
  tags="$(gcloud compute instances describe "$name" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(tags.items)" 2>/dev/null | tr '\n' ',')"
  dim "  --- $name, as the grader sees it ---"
  printf "      machine type : %s\n" "$(instance_machine_type "$name")"
  printf "      image        : %s\n" "${img:-unknown}"
  printf "      boot disk    : %s %s GB\n" "${disk_type:-unknown}" "${disk_size:-?}"
  printf "      external IP  : %s\n" "${ip:-none}"
  printf "      tags         : %s\n" "${tags:-none}"
}

wait_running() {  # $1 = instance name
  local i
  for i in $(seq 1 40); do
    if gcloud compute instances describe "$1" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      return 0
    fi
    sleep 5
  done
  return 1
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

if network_exists "default"; then
  ok "the default network is there"
else
  warn "there is no default network - the VMs in this lab need one"
  dim "  create it with:  gcloud compute networks create default --subnet-mode=auto"
fi

# ---------------------------------------------------------------------------
# Task 1 - the utility VM
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create a utility virtual machine"

  if instance_exists "$VM_UTIL" "$ZONE"; then
    ensure_machine_type "$VM_UTIL" "$MT_UTIL" || return 1
    if instance_exists "$VM_UTIL" "$ZONE"; then
      ok "$VM_UTIL already exists in $ZONE"
    else
      gcloud compute instances create "$VM_UTIL" \
         --zone="$ZONE" --machine-type="$MT_UTIL" \
         --network-interface="network=default,subnet=default,no-address" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
         && ok "created $VM_UTIL (e2-medium, no external IP)" \
         || note_fail "could not create $VM_UTIL"
    fi
  else
    if gcloud compute instances create "$VM_UTIL" \
         --zone="$ZONE" \
         --machine-type="$MT_UTIL" \
         --network-interface="network=default,subnet=default,no-address" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $VM_UTIL (e2-medium, no external IP)"
    else
      note_fail "could not create $VM_UTIL"
      return 1
    fi
  fi

  info "waiting for $VM_UTIL to start"
  if wait_running "$VM_UTIL"; then
    ok "$VM_UTIL is RUNNING"
  else
    warn "$VM_UTIL did not report RUNNING in time"
  fi

  EXT_IP="$(gcloud compute instances describe "$VM_UTIL" --zone "$ZONE" --project "$PROJECT_ID" \
             --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"
  if [ -z "$EXT_IP" ] || [ "$EXT_IP" = "None" ]; then
    ok "$VM_UTIL has no external IP, as the lab wants"
  else
    warn "$VM_UTIL has an external IP ($EXT_IP) - it should not"
  fi

  # the exploration the lab asks for
  dim ""
  dim "  CPU platform and availability policies:"
  CPU_PLATFORM="$(gcloud compute instances describe "$VM_UTIL" --zone "$ZONE" \
                  --project "$PROJECT_ID" --format="value(cpuPlatform)" 2>/dev/null)"
  SCHEDULING="$(gcloud compute instances describe "$VM_UTIL" --zone "$ZONE" \
                --project "$PROJECT_ID" --flatten="scheduling" \
                --format="value(scheduling)" 2>/dev/null)"
  printf "      %s\n" "${CPU_PLATFORM:-unknown}"
  printf "      %s\n" "${SCHEDULING:-unknown}"
  dim "  the logs are at: Compute Engine > VM instances > $VM_UTIL > Logging"
  show_vm "$VM_UTIL"

  pause_for_check 1 "Create a utility virtual machine"
}

# ---------------------------------------------------------------------------
# Task 2 - the Windows VM
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create a Windows virtual machine"

  # Ticking "Allow HTTP traffic" and "Allow HTTPS traffic" in the console
  # creates these two rules and tags the instance.
  info "creating the HTTP and HTTPS firewall rules"
  create_www_rule() {  # $1 name, $2 port, $3 tag
    if rule_exists "$1"; then
      ok "$1 already exists"
      return 0
    fi
    if gcloud compute firewall-rules create "$1" \
         --network=default --direction=INGRESS --priority=1000 \
         --action=ALLOW --rules="tcp:$2" --source-ranges="0.0.0.0/0" \
         --target-tags="$3" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $1 (tcp:$2 -> tag $3)"
    else
      note_fail "could not create $1"
    fi
  }
  create_www_rule "default-allow-http"  80  "http-server"
  create_www_rule "default-allow-https" 443 "https-server"

  if instance_exists "$VM_WIN" "$ZONE"; then
    ensure_machine_type "$VM_WIN" "$MT_WIN" || return 1
    if instance_exists "$VM_WIN" "$ZONE"; then
      ok "$VM_WIN already exists in $ZONE"
    else
      gcloud compute instances create "$VM_WIN" \
         --zone="$ZONE" --machine-type="$MT_WIN" \
         --network-interface="network=default,subnet=default" \
         --image-family="$WINDOWS_FAMILY" --image-project=windows-cloud \
         --boot-disk-size=64 --boot-disk-type=pd-ssd \
         --tags="http-server,https-server" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
         && ok "created $VM_WIN (e2-standard-2, Windows Server 2025, 64 GB SSD)" \
         || note_fail "could not create $VM_WIN"
    fi
  else
    if gcloud compute instances create "$VM_WIN" \
         --zone="$ZONE" \
         --machine-type="$MT_WIN" \
         --network-interface="network=default,subnet=default" \
         --image-family="$WINDOWS_FAMILY" --image-project=windows-cloud \
         --boot-disk-size=64 --boot-disk-type=pd-ssd \
         --tags="http-server,https-server" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $VM_WIN (e2-standard-2, Windows Server 2025, 64 GB SSD)"
    else
      note_fail "could not create $VM_WIN"
      dim "  if the Windows image family is wrong, check the available ones:"
      dim "    gcloud compute images list --project windows-cloud --filter='family:windows-2025'"
      dim "  and re-run with:  ./gsp_create_vms.sh --windows-family <family>"
      return 1
    fi
  fi

  info "waiting for $VM_WIN to start (a Windows VM takes a minute or two)"
  if wait_running "$VM_WIN"; then
    ok "$VM_WIN is RUNNING"
  else
    warn "$VM_WIN did not report RUNNING in time"
  fi

  cat <<EOF

  ${C_DIM}The lab asks you to set a Windows password too. There is no gcloud${C_RESET}
  ${C_DIM}command for that, so do it in the console:${C_RESET}
    ${C_CYAN}Compute Engine > VM instances > $VM_WIN > Set Windows password${C_RESET}
  ${C_DIM}Copy the password it gives you and click Close. The lab does not${C_RESET}
  ${C_DIM}connect to the Windows VM - that needs an RDP client on your machine.${C_RESET}

EOF
  show_vm "$VM_WIN"

  pause_for_check 2 "Create a Windows virtual machine"
}

# ---------------------------------------------------------------------------
# Task 3 - the custom VM
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Create a custom virtual machine"

  if instance_exists "$VM_CUSTOM" "$ZONE"; then
    ensure_machine_type "$VM_CUSTOM" "$MT_CUSTOM" || return 1
    if instance_exists "$VM_CUSTOM" "$ZONE"; then
      ok "$VM_CUSTOM already exists in $ZONE"
    else
      gcloud compute instances create "$VM_CUSTOM" \
         --zone="$ZONE" --machine-type="$MT_CUSTOM" \
         --network-interface="network=default,subnet=default" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
         && ok "created $VM_CUSTOM ($MT_CUSTOM)" \
         || note_fail "could not create $VM_CUSTOM"
    fi
  else
    if gcloud compute instances create "$VM_CUSTOM" \
         --zone="$ZONE" \
         --machine-type="$MT_CUSTOM" \
         --network-interface="network=default,subnet=default" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $VM_CUSTOM (2 vCPU, 4 GB)"
    else
      note_fail "could not create $VM_CUSTOM"
      return 1
    fi
  fi

  info "waiting for $VM_CUSTOM to start"
  if wait_running "$VM_CUSTOM"; then
    ok "$VM_CUSTOM is RUNNING"
  else
    warn "$VM_CUSTOM did not report RUNNING in time"
  fi

  MT="$(instance_machine_type "$VM_CUSTOM")"
  ok "machine type: $MT"
  if [ "$MT" != "$MT_CUSTOM" ]; then
    note_fail "the machine type is $MT but the lab wants $MT_CUSTOM"
  fi

  if [ "$DO_VERIFY" = "1" ]; then
    info "checking the VM over SSH"
    OUT="$(gcloud compute ssh "$VM_CUSTOM" --zone "$ZONE" --project "$PROJECT_ID" --quiet \
             --command="nproc; free -m | head -2" 2>&1)"
    if printf '%s' "$OUT" | grep -qE '^[0-9]+$'; then
      ok "the VM reports $(printf '%s' "$OUT" | head -1) vCPU"
      dim "$(printf '%s' "$OUT" | sed -n '2p')"
    else
      warn "the SSH check did not answer - that is fine, the checkpoint is the VM itself"
    fi
  fi

  show_vm "$VM_CUSTOM"

  pause_for_check 3 "Create a custom virtual machine"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  3) task3 ;;
  "")
    task1
    task2
    task3
    ;;
  *)
    err "--task must be between 1 and 3"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project      : $PROJECT_ID"
echo "  Zone / Region: $ZONE  /  $REGION"
printf "  %-14s: %s, no external IP\n" "$VM_UTIL" "$MT_UTIL"
printf "  %-14s: %s, Windows Server 2025, 64 GB pd-ssd, tags http-server,https-server\n" "$VM_WIN" "$MT_WIN"
printf "  %-14s: %s (%s cores / %s MB)\n" "$VM_CUSTOM" "$MT_CUSTOM" "$CORES" "$MEMORY_MB"
echo ""
echo "  Checkpoints:"
echo "    1. Create a utility virtual machine   (30)"
echo "    2. Create a Windows virtual machine   (30)"
echo "    3. Create a custom virtual machine    (40)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute instances delete $VM_UTIL $VM_WIN $VM_CUSTOM --zone=$ZONE --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
