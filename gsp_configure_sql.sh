#!/usr/bin/env bash
# =============================================================================
#  "Configure Cloud SQL"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19086).
#
#  Creates the wordpress-db Cloud SQL instance with a Private IP connection,
#  creates the wordpress database, and runs the Cloud SQL Auth Proxy on the
#  wordpress-proxy VM.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_configure_sql.sh
#     chmod +x gsp_configure_sql.sh
#     ./gsp_configure_sql.sh
#
#  OPTIONS:
#     --project ID       GCP project (default: active gcloud project)
#     --password PASS    the Cloud SQL root password (asked for)
#     --instance NAME    the Cloud SQL instance (default: wordpress-db)
#     --database NAME    the database (default: wordpress)
#     --db-version VER   MYSQL_8_0 (default) or MYSQL_5_7
#     --proxy-vm NAME    the proxy VM (detected from the project)
#     --private-vm NAME  the private IP VM (detected from the project)
#     --task N           run only task N (1-2)
#     --yes              do not pause for the checkpoints
#     -h, --help         this help
#
#  CHECKPOINTS (100 points, 50 each):
#     1. Create a Cloud SQL instance
#     2. Create a database and configure a proxy on a Virtual Machine
#
#  NOTES:
#   * The lab pre-creates the two WordPress VMs, so the zone and the region
#     are read from the proxy VM instead of being asked for.
#   * The proxy is started with nohup so it keeps running after the SSH
#     session closes. The lab's own command would die with the shell.
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
PASSWORD_OVERRIDE=""
INSTANCE_OVERRIDE=""
DATABASE_OVERRIDE=""
DB_VERSION_OVERRIDE="MYSQL_8_0"
PROXY_VM_OVERRIDE=""
PRIVATE_VM_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0

WORKDIR="${GSP_SQL_WORKDIR:-$HOME/gsp-configure-sql}"
PSA_RANGE="default-ip-range"
PROXY_URL="https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64"

usage() {
  cat <<'USAGE_END'
Configure Cloud SQL

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_configure_sql.sh
   chmod +x gsp_configure_sql.sh
   ./gsp_configure_sql.sh

OPTIONS:
   --project ID       GCP project (default: active gcloud project)
   --password PASS    the Cloud SQL root password (asked for)
   --instance NAME    the Cloud SQL instance (default: wordpress-db)
   --database NAME    the database (default: wordpress)
   --db-version VER   MYSQL_8_0 (default) or MYSQL_5_7
   --proxy-vm NAME    the proxy VM (detected from the project)
   --private-vm NAME  the private IP VM (detected from the project)
   --task N           run only task N (1-2)
   --yes              do not pause for the checkpoints
   -h, --help         this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)     PROJECT_OVERRIDE="$2";     shift 2 ;;
    --password)    PASSWORD_OVERRIDE="$2";    shift 2 ;;
    --instance)    INSTANCE_OVERRIDE="$2";    shift 2 ;;
    --database)    DATABASE_OVERRIDE="$2";    shift 2 ;;
    --db-version)  DB_VERSION_OVERRIDE="$2";  shift 2 ;;
    --proxy-vm)    PROXY_VM_OVERRIDE="$2";    shift 2 ;;
    --private-vm)  PRIVATE_VM_OVERRIDE="$2";  shift 2 ;;
    --task)        ONLY_TASK="$2";            shift 2 ;;
    --yes)         ASSUME_YES=1;              shift ;;
    -h|--help)     usage ;;
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

INSTANCE="${INSTANCE_OVERRIDE:-wordpress-db}"
DATABASE="${DATABASE_OVERRIDE:-wordpress}"
DB_VERSION="${DB_VERSION_OVERRIDE:-MYSQL_8_0}"

mkdir -p "$WORKDIR" 2>/dev/null

# ---------------------------------------------------------------------------
# the two WordPress VMs the lab pre-creates
# ---------------------------------------------------------------------------
ALL_VMS="$(gcloud compute instances list --project "$PROJECT_ID" \
             --format="value(name,zone)" 2>/dev/null)"

find_vm() {  # $1 = a pattern
  echo "$ALL_VMS" | awk -v p="$1" '$1 ~ p { print $1; exit }'
}

