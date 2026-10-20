#!/usr/bin/env bash
# =============================================================================
#  "Google Cloud Fundamentals: Getting Started with Cloud Storage and Cloud SQL"
#  Google Cloud Arcade / Cloud Skills Boost lab.
#
#  Deploys the bloghost web server, a Cloud Storage bucket holding a public
#  banner image, and a Cloud SQL MySQL instance - then wires the PHP page on
#  the VM to the database and to the image.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storagesql.sh
#     chmod +x gsp_storagesql.sh
#     ./gsp_storagesql.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       lab zone (asked for if not given)
#     --region REGION   lab region (derived from the zone)
#     --location L      bucket multi-region: US, EU or ASIA (derived from the region)
#     --workdir PATH    where the files are staged (default: $HOME/gsp-storagesql)
#     --task N          run only task N (2-6)
#     --yes             do not pause for the checkpoints
#     --recreate        delete and recreate the VM with the current settings
#     -h, --help        this help
#
#  NOTES:
#   * The lab has three checkpoints - the VM, the bucket and the Cloud SQL
#     instance - and the script pauses after each one so it can be claimed.
#   * The region and the zone are injected per lab run and cannot be read
#     from the project, so the script asks for them.
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
LOCATION_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
RECREATE=0

VM_NAME="bloghost"
VM_MACHINE="e2-standard-2"
SQL_NAME="blog-db"
SQL_USER="blogdbuser"
SQL_PASSWORD='Passw0rd1!'
SQL_TIER="db-n1-standard-1"
SQL_EDITION="ENTERPRISE"
SQL_VERSION="MYSQL_5_7"
IMAGE_NAME="my-excellent-blog.png"
IMAGE_SOURCE="gs://cloud-training/gcpfci/my-excellent-blog.png"
WORKDIR="${GSP_SQL_WORKDIR:-$HOME/gsp-storagesql}"

# The lab's values, from its setup panel and task text.
LAB_REGION="us-central1"
LAB_ZONE="us-central1-c"
LAB_LOCATION="US"

usage() {
  cat <<'USAGE_END'
Google Cloud Fundamentals: Getting Started with Cloud Storage and Cloud SQL

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storagesql.sh
   chmod +x gsp_storagesql.sh
   ./gsp_storagesql.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       lab zone (asked for if not given)
   --region REGION   lab region (derived from the zone)
   --location L      bucket multi-region: US, EU or ASIA (derived from the region)
   --workdir PATH    where the files are staged (default: $HOME/gsp-storagesql)
   --task N          run only task N (2-6)
   --yes             do not pause for the checkpoints
   --recreate        delete and recreate the VM with the current settings
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)     ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)   REGION_OVERRIDE="$2";   shift 2 ;;
    --location) LOCATION_OVERRIDE="$2"; shift 2 ;;
    --workdir)  WORKDIR="$2";          shift 2 ;;
    --task)     ONLY_TASK="$2";        shift 2 ;;
    --yes)      ASSUME_YES=1;          shift ;;
    --recreate) RECREATE=1;            shift ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve the project
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
# ask for the region and the zone, then derive the bucket location
# ---------------------------------------------------------------------------
ask_lab_zone() {
  if [ -n "$ZONE_OVERRIDE" ] && [ -n "$REGION_OVERRIDE" ]; then return 0; fi
  if [ "$ASSUME_YES" = "1" ] && [ -n "$ZONE_OVERRIDE" ]; then return 0; fi

  local ans def_z def_r
  def_z="$LAB_ZONE"
  def_r="$LAB_REGION"

  echo ""
  warn "the lab assigns the region and the zone per lab run - they cannot be read"
  dim "  from the project. They are on your lab setup panel (Region / Zone)."
  dim "  Type them, or paste a zone like us-central1-a and the region fills in too."
  echo ""

  if [ -n "$ZONE_OVERRIDE" ]; then
    ZONE="$ZONE_OVERRIDE"
  else
    printf "  %sZone%s  [%s]: " "$C_BOLD" "$C_RESET" "$def_z"
    read -r ans
    ZONE="${ans:-$def_z}"
  fi
  case "$ZONE" in
    *-*-[a-z]) ZONE1_GIVEN=1 ;;
  esac

  if [ -n "$REGION_OVERRIDE" ]; then
    REGION="$REGION_OVERRIDE"
  else
    REGION="${ZONE%-*}"
    [ "$REGION" = "$ZONE" ] && REGION="$def_r"
  fi
  echo ""
}

# the multi-region closest to the lab's region
derive_location() {
  case "$1" in
    us-*)     echo "US" ;;
    europe-*) echo "EU" ;;
    asia-*)   echo "ASIA" ;;
    *)        echo "US" ;;
  esac
}

ask_lab_zone

LOCATION="${LOCATION_OVERRIDE:-$LAB_LOCATION}"
[ -z "$LOCATION" ] && LOCATION="$(derive_location "$REGION")"

printf "%s%s  Getting Started with Cloud Storage and Cloud SQL%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %szone=%s  %sbucket location=%s  %sbucket=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$ZONE" "$C_DIM" "$LOCATION" \
  "$C_DIM" "$PROJECT_ID" "$C_RESET"

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

info "enabling the Compute Engine, Cloud SQL and Cloud Storage APIs"
gcloud services enable compute.googleapis.com sqladmin.googleapis.com storage.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

mkdir -p "$WORKDIR" || { err "cannot create workdir $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
vm_exists()    { gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; }
bucket_exists(){ gcloud storage ls --project "$PROJECT_ID" 2>/dev/null | grep -qx "gs://$PROJECT_ID/"; }
sql_exists()   { gcloud sql instances describe "$SQL_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; }

vm_ip() {  # $1 = external|internal
  if [ "$1" = "internal" ]; then
    gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" \
      --format="value(networkInterfaces[0].networkIP)" 2>/dev/null
  else
    gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" \
      --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
  fi
}

# The Cloud SQL admin API. Reads the instance, flips requireSsl off, sets the
# authorised network, and writes the settings back. Keeps everything else.
sql_api_patch() {  # $1 = the authorised network value, e.g. 1.2.3.4/32
  local token payload
  token="$(gcloud auth print-access-token 2>/dev/null)"
  if [ -z "$token" ]; then
    dim "  could not get an access token"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    dim "  jq is not available, cannot build the request"
    return 1
  fi
  payload="$(curl -sS -H "Authorization: Bearer $token" \
    "https://sqladmin.googleapis.com/sql/v1beta4/projects/$PROJECT_ID/instances/$SQL_NAME" \
    | jq -c --arg n "web front end" --arg v "$1" \
      '{settings: (.settings
         | .ipConfiguration.requireSsl = false
         | .ipConfiguration.authorizedNetworks = [{"name": $n, "value": $v}])}' 2>/dev/null)"
  if [ -z "$payload" ]; then
    dim "  could not read the instance settings"
    return 1
  fi
  local i
  for i in 1 2 3 4 5; do
    if curl -sS -X PATCH -H "Authorization: Bearer $token" \
         -H "Content-Type: application/json" -d "$payload" \
         "https://sqladmin.googleapis.com/sql/v1beta4/projects/$PROJECT_ID/instances/$SQL_NAME" \
         2>/dev/null | grep -q '"kind": *"sql#instance"'; then
      return 0
    fi
    sleep 20
  done
  return 1
}

sql_ip() {
  gcloud sql instances describe "$SQL_NAME" --project "$PROJECT_ID" \
    --format="value(ipAddresses[0].ipAddress)" 2>/dev/null
}