PROXY_VM="${PROXY_VM_OVERRIDE:-$(find_vm proxy)}"
PRIVATE_VM="${PRIVATE_VM_OVERRIDE:-$(find_vm "private.ip")}"
[ -z "$PRIVATE_VM" ] && PRIVATE_VM="$(find_vm private)"

if [ -z "$PROXY_VM" ]; then
  err "could not find the proxy VM - the lab creates it for you"
  dim "  expected a VM whose name contains 'proxy'. The project has:"
  echo "$ALL_VMS" | sed 's/^/    /'
  dim "  pass it with --proxy-vm NAME"
  exit 1
fi

PROXY_ZONE="$(echo "$ALL_VMS" | awk -v v="$PROXY_VM" '$1 == v { print $2 }' | sed 's|.*/||')"
REGION="${PROXY_ZONE%-*}"
PRIVATE_ZONE=""
if [ -n "$PRIVATE_VM" ]; then
  PRIVATE_ZONE="$(echo "$ALL_VMS" | awk -v v="$PRIVATE_VM" '$1 == v { print $2 }' | sed 's|.*/||')"
fi

# ---------------------------------------------------------------------------
# the root password
# ---------------------------------------------------------------------------
if [ -z "$PASSWORD_OVERRIDE" ] && [ -f "$WORKDIR/root-password" ]; then
  PASSWORD_OVERRIDE="$(cat "$WORKDIR/root-password")"