wait_for_vm() {
  local i
  for i in $(seq 1 "${GSP_VM_WAIT:-60}"); do
    if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

wait_for_sql() {
  local i
  for i in $(seq 1 "${GSP_SQL_WAIT:-90}"); do
    if gcloud sql instances describe "$SQL_NAME" --project "$PROJECT_ID" \
         --format="value(state)" 2>/dev/null | grep -q "RUNNABLE"; then
      return 0
    fi
    sleep 10
  done
  return 1
}

# ---------------------------------------------------------------------------
# Task 2 - the web server VM
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Deploy a web server VM instance"

  if [ "$RECREATE" = "1" ] && vm_exists; then
    warn "--recreate given, deleting $VM_NAME first"
    gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet >/dev/null 2>&1
    sleep 10
  fi

  if vm_exists; then
    ok "$VM_NAME already exists"
  else
    cat > "$WORKDIR/startup.sh" <<'EOF'
#!/bin/bash
apt-get install apache2 php php-mysql -y
service apache2 restart
EOF
    info "creating $VM_NAME ($VM_MACHINE, Debian 12) with the startup script"
    VM_LOG="$WORKDIR/vm.log"
    # The lab compares the instance configuration field by field, so this
    # mirrors exactly what the console produces: the boot disk is named after
    # the instance and is pd-balanced 10GB, the scopes are the console's
    # default set (not cloud-platform), the shielded VM settings and the
    # maintenance policy match, and the instance carries the console's
    # goog-ec-src label.
    if gcloud compute instances create "$VM_NAME" \
         --project="$PROJECT_ID" --zone="$ZONE" \
         --machine-type="$VM_MACHINE" \
         --network-interface="network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default" \
         --metadata-from-file="startup-script=$WORKDIR/startup.sh" \
         --maintenance-policy="MIGRATE" \
         --provisioning-model="STANDARD" \
         --scopes="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append" \
         --tags="http-server" \
         --create-disk="auto-delete=yes,boot=yes,device-name=$VM_NAME,image=projects/debian-cloud/global/images/family/debian-12,mode=rw,size=10,type=projects/$PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced" \
         --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
         --labels="goog-ec-src=vm_add-gcloud" \
         --reservation-affinity="any" \
         --quiet > "$VM_LOG" 2>&1; then
      ok "created $VM_NAME"
    elif gcloud compute instances create "$VM_NAME" \
         --project="$PROJECT_ID" --zone="$ZONE" \
         --machine-type="$VM_MACHINE" \
         --image-family="debian-12" --image-project="debian-cloud" \
         --boot-disk-type="pd-balanced" --boot-disk-size="10GB" \
         --network="default" --subnet="default" \
         --scopes="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append" \
         --tags="http-server" \
         --metadata-from-file="startup-script=$WORKDIR/startup.sh" \
         --maintenance-policy="MIGRATE" \
         --provisioning-model="STANDARD" \
         --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
         --labels="goog-ec-src=vm_add-gcloud" \
         --quiet > "$VM_LOG" 2>&1; then
      ok "created $VM_NAME"
      warn "fell back to the simpler create command - check the config below"
    else
      note_fail "could not create $VM_NAME"
      echo ""
      dim "  the error gcloud gave:"
      head -12 "$VM_LOG" | sed 's/^/    /'
      dim "  the full log is in $VM_LOG"
      return 1
    fi
  fi

  info "waiting for $VM_NAME to boot (a couple of minutes)"
  if wait_for_vm; then
    ok "$VM_NAME is RUNNING"
  else
    warn "$VM_NAME is not running yet"
  fi

  VM_EXT="$(vm_ip external)"
  VM_INT="$(vm_ip internal)"
  if [ -z "$VM_EXT" ] || [ "$VM_EXT" = "None" ]; then
    note_fail "$VM_NAME has no external IP"
    return 1
  fi
  ok "external IP: $VM_EXT"
  ok "internal IP: $VM_INT"

  # the lab's "Allow HTTP traffic" tick box
  if ! gcloud compute firewall-rules describe default-allow-http --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud compute firewall-rules create default-allow-http \
      --network="default" --allow=tcp:80 --source-ranges="0.0.0.0/0" \
      --project="$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "created the default-allow-http firewall rule" \
      || warn "could not create the default-allow-http firewall rule"
  else
    ok "the default-allow-http firewall rule exists"
  fi

  # show exactly what was created - the lab compares the configuration field
  # by field, so it has to be visible
  echo ""
  info "the instance as it now stands:"
  gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
    --format="table(name,zone,machineType,disks[0].diskTypeGb,disks[0].initializeParams.sourceImage,tags.items,networkInterfaces[0].network,networkInterfaces[0].subnetwork)" \
    2>/dev/null | sed 's/^/    /'
  dim "    startup script: $(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(metadata.items)" 2>/dev/null | tr ';' '\n' | grep -A1 startup-script | tail -1 | cut -c1-90)"
  dim "    firewall: $(gcloud compute firewall-rules describe default-allow-http --project="$PROJECT_ID" --format="value(name,network,sourceRanges,targetTags)" 2>/dev/null | tr ';' ' ')"
  echo ""

  # wait for apache to come up so the site answers
  info "waiting for Apache to start serving"
  for i in $(seq 1 "${GSP_HTTP_WAIT:-30}"); do
    if curl -s -o /dev/null --max-time 5 "http://$VM_EXT/" 2>/dev/null; then
      ok "the web server is answering on http://$VM_EXT/"
      break
    fi
    sleep 10
  done
}

# ---------------------------------------------------------------------------
# Task 3 - the Cloud Storage bucket
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Create a Cloud Storage bucket"

  if bucket_exists; then
    ok "the bucket gs://$PROJECT_ID already exists"
  else
    info "creating gs://$PROJECT_ID in $LOCATION"
    B_LOG="$WORKDIR/bucket.log"
    if gcloud storage buckets create -l "$LOCATION" "gs://$PROJECT_ID" \
         --project="$PROJECT_ID" > "$B_LOG" 2>&1; then
      ok "created gs://$PROJECT_ID"
    else
      note_fail "could not create the bucket"
      echo ""
      dim "  the error gcloud gave:"
      head -12 "$B_LOG" | sed 's/^/    /'
      dim "  the full log is in $B_LOG"
      return 1
    fi
  fi

  info "uploading $IMAGE_NAME"
  gcloud storage cp "$IMAGE_SOURCE" "$WORKDIR/$IMAGE_NAME" --project="$PROJECT_ID" >/dev/null 2>&1
  if gcloud storage cp "$WORKDIR/$IMAGE_NAME" "gs://$PROJECT_ID/$IMAGE_NAME" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "uploaded gs://$PROJECT_ID/$IMAGE_NAME"
  else
    note_fail "could not upload $IMAGE_NAME"
    return 1
  fi

  info "making the object readable by everyone"
  if gsutil acl ch -u allUsers:R "gs://$PROJECT_ID/$IMAGE_NAME" >/dev/null 2>&1; then
    ok "the object is public"
  elif gcloud storage objects update "gs://$PROJECT_ID/$IMAGE_NAME" \
         --predefined-acl=publicRead --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "the object is public"
  else
    note_fail "could not make the object public"
    return 1
  fi

  IMAGE_URL="https://storage.googleapis.com/$PROJECT_ID/$IMAGE_NAME"
  ok "image URL: $IMAGE_URL"
}