fi
# Cloud SQL applies a password policy to new instances: at least 8
# characters, and usually a mix of upper case, lower case, digits and
# symbols. A short password is rejected by the API with an error that is
# easy to miss, so it is checked here first.
password_problems() {
  local p="$1" out=""
  [ ${#p} -lt 8 ] && out="at least 8 characters"
  echo "$p" | grep -q '[A-Z]'  || out="$out, an upper case letter"
  echo "$p" | grep -q '[a-z]'  || out="$out, a lower case letter"
  echo "$p" | grep -q '[0-9]'  || out="$out, a digit"
  echo "$p" | grep -q '[^A-Za-z0-9]' || out="$out, a symbol"
  echo "$out" | sed 's/^, //'
}

if [ -z "$PASSWORD_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  echo ""
  warn "the lab asks you to choose a root password for the Cloud SQL instance"
  dim "  you will need it for the WordPress setup form later, so pick one you remember"
  while true; do
    printf "  %sRoot password%s  [Passw0rd1!]: " "$C_BOLD" "$C_RESET"
    read -r ans || true
    PASSWORD_OVERRIDE="${ans:-Passw0rd1!}"
    echo ""
    PROBLEMS="$(password_problems "$PASSWORD_OVERRIDE")"
    if [ ${#PASSWORD_OVERRIDE} -lt 8 ]; then
      err "that password is ${#PASSWORD_OVERRIDE} characters - Cloud SQL needs at least 8"
      continue
    fi
    if [ -n "$PROBLEMS" ]; then
      warn "the Cloud SQL password policy may want: $PROBLEMS"
      printf "  %sUse it anyway? [y/N]%s " "$C_BOLD" "$C_RESET"
      read -r go || true
      echo ""
      case "$go" in
        y|Y|yes|YES) break ;;
        *) continue ;;
      esac
    fi
    break
  done
fi
PASSWORD="${PASSWORD_OVERRIDE:-Passw0rd1!}"
printf '%s' "$PASSWORD" > "$WORKDIR/root-password"

printf "%s%s  Configure Cloud SQL%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sinstance=%s  %sversion=%s  %sproxy-vm=%s  %szone=%s  %sregion=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$INSTANCE" "$C_DIM" "$DB_VERSION" "$C_DIM" "$PROXY_VM" \
  "$C_DIM" "$PROXY_ZONE" "$C_DIM" "$REGION" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
instance_exists() {
  gcloud sql instances describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}
db_exists() {
  gcloud sql databases describe "$1" --instance "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}
vm_ext_ip() {  # $1 = vm name, $2 = zone
  gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
}

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _ || true
  return 0
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

info "enabling the Cloud SQL, Service Networking and Service Management APIs"
gcloud services enable sqladmin.googleapis.com servicenetworking.googleapis.com \
  servicemanagement.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - the zone may be wrong"
fi

# ---------------------------------------------------------------------------
# Task 1 - the Cloud SQL instance
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create a Cloud SQL database"

  if instance_exists "$INSTANCE"; then
    ok "the instance $INSTANCE already exists"
  else
    # Private Services Access: an allocated range plus the peering. This is
    # what the console's "Confirm network setup" button does.
    info "allocating the Private Services Access range $PSA_RANGE"
    gcloud compute addresses create "$PSA_RANGE" --global \
      --purpose=VPC_PEERING --prefix-length=24 --description="SQL" \
      --network=default --project "$PROJECT_ID" >/dev/null 2>&1 \
      && ok "allocated $PSA_RANGE" \
      || ok "$PSA_RANGE already exists"

    info "connecting the service networking peering (this takes a minute)"
    gcloud services vpc-peerings connect \
      --service=servicenetworking.googleapis.com \
      --ranges="$PSA_RANGE" --network=default \
      --project "$PROJECT_ID" >/dev/null 2>&1 \
      && ok "the peering is connected" \
      || warn "the peering may already be connected"

    # the proxy VM's address, used in the API fallback below
    PROXY_IP_HINT="$(vm_ext_ip "$PROXY_VM" "$PROXY_ZONE")"
    [ "$PROXY_IP_HINT" = "None" ] && PROXY_IP_HINT="0.0.0.0"

    info "creating $INSTANCE (this takes a few minutes)"
    # The private IP flags only exist on the beta command, and not every
    # gcloud build accepts every one of them, so a few known combinations
    # are tried in turn. Each attempt gets its own log.
    local NET_ARG="projects/$PROJECT_ID/global/networks/default"
    local -a ATTEMPTS=(
      "gcloud beta sql instances create $INSTANCE --database-version=$DB_VERSION --cpu=1 --memory=3840MB --region=$REGION --root-password=$PASSWORD --network=$NET_ARG --allocated-ip-range-name=$PSA_RANGE --project=$PROJECT_ID"
      "gcloud beta sql instances create $INSTANCE --database-version=$DB_VERSION --cpu=1 --memory=3840MB --region=$REGION --zone=$PROXY_ZONE --root-password=$PASSWORD --network=$NET_ARG --allocated-ip-range-name=$PSA_RANGE --project=$PROJECT_ID"
      "gcloud beta sql instances create $INSTANCE --database-version=$DB_VERSION --cpu=1 --memory=3840MB --region=$REGION --zone=$PROXY_ZONE --storage-size=10 --root-password=$PASSWORD --network=$NET_ARG --allocated-ip-range-name=$PSA_RANGE --project=$PROJECT_ID"
      "gcloud sql instances create $INSTANCE --database-version=$DB_VERSION --edition=ENTERPRISE --cpu=1 --memory=3840MB --region=$REGION --zone=$PROXY_ZONE --root-password=$PASSWORD --project=$PROJECT_ID"
    )
    local CREATE_LOG="" n=0
    for CREATE_CMD in "${ATTEMPTS[@]}"; do
      n=$((n + 1))
      CREATE_LOG="$WORKDIR/create-$n.log"
      if $CREATE_CMD > "$CREATE_LOG" 2>&1; then
        ok "created $INSTANCE (attempt $n)"
        CREATE_LOG=""
        break
      fi
      dim "  attempt $n did not work:"
      head -4 "$CREATE_LOG" | sed 's/^/    /'
    done

    if [ -n "$CREATE_LOG" ]; then
      # as a last resort, the REST API, which has no flags to guess at
      info "trying the Cloud SQL Admin API instead"
      API_LOG="$WORKDIR/create-api.log"
      TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
      if [ -n "$TOKEN" ]; then
        curl -s -X POST "https://sqladmin.googleapis.com/sql/v1beta4/projects/$PROJECT_ID/instances" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
                \"name\": \"$INSTANCE\",
                \"region\": \"$REGION\",
                \"databaseVersion\": \"$DB_VERSION\",
                \"settings\": {
                  \"tier\": \"db-custom-1-3840\",
                  \"edition\": \"ENTERPRISE\",
                  \"storageSize\": 10,
                  \"rootPassword\": \"$PASSWORD\",
                  \"ipConfiguration\": {
                    \"ipv4Enabled\": true,
                    \"requireSsl\": false,
                    \"privateNetwork\": \"$NET_ARG\",
                    \"allocatedIpRange\": \"$PSA_RANGE\",
                    \"authorizedNetworks\": [{ \"name\": \"wordpress\", \"value\": \"$PROXY_IP_HINT/32\" }]
                  }
                }
              }" > "$API_LOG" 2>&1
        if grep -q '"kind": "sql#instance"' "$API_LOG" 2>/dev/null; then
          ok "created $INSTANCE through the API"
          CREATE_LOG=""
        fi
      fi
    fi

    if [ -n "$CREATE_LOG" ]; then
      note_fail "could not create $INSTANCE"
      echo ""
      dim "  every attempt and its error:"
      for f in "$WORKDIR"/create-*.log "$WORKDIR"/create-api.log; do
        [ -f "$f" ] || continue
        dim "    $(basename "$f"):"
        head -6 "$f" | sed 's/^/      /'
      done
      dim "  run the first one by hand to see everything:"
      dim "    ${ATTEMPTS[0]}"
      return 1
    fi
  fi

  info "waiting for the instance to be ready"
  local i
  for i in $(seq 1 60); do
    if gcloud sql instances describe "$INSTANCE" --project "$PROJECT_ID" \
         --format="value(state)" 2>/dev/null | grep -q "RUNNABLE"; then
      ok "$INSTANCE is RUNNABLE"
      break
    fi
    sleep 10
  done

  # The lab allows unencrypted traffic, because WordPress talks to the
  # database over plain MySQL. The proxy VM connects over the public IP, so
  # its address has to be allowlisted too.
  PROXY_IP="$(vm_ext_ip "$PROXY_VM" "$PROXY_ZONE")"
  if [ -n "$PROXY_IP" ] && [ "$PROXY_IP" != "None" ]; then
    info "allowlisting the proxy VM $PROXY_VM ($PROXY_IP)"
    gcloud sql instances patch "$INSTANCE" --project "$PROJECT_ID" \
      --authorized-networks="$PROXY_IP/32" --no-require-ssl \
      >/dev/null 2>&1 \
      && ok "the proxy VM is allowlisted and unencrypted traffic is allowed" \
      || warn "could not patch the instance - it may already be set"
  else
    warn "the proxy VM has no external IP yet"
  fi

  dim ""
  dim "  the instance:"
  gcloud sql instances describe "$INSTANCE" --project "$PROJECT_ID" \
    --format="table(name,region,state,databaseVersion,ipv4Enabled,privateNetwork,serviceType)" 2>/dev/null \
    | sed 's/^/      /'
  PRIVATE_IP="$(gcloud sql instances describe "$INSTANCE" --project "$PROJECT_ID" \
                 --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)"
  ok "the private IP is $PRIVATE_IP"
  echo "$PRIVATE_IP" > "$WORKDIR/private-ip"

  pause_for_check 1 "Create a Cloud SQL instance"
}