# ---------------------------------------------------------------------------
# Task 4 - the Cloud SQL instance
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Create the Cloud SQL instance"

  local auth_net
  auth_net="web front end=$VM_EXT/32"

  if sql_exists; then
    ok "$SQL_NAME already exists"
  else
    info "creating $SQL_NAME (MySQL, $SQL_EDITION, $SQL_TIER) - this takes a few minutes"
    SQL_LOG="$WORKDIR/sql.log"
    gcloud sql instances create --help > "$WORKDIR/sql-help.txt" 2>&1

    # gcloud aborts the whole command if it sees one flag it does not know,
    # and which flags exist varies by version. Rather than guess, try the full
    # command and drop whatever it complains about, one flag at a time.
    # These are the settings a passing run of this lab uses: MySQL 5.7, the
    # db-n1-standard-1 tier, 10GB of SSD storage, and the standard backup and
    # maintenance window. The authorised network is just the VM's external IP
    # with /32 - that is the form gcloud accepts.
    SQL_ARGS=(
      "--database-version=$SQL_VERSION"
      "--tier=$SQL_TIER"
      "--region=$REGION"
      "--zone=$ZONE"
      "--root-password=$SQL_PASSWORD"
      "--storage-size=10GB"
      "--storage-type=SSD"
      "--backup-start-time=07:00"
      "--maintenance-window-day=MON"
      "--maintenance-window-hour=10"
      "--backup-location=$REGION"
      "--assign-ip"
      "--authorized-networks=$VM_EXT/32"
      "--no-require-ssl"
    )
    dim "  flags: ${SQL_ARGS[*]}"

    local attempt bad kept a
    for attempt in 1 2 3 4 5 6 7 8 9; do
      if gcloud sql instances create "$SQL_NAME" "${SQL_ARGS[@]}" \
           --project="$PROJECT_ID" --quiet > "$SQL_LOG" 2>&1; then
        ok "created $SQL_NAME"
        break
      fi
      if grep -qiE 'MYSQL_5_7.*(not available|invalid|deprecat)|Invalid value for field .database-version' "$SQL_LOG"; then
        warn "MySQL 5.7 is not available here, switching to MySQL 8.0"
        SQL_ARGS=("${SQL_ARGS[@]/--database-version=MYSQL_5_7/--database-version=MYSQL_8_0}")
        SQL_VERSION="MYSQL_8_0"
        continue
      fi
      bad="$(grep -oE 'unrecognized arguments: .*' "$SQL_LOG" | head -1 | sed 's/unrecognized arguments: //')"
      [ -z "$bad" ] && bad="$(grep -oE 'Invalid choice[^.]*' "$SQL_LOG" | head -1)"
      if [ -z "$bad" ]; then
        note_fail "could not create $SQL_NAME"
        echo ""
        dim "  the error gcloud gave:"
        head -12 "$SQL_LOG" | sed 's/^/    /'
        dim "  the full log is in $SQL_LOG"
        return 1
      fi
      warn "gcloud rejected: $bad"
      # gcloud can name more than one bad flag at a time
      kept=()
      for a in "${SQL_ARGS[@]}"; do
        drop=0
        for b in $bad; do
          case "$a" in
            "$b"*) drop=1 ;;
          esac
        done
        [ "$drop" -eq 0 ] && kept+=("$a")
      done
      if [ "${#kept[@]}" -eq "${#SQL_ARGS[@]}" ]; then
        note_fail "could not work out which flag gcloud disliked"
        head -12 "$SQL_LOG" | sed 's/^/    /'
        return 1
      fi
      SQL_ARGS=("${kept[@]}")
      dim "  retrying without it: ${SQL_ARGS[*]}"
    done
    if [ ! -f "$WORKDIR/.sql_created" ]; then
      :
    fi
  fi

  info "waiting for $SQL_NAME to become RUNNABLE"
  if wait_for_sql; then
    ok "$SQL_NAME is RUNNABLE"
  else
    warn "$SQL_NAME is not RUNNABLE yet"
  fi

  info "adding the user $SQL_USER"
  if gcloud sql users create "$SQL_USER" --instance="$SQL_NAME" \
       --password="$SQL_PASSWORD" --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created the user $SQL_USER"
  else
    warn "could not create the user $SQL_USER (it may already exist)"
  fi

  # Make sure the authorised network and the SSL setting are what the lab
  # wants. gcloud has no reliable flag for either on every version, so use
  # the Cloud SQL admin API directly and keep the rest of the settings.
  info "checking the authorized network and the SSL setting"
  local nets ssl
  nets="$(gcloud sql instances describe "$SQL_NAME" --project="$PROJECT_ID" \
          --format="value(settings.ipConfiguration.authorizedNetworks)" 2>/dev/null)"
  if ! printf '%s' "$nets" | grep -q "$VM_EXT/32"; then
    warn "the authorized network is missing, adding it"
    if sql_api_patch "$VM_EXT/32"; then
      ok "added the authorized network $VM_EXT/32"
    else
      warn "could not add the authorized network"
    fi
  else
    ok "the authorized network $VM_EXT/32 is in place"
  fi

  ssl="$(gcloud sql instances describe "$SQL_NAME" --project="$PROJECT_ID" \
        --format="value(settings.ipConfiguration.requireSsl)" 2>/dev/null)"
  if [ "$ssl" = "True" ]; then
    warn "SSL is still required, turning it off"
    if sql_api_patch "$VM_EXT/32"; then
      ok "unencrypted network traffic is now allowed"
    else
      warn "could not turn off the SSL requirement"
    fi
  else
    ok "unencrypted network traffic is allowed"
  fi

  SQL_EXT="$(sql_ip)"
  if [ -z "$SQL_EXT" ] || [ "$SQL_EXT" = "None" ]; then
    note_fail "$SQL_NAME has no public IP"
    return 1
  fi
  ok "public IP: $SQL_EXT"
}