# ---------------------------------------------------------------------------
# Task 2 - the database and the proxy
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Configure a proxy on a virtual machine"

  if db_exists "$DATABASE" "$INSTANCE"; then
    ok "the database $DATABASE already exists"
  else
    if gcloud sql databases create "$DATABASE" --instance="$INSTANCE" \
         --project="$PROJECT_ID" >/dev/null 2>&1; then
      ok "created the database $DATABASE"
    else
      note_fail "could not create the database $DATABASE"
      return 1
    fi
  fi

  CONNECTION_NAME="$PROJECT_ID:$REGION:$INSTANCE"
  ok "the connection name is $CONNECTION_NAME"

  info "checking that the proxy VM is reachable"
  if ! gcloud compute instances describe "$PROXY_VM" --zone "$PROXY_ZONE" \
       --project "$PROJECT_ID" >/dev/null 2>&1; then
    note_fail "cannot reach $PROXY_VM"
    return 1
  fi

  # The lab starts the proxy from an SSH session with a bare "&", which dies
  # with the shell. nohup keeps it alive after the session closes.
  info "downloading the Cloud SQL Proxy onto $PROXY_VM"
  gcloud compute ssh "$PROXY_VM" --zone "$PROXY_ZONE" --project "$PROJECT_ID" --quiet \
    --command="cd ~ && ( [ -f cloud_sql_proxy ] || wget -q $PROXY_URL -O cloud_sql_proxy ) && chmod +x cloud_sql_proxy && echo PROXY-READY" \
    2>/dev/null | grep -q "PROXY-READY" \
    && ok "the proxy binary is on $PROXY_VM" \
    || warn "could not prepare the proxy on $PROXY_VM"

  info "starting the proxy in the background"
  gcloud compute ssh "$PROXY_VM" --zone "$PROXY_ZONE" --project "$PROJECT_ID" --quiet \
    --command="cd ~ && ( pkill -f 'cloud_sql_proxy' >/dev/null 2>&1 || true ); nohup ./cloud_sql_proxy -instances=$CONNECTION_NAME=tcp:3306 > proxy.log 2>&1 & sleep 8; grep -m1 -E 'Listening|Ready' proxy.log || cat proxy.log" \
    2>/dev/null | sed 's/^/      /'

  if gcloud compute ssh "$PROXY_VM" --zone "$PROXY_ZONE" --project "$PROJECT_ID" --quiet \
       --command="pgrep -f cloud_sql_proxy >/dev/null && echo PROXY-RUNNING" 2>/dev/null \
       | grep -q "PROXY-RUNNING"; then
    ok "the proxy is running on $PROXY_VM"
  else
    warn "the proxy does not look like it is running - check it with:"
    dim "    gcloud compute ssh $PROXY_VM --zone=$PROXY_ZONE --command='cat ~/proxy.log'"
  fi

  pause_for_check 2 "Create a database and configure a proxy on a Virtual Machine"
}

# ---------------------------------------------------------------------------
# the browser steps
# ---------------------------------------------------------------------------
browser_steps() {
  local PROXY_IP PRIVATE_IP
  PROXY_IP="$(vm_ext_ip "$PROXY_VM" "$PROXY_ZONE")"
  PRIVATE_IP="$(cat "$WORKDIR/private-ip" 2>/dev/null)"
  [ -z "$PRIVATE_IP" ] && PRIVATE_IP="$(gcloud sql instances describe "$INSTANCE" --project "$PROJECT_ID" --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)"

  cat <<EOF

  ${C_BOLD}The last two steps are done in the browser - the WordPress setup is a${C_RESET}
  ${C_BOLD}web form, so the script cannot fill it in for you.${C_RESET}

  ${C_BOLD}1. Over the proxy${C_RESET}
     Open      ${C_CYAN}http://$PROXY_IP${C_RESET}
     Click     ${C_BOLD}Let's Go${C_RESET}, then fill the form in with:
       Database Name : $DATABASE
       Username      : root
       Password      : $PASSWORD
       Database Host : 127.0.0.1
     Click ${C_BOLD}Submit${C_RESET}, then ${C_BOLD}Run the installation${C_RESET},
     then fill in any site details and click ${C_BOLD}Install Wordpress${C_RESET}.
     It can take up to 3 minutes.

  ${C_BOLD}2. Over the private IP${C_RESET}
     Open      ${C_CYAN}http://$(vm_ext_ip "$PRIVATE_VM" "$PRIVATE_ZONE")${C_RESET}
     Click     ${C_BOLD}Let's Go${C_RESET}, then fill the form in with:
       Database Name : $DATABASE
       Username      : root
       Password      : $PASSWORD
       Database Host : $PRIVATE_IP
     Click ${C_BOLD}Submit${C_RESET}. You should get an ${C_BOLD}Already Installed!${C_RESET}
     window, which means the private IP connection works.

EOF
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  "")
    task1 || { echo ""; err "task 1 failed - fix that first, everything else depends on it"; exit 1; }
    task2 || { echo ""; err "task 2 failed"; exit 1; }
    browser_steps
    ;;
  *)
    err "--task must be 1 or 2"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project    : $PROJECT_ID"
echo "  Instance   : $INSTANCE  ($DB_VERSION, 1 vCPU / 3840 MB, 10 GB)"
echo "  Database   : $DATABASE"
echo "  Region     : $REGION   (zone $PROXY_ZONE)"
echo "  Proxy VM   : $PROXY_VM"
echo "  Private VM : $PRIVATE_VM"
echo "  Password   : $PASSWORD   (also saved in $WORKDIR/root-password)"
echo ""
echo "  Checkpoints:"
echo "    1. Create a Cloud SQL instance                                        (50)"
echo "    2. Create a database and configure a proxy on a Virtual Machine       (50)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