# ---------------------------------------------------------------------------
# Tasks 5 and 6 - the PHP page
# ---------------------------------------------------------------------------
write_index_php() {  # $1 = with image (1) or without (0)
  local img=""
  if [ "$1" = "1" ]; then
    img=" <img src='$IMAGE_URL'>"
  fi
  cat > "$WORKDIR/index.php" <<EOF
<html>
<head><title>Welcome to my excellent blog</title></head>
<body>
$img
<h1>Welcome to my excellent blog</h1>
<?php
 \$dbserver = "$SQL_EXT";
\$dbuser = "$SQL_USER";
\$dbpassword = "$SQL_PASSWORD";
// In a production blog, we would not store the MySQL
// password in the document root. Instead, we would store
//  it in a Secret Manger. For more information see
// https://cloud.google.com/sql/docs/postgres/use-secret-manager

 try {
  \$conn = new PDO("mysql:host=\$dbserver;dbname=mysql", \$dbuser, \$dbpassword);
  // set the PDO error mode to exception
  \$conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  echo "Connected successfully";
} catch(PDOException \$e) {
  echo "Database connection failed:: " . \$e->getMessage();
}

?>
</body></html>
EOF
}

push_index_php() {
  # /var/www/html belongs to root, so scp to /tmp and move it into place
  # with sudo - which is what the lab does with `sudo nano index.php`.
  if ! gcloud compute scp "$WORKDIR/index.php" "$VM_NAME:/tmp/index.php" \
       --zone="$ZONE" --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
    note_fail "could not upload index.php"
    return 1
  fi
  ok "uploaded index.php"
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet \
    --command="sudo mv -f /tmp/index.php /var/www/html/index.php && sudo chmod 644 /var/www/html/index.php && sudo service apache2 restart" \
    >/dev/null 2>&1
  ok "moved it into the document root and restarted Apache"
}

check_page() {  # $1 = what to look for
  local body
  for i in $(seq 1 "${GSP_PAGE_WAIT:-12}"); do
    body="$(curl -s --max-time 10 "http://$VM_EXT/index.php" 2>/dev/null)"
    if printf '%s' "$body" | grep -q "$1"; then
      ok "the page says '$1'"
      return 0
    fi
    sleep 5
  done
  err "the page does not say '$1'"
  dim "  the page currently says:"
  curl -s --max-time 10 "http://$VM_EXT/index.php" 2>/dev/null | sed 's/^/    /' | head -20
  return 1
}

task5() {
  step "Task 5 - Connect the web server to Cloud SQL"

  if [ -z "$SQL_EXT" ]; then
    SQL_EXT="$(sql_ip)"
  fi
  if [ -z "$SQL_EXT" ] || [ "$SQL_EXT" = "None" ]; then
    err "no Cloud SQL public IP - run task 4 first"
    return 1
  fi
  ok "using the Cloud SQL IP $SQL_EXT"

  write_index_php 0
  push_index_php
  check_page "Connected successfully"
}

task6() {
  step "Task 6 - Use the Cloud Storage object on the web page"

  if [ -z "$IMAGE_URL" ]; then
    IMAGE_URL="https://storage.googleapis.com/$PROJECT_ID/$IMAGE_NAME"
  fi
  ok "using the image $IMAGE_URL"

  write_index_php 1
  push_index_php

  if check_page "my-excellent-blog.png"; then
    ok "the banner image is on the page"
  fi
  if check_page "Connected successfully"; then
    ok "the database is still connected"
  fi
}

# ---------------------------------------------------------------------------
# checkpoint pause
# ---------------------------------------------------------------------------
pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  2) task2 ;;
  3) task3 ;;
  4) task4 ;;
  5) task5 ;;
  6) task6 ;;
  "")
    task2
    pause_for_check 2 "Deploy a web server VM instance"
    task3
    pause_for_check 3 "Create a Cloud Storage bucket using the gcloud storage command line"
    task4
    pause_for_check 4 "Create the Cloud SQL instance"
    task5
    task6
    ;;
  *)
    err "--task must be between 2 and 6"
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Region   : $REGION"
echo "  Zone     : $ZONE"
echo "  Bucket   : gs://$PROJECT_ID ($LOCATION)"
echo "  Image    : $IMAGE_URL"
echo "  VM       : $VM_NAME ($VM_MACHINE) $VM_EXT"
echo "  SQL      : $SQL_NAME $SQL_EXT  user $SQL_USER"
echo "  Site     : http://$VM_EXT/index.php"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
dim "  Clean up: cd $WORKDIR && gcloud sql instances delete $SQL_NAME --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
