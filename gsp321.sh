#!/usr/bin/env bash
# =============================================================================
#  GSP321 - "Develop Your Google Cloud Network"
#  Google Cloud Arcade / Cloud Skills Boost challenge lab.
#
#  One-shot provisioning script designed to run unattended in Google Cloud
#  Shell. Idempotent: safe to re-run, it skips anything that already exists.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh
#     chmod +x gsp321.sh
#     ./gsp321.sh
#
#  ...or in a single line, no download needed:
#     bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh)
#
#  OPTIONS:
#     --project ID       GCP project to use        (default: active gcloud project)
#     --zone ZONE        e.g. us-central1-a         (default: $ZONE, else us-central1-a)
#     --region REGION    e.g. us-central1           (default: derived from --zone)
#     --workdir PATH     scratch dir for manifests (default: $HOME/gsp321)
#     --timeout MINUTES  how long to wait for the GKE LoadBalancer IP (default: 10)
#     --engineer EMAIL     the additional engineer account (default: any other viewer)
#     --skip-iam         skip Task 9 (promote viewer -> editor)
#     -h, --help         this help
#
#  NOTES:
#   * Task 8 waits for the LoadBalancer external IP before creating the uptime
#     check. The upstream version of this script read the IP ~2 seconds after
#     the Service was created, when it is still empty, which made the API
#     reject the check with "uptime_url check is missing a host".
#   * Task 8 also sends the required `project_id` label, which the
#     `uptime_url` monitored resource descriptor mandates.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# colors - defined locally so the script renders correctly outside Cloud Shell
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

step() { printf "\n%s%s== %s%s\n" "$C_CYAN" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf "  %s[OK]%s   %s\n"   "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "  %s[WARN]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "  %s[FAIL]%s %s\n" "$C_RED"    "$C_RESET" "$*"; }
info() { printf "  %s[INFO]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
dim()  { printf "  %s%s%s\n"          "$C_DIM"    "$*"       "$C_RESET"; }

FAILURES=0
note_fail() { err "$1"; FAILURES=$((FAILURES + 1)); }

# Run a command and show its output as it arrives. Creating a Cloud SQL
# instance or a GKE cluster blocks for minutes while the operation runs, and
# a silent wait looks exactly like a hang.
run_live() {  # $1 = log file, rest = command
  local log="$1"; shift
  local pid last=0 n elapsed=0
  : > "$log"
  "$@" > "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2
    elapsed=$((elapsed + 2))
    n="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
    [ -z "$n" ] && n=0
    if [ "$n" -gt "$last" ]; then
      tail -n +$((last + 1)) "$log" | sed 's/^/    /'
      last="$n"
    elif [ $((elapsed % 20)) -eq 0 ]; then
      printf "    ... still working (%ss elapsed)\n" "$elapsed"
    fi
  done
  wait "$pid"
  local rc=$?
  n="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
  [ -z "$n" ] && n=0
  if [ "$n" -gt "$last" ]; then
    tail -n +$((last + 1)) "$log" | sed 's/^/    /'
  fi
  return $rc
}


# ---------------------------------------------------------------------------
# defaults + argument parsing
# ---------------------------------------------------------------------------
PROJECT_OVERRIDE=""
ZONE_OVERRIDE=""
REGION_OVERRIDE=""
WORKDIR="${GSP321_WORKDIR:-$HOME/gsp321}"
WAIT_MINUTES="${GSP321_WAIT_MINUTES:-10}"
ENGINEER_OVERRIDE=""
SKIP_MONITOR=0
SKIP_IAM=0

usage() {
  cat <<'USAGE_END'
GSP321 - Develop Your Google Cloud Network
Google Cloud Arcade / Cloud Skills Boost challenge lab.

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh
   chmod +x gsp321.sh
   ./gsp321.sh

Single line, no download:
   bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh)

OPTIONS:
   --project ID       GCP project to use        (default: active gcloud project)
   --zone ZONE        e.g. us-central1-a         (default: $ZONE, else us-central1-a)
   --region REGION    e.g. us-central1           (default: derived from --zone)
   --workdir PATH     scratch dir for manifests (default: $HOME/gsp321)
   --timeout MINUTES  wait time for the GKE LoadBalancer IP (default: 10)
   --engineer EMAIL     the additional engineer account (default: any other viewer)
   --skip-iam         skip Task 9 (promote viewer -> editor)
   -h, --help         this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)         ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)       REGION_OVERRIDE="$2";   shift 2 ;;
    --workdir)      WORKDIR="$2";           shift 2 ;;
    --timeout)      WAIT_MINUTES="$2";      shift 2 ;;
    --engineer)      ENGINEER_OVERRIDE="$2"; shift 2 ;;
    --skip-monitor) SKIP_MONITOR=1;         shift ;;
    --skip-iam)     SKIP_IAM=1;             shift ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve project / zone / region
# ---------------------------------------------------------------------------
PROJECT_ID="$PROJECT_OVERRIDE"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
fi
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

ZONE="${ZONE_OVERRIDE:-${ZONE:-us-central1-a}}"
REGION="${REGION_OVERRIDE:-${REGION:-${ZONE%-*}}}"

# Cloud Skills Boost points gcloud's own config at the lab's region/zone, and
# that is more reliable than any environment variable. Prefer it.
# Zone detection. `gcloud config compute/zone` is a per-user setting that
# survives Cloud Shell restarts, so the zone from a PREVIOUS lab is often
# still sitting there. Sources are tried most-reliable first.
GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

zone_exists() {
  gcloud compute zones describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

detect_zone() {
  local z

  # 1. an instance that already exists in this project
  z="$(gcloud compute instances list --project "$PROJECT_ID" \
        --format="value(zone)" 2>/dev/null | head -1 | sed 's|.*/||')"
  if [ -n "$z" ] && [ "$z" != "(unset)" ]; then
    ZONE="$z"
    ZONE_SOURCE="an existing instance in this project"
    return 0
  fi

  # 2. the project's startup script metadata
  z="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null \
        | grep -oE '\b[a-z]+-[a-z]+[0-9]-[a-z]\b' | head -1)"
  if [ -n "$z" ] && zone_exists "$z"; then
    ZONE="$z"
    ZONE_SOURCE="the project startup script metadata"
    return 0
  fi

  # 3. the environment
  if [ -n "${CLOUDSDK_COMPUTE_ZONE:-}" ] && zone_exists "$CLOUDSDK_COMPUTE_ZONE"; then
    ZONE="$CLOUDSDK_COMPUTE_ZONE"
    ZONE_SOURCE="CLOUDSDK_COMPUTE_ZONE"
    return 0
  fi

  # 4. gcloud config - may well be left over from a previous lab
  if [ -n "$GCP_ZONE" ] && zone_exists "$GCP_ZONE"; then
    ZONE="$GCP_ZONE"
    ZONE_SOURCE="gcloud config compute/zone (may be left over from a previous lab)"
    return 0
  fi

  ZONE="us-central1-a"
  ZONE_SOURCE="the built-in default"
  return 0
}

ZONE_SOURCE="the --zone flag"
if [ -n "$ZONE_OVERRIDE" ]; then
  ZONE="$ZONE_OVERRIDE"
else
  detect_zone
fi

if [ -n "$ZONE_OVERRIDE" ] && [ -z "$REGION_OVERRIDE" ]; then
  # An explicit zone implies its region - do not mix it with the config region.
  REGION="${ZONE_OVERRIDE%-*}"
else
  REGION="${REGION_OVERRIDE:-${GCP_REGION:-${CLOUDSDK_COMPUTE_REGION:-${ZONE%-*}}}}"
fi

SQL_VERSION="${SQL_VERSION:-MYSQL_5_7}"
SQL_ROOT_PASSWORD="${SQL_ROOT_PASSWORD:-awesome}"
SQL_DB="wordpress"
SQL_USER="wp_user"
SQL_PASS="stormwind_rules"

CLUSTER="griffin-dev"
SERVICE="wordpress"
UPTIME_CHECK="wordpress-uptime-check"
DEPLOYMENT_MANAGER_NAME="prod-network"

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
printf "%s%s  GSP321 - Develop Your Google Cloud Network%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %sworkdir=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$WORKDIR" "$C_RESET"
printf "  %sZONE  = %s%s%s   %s(from %s)%s\n" \
  "$C_BOLD" "$C_YELLOW" "$ZONE" "$C_RESET" "$C_DIM" "$ZONE_SOURCE" "$C_RESET"
echo ""
printf "  %s>> Confirm the zone matches the lab page before continuing.%s\n" "$C_YELLOW" "$C_RESET"
printf "  %s   The lab scores the subnets, SQL instance and cluster against its%s\n" "$C_DIM"
printf "  %s   own region. If it differs, stop and re-run with:%s\n" "$C_DIM" "$C_RESET"
printf "  %s   ./gsp321.sh --zone <lab-zone> --region <lab-region>%s\n" "$C_DIM" "$C_RESET"

step "Preflight checks"

for bin in gcloud kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    err "$bin not found on PATH. Run this inside Google Cloud Shell."
    exit 1
  fi
done
ok "gcloud and kubectl are available"

if ! command -v gsutil >/dev/null 2>&1; then
  warn "gsutil not found - run: gcloud components install gsutil"
fi

ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
if [ -z "$ACTIVE_ACCOUNT" ] || [ "$ACTIVE_ACCOUNT" = "(unset)" ]; then
  err "No active gcloud account. Run: gcloud auth login"
  exit 1
fi
ok "active account: $ACTIVE_ACCOUNT"

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  err "No GCP project resolved. Pass --project ID or run: gcloud config set project ID"
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
ok "project: $PROJECT_ID"

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - zone/project defaults may be wrong, use --zone/--project"
fi

# The lab hands you two accounts. The active one usually holds roles/owner,
# which is enough for everything - so list the real roles instead of assuming
# roles/editor and warning on a false negative.
#
# NOTE: deliberately no --filter here. Member strings look like
# "user:someone@example.com" and the ':' inside a filter value is ambiguous.
# Pull role+member pairs and match locally instead.
USER_ROLES="$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --format="value(bindings.role,bindings.members)" 2>/dev/null \
  | awk -F',' -v u="user:${ACTIVE_ACCOUNT}" '$2 == u { print $1 }' \
  | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

if [ -z "$USER_ROLES" ] && command -v jq >/dev/null 2>&1; then
  USER_ROLES="$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json 2>/dev/null \
    | jq -r --arg u "user:${ACTIVE_ACCOUNT}" \
        '.bindings[]? | select(.members[]? | . == $u) | .role' 2>/dev/null \
    | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
fi

if printf '%s' "$USER_ROLES" | grep -qE 'roles/(owner|editor|iam\.securityAdmin|iam\.projectIamAdmin)'; then
  ok "active account roles: $USER_ROLES"
elif [ -n "$USER_ROLES" ]; then
  warn "active account roles: $USER_ROLES"
  warn "Task 8 (uptime check) and Task 9 (promote engineer) need editor-level rights."
  warn "Grant yourself editor, then re-run:"
  warn "  gcloud projects add-iam-policy-binding $PROJECT_ID --member=\"user:$ACTIVE_ACCOUNT\" --role=roles/editor"
else
  warn "could not read the active account's project roles - check IAM & Admin"
  warn "Task 8 and Task 9 may fail with PERMISSION_DENIED."
fi

mkdir -p "$WORKDIR" || { err "cannot create workdir $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
ensure_network() {  # $1 = name
  if gcloud compute networks describe "$1" >/dev/null 2>&1; then
    ok "network $1 already exists"
  else
    if gcloud compute networks create "$1" --subnet-mode custom --quiet >/dev/null 2>&1; then
      ok "created network $1"
    else
      note_fail "could not create network $1"
    fi
  fi
}

ensure_subnet() {   # $1 = name, $2 = cidr, $3 = network
  if gcloud compute networks subnets describe "$1" --region "$REGION" >/dev/null 2>&1; then
    ok "subnet $1 already exists"
  else
    if gcloud compute networks subnets create "$1" --network="$3" --region "$REGION" \
         --range="$2" --quiet >/dev/null 2>&1; then
      ok "created subnet $1 ($2)"
    else
      note_fail "could not create subnet $1"
    fi
  fi
}

ensure_firewall() { # $1 = name, $2 = network
  if gcloud compute firewall-rules describe "$1" >/dev/null 2>&1; then
    ok "firewall rule $1 already exists"
  else
    if gcloud compute firewall-rules create "$1" --source-ranges=0.0.0.0/0 --target-tags ssh \
         --allow=tcp:22 --network="$2" --quiet >/dev/null 2>&1; then
      ok "created firewall rule $1"
    else
      note_fail "could not create firewall rule $1"
    fi
  fi
}

# The lab manifests live in a Google-managed bucket. Current labs point at
# gs://spls/gsp321/, older material at gs://cloud-training/gsp321/. Try both.
fetch_lab_files() { # $1 = subdir, $2 = destination dir
  for LB_BUCKET in ${GSP321_BUCKET:-"gs://spls/gsp321" "gs://cloud-training/gsp321"}; do
    if gsutil cp -r "$LB_BUCKET/$1" "$2" >/dev/null 2>&1; then
      ok "fetched $1 from $LB_BUCKET"
      return 0
    fi
  done
  note_fail "could not fetch $1 from any known lab bucket"
  return 1
}

# ---------------------------------------------------------------------------
# Task 1 - development VPC
# ---------------------------------------------------------------------------
step "Task 1 - Development VPC (manual)"
ensure_network "griffin-dev-vpc"
ensure_subnet "griffin-dev-wp"    "192.168.16.0/20" "griffin-dev-vpc"
ensure_subnet "griffin-dev-mgmt" "192.168.32.0/20" "griffin-dev-vpc"

# ---------------------------------------------------------------------------
# Task 2 - production VPC via Deployment Manager
# ---------------------------------------------------------------------------
step "Task 2 - Production VPC (Deployment Manager)"
if [ ! -f "$WORKDIR/dm/prod-network.yaml" ]; then
  fetch_lab_files "dm" "$WORKDIR/"
fi
if [ -f "$WORKDIR/dm/prod-network.yaml" ]; then
  if grep -q "SET_REGION" "$WORKDIR/dm/prod-network.yaml"; then
    sed -i "s/SET_REGION/$REGION/g" "$WORKDIR/dm/prod-network.yaml"
  else
    warn "prod-network.yaml has no SET_REGION placeholder - patching the region field"
    sed -i -E "s/(region:[[:space:]]*)[A-Za-z0-9_-]+/\1$REGION/g" "$WORKDIR/dm/prod-network.yaml"
  fi
  grep -q "$REGION" "$WORKDIR/dm/prod-network.yaml" \
    && ok "prod-network.yaml region set to $REGION" \
    || note_fail "could not set the region in prod-network.yaml"
  if gcloud deployment-manager deployments describe "$DEPLOYMENT_MANAGER_NAME" >/dev/null 2>&1; then
    ok "deployment $DEPLOYMENT_MANAGER_NAME already exists"
  else
    if run_live "$WORKDIR/dm-create.log" gcloud deployment-manager deployments create "$DEPLOYMENT_MANAGER_NAME" \
         --config="$WORKDIR/dm/prod-network.yaml" --quiet ; then
      ok "created deployment $DEPLOYMENT_MANAGER_NAME"
    else
      note_fail "could not create deployment $DEPLOYMENT_MANAGER_NAME"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Task 3 - bastion host + firewall rules
# ---------------------------------------------------------------------------
step "Task 3 - Bastion host"
if gcloud compute instances describe bastion --zone "$ZONE" >/dev/null 2>&1; then
  ok "instance bastion already exists"
else
  if gcloud compute instances create bastion \
      --network-interface=network=griffin-dev-vpc,subnet=griffin-dev-mgmt \
      --network-interface=network=griffin-prod-vpc,subnet=griffin-prod-mgmt \
      --tags=ssh --zone="$ZONE" --quiet >/dev/null 2>&1; then
    ok "created bastion"
  else
    note_fail "could not create bastion"
  fi
fi
ensure_firewall "fw-ssh-dev"  "griffin-dev-vpc"
ensure_firewall "fw-ssh-prod" "griffin-prod-vpc"

# ---------------------------------------------------------------------------
# Task 4 - Cloud SQL for MySQL
# ---------------------------------------------------------------------------
step "Task 4 - Cloud SQL instance"
if gcloud sql instances describe griffin-dev-db >/dev/null 2>&1; then
  ok "instance griffin-dev-db already exists"
else
  info "creating MySQL instance (this takes 2-4 minutes)..."
  if ! run_live "$WORKDIR/sql-create.log" gcloud sql instances create griffin-dev-db \
        --database-version="$SQL_VERSION" --region="$REGION" \
        --root-password="$SQL_ROOT_PASSWORD" --quiet; then
    warn "$SQL_VERSION was rejected, retrying with MYSQL_8_0"
    SQL_VERSION="MYSQL_8_0"
    run_live "$WORKDIR/sql-create.log" gcloud sql instances create griffin-dev-db \
      --database-version="$SQL_VERSION" --region="$REGION" \
      --root-password="$SQL_ROOT_PASSWORD" --quiet \
      && ok "created griffin-dev-db ($SQL_VERSION)" \
      || note_fail "could not create griffin-dev-db"
  else
    ok "created griffin-dev-db ($SQL_VERSION)"
  fi
fi

if gcloud sql databases describe "$SQL_DB" --instance=griffin-dev-db >/dev/null 2>&1; then
  ok "database $SQL_DB already exists"
else
  gcloud sql databases create "$SQL_DB" --instance=griffin-dev-db --quiet >/dev/null 2>&1 \
    && ok "created database $SQL_DB" \
    || note_fail "could not create database $SQL_DB"
fi

if gcloud sql users describe "$SQL_USER" --instance=griffin-dev-db >/dev/null 2>&1; then
  gcloud sql users set-password "$SQL_USER" --instance=griffin-dev-db \
    --password="$SQL_PASS" --quiet >/dev/null 2>&1
  ok "reset password for user $SQL_USER"
else
  gcloud sql users create "$SQL_USER" --instance=griffin-dev-db \
    --password="$SQL_PASS" --quiet >/dev/null 2>&1 \
    && ok "created user $SQL_USER" \
    || note_fail "could not create user $SQL_USER"
fi

# ---------------------------------------------------------------------------
# Task 5 - GKE cluster
# ---------------------------------------------------------------------------
step "Task 5 - Kubernetes cluster"
if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" >/dev/null 2>&1; then
  ok "cluster $CLUSTER already exists"
else
  info "creating GKE cluster (5-10 minutes)..."
  if run_live "$WORKDIR/cluster-create.log" gcloud container clusters create "$CLUSTER" \
      --network griffin-dev-vpc --subnetwork griffin-dev-wp \
      --machine-type e2-standard-4 --num-nodes 2 --zone "$ZONE" --quiet; then
    ok "created cluster $CLUSTER"
  else
    note_fail "could not create cluster $CLUSTER"
  fi
fi

gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" >/dev/null 2>&1 \
  && ok "kubectl context pointed at $CLUSTER" \
  || note_fail "could not get cluster credentials"

# ---------------------------------------------------------------------------
# Task 6 - prepare the cluster (PVC, secret, cloud-sql-proxy key)
# ---------------------------------------------------------------------------
step "Task 6 - Prepare the Kubernetes cluster"
if [ ! -d "$WORKDIR/wp-k8s" ]; then
  fetch_lab_files "wp-k8s" "$WORKDIR/"
fi

# A 404 from GCS can leave an XML error page where a manifest should be.
for WF in wp-env.yaml wp-deployment.yaml wp-service.yaml; do
  if [ ! -s "$WORKDIR/wp-k8s/$WF" ]; then
    note_fail "wp-k8s/$WF is missing or empty"
  elif grep -q "NoSuchKey\|<Error>" "$WORKDIR/wp-k8s/$WF" 2>/dev/null; then
    note_fail "wp-k8s/$WF is a GCS error page, not a manifest"
  fi
done

cat > "$WORKDIR/wp-k8s/wp-env.yaml" <<EOF_END
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: wordpress-volumeclaim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: database
type: Opaque
stringData:
  username: $SQL_USER
  password: $SQL_PASS
EOF_END
ok "wrote wp-env.yaml (PVC + db secret)"

kubectl apply -f "$WORKDIR/wp-k8s/wp-env.yaml" >/dev/null 2>&1 \
  && ok "applied wp-env.yaml" \
  || note_fail "could not apply wp-env.yaml"

SA_NAME="cloud-sql-proxy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  ok "service account $SA_EMAIL already exists"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Cloud SQL Proxy" --project="$PROJECT_ID" >/dev/null 2>&1
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" --role="roles/cloudsql.client" --quiet >/dev/null 2>&1
  ok "created service account $SA_EMAIL with roles/cloudsql.client"
fi

KEY_FILE="$WORKDIR/wp-k8s/key.json"
if [ -s "$KEY_FILE" ]; then
  ok "reusing existing key.json (service account keys cannot be re-downloaded)"
else
  if gcloud iam service-accounts keys create "$KEY_FILE" --iam-account="$SA_EMAIL" \
       --key-file-type=json >/dev/null 2>&1; then
    ok "created service account key"
  else
    note_fail "could not create service account key (org IAM policy may block it)"
  fi
fi

if [ -s "$KEY_FILE" ]; then
  kubectl create secret generic cloudsql-instance-credentials \
    --from-file="key.json=$KEY_FILE" --dry-run=client -o yaml 2>/dev/null \
    | kubectl apply -f - >/dev/null 2>&1 \
    && ok "applied secret cloudsql-instance-credentials" \
    || note_fail "could not apply secret cloudsql-instance-credentials"
fi

# ---------------------------------------------------------------------------
# Task 7 - WordPress deployment + service
# ---------------------------------------------------------------------------
step "Task 7 - WordPress deployment"
INSTANCE_ID="$(gcloud sql instances describe griffin-dev-db --format='value(connectionName)' 2>/dev/null)"
if [ -z "$INSTANCE_ID" ]; then
  note_fail "could not resolve griffin-dev-db connection name"
else
  ok "instance connection name: $INSTANCE_ID"
  if [ -f "$WORKDIR/wp-k8s/wp-deployment.yaml" ]; then
    if grep -q "YOUR_SQL_INSTANCE" "$WORKDIR/wp-k8s/wp-deployment.yaml"; then
      sed -i "s/YOUR_SQL_INSTANCE/$INSTANCE_ID/g" "$WORKDIR/wp-k8s/wp-deployment.yaml"
    else
      warn "no YOUR_SQL_INSTANCE placeholder - repointing the proxy at $INSTANCE_ID"
      sed -i -E "s#(-instances=)[^=\"]+#\1$INSTANCE_ID#g" "$WORKDIR/wp-k8s/wp-deployment.yaml"
    fi
    grep -q "$INSTANCE_ID" "$WORKDIR/wp-k8s/wp-deployment.yaml" \
      && ok "wp-deployment.yaml points at $INSTANCE_ID" \
      || note_fail "wp-deployment.yaml does not reference $INSTANCE_ID"
    kubectl apply -f "$WORKDIR/wp-k8s/wp-deployment.yaml" >/dev/null 2>&1 \
      && ok "applied wp-deployment.yaml" \
      || note_fail "could not apply wp-deployment.yaml"
  else
    note_fail "wp-deployment.yaml missing from $WORKDIR/wp-k8s"
  fi
fi

if [ -f "$WORKDIR/wp-k8s/wp-service.yaml" ]; then
  kubectl apply -f "$WORKDIR/wp-k8s/wp-service.yaml" >/dev/null 2>&1 \
    && ok "applied wp-service.yaml" \
    || note_fail "could not apply wp-service.yaml"
else
  note_fail "wp-service.yaml missing from $WORKDIR/wp-k8s"
fi

# ---------------------------------------------------------------------------
# Task 8 - monitoring (uptime check)
#   THE FIX: wait for the LoadBalancer external IP, and send project_id.
# ---------------------------------------------------------------------------
if [ "$SKIP_MONITOR" -eq 1 ]; then
  step "Task 8 - Uptime check  (skipped via --skip-monitor)"
else
  step "Task 8 - Uptime check"

  gcloud services enable monitoring.googleapis.com --quiet >/dev/null 2>&1
  info "monitoring API enabled"

  DEADLINE=$(( $(date +%s) + WAIT_MINUTES * 60 ))
  WP_IP=""
  ATTEMPT=0
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    WP_IP="$(kubectl get svc "$SERVICE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    if [ -n "$WP_IP" ]; then
      break
    fi
    if [ $((ATTEMPT % 4)) -eq 1 ]; then
      dim "waiting for the GKE LoadBalancer IP (attempt $ATTEMPT)..."
    fi
    sleep 15
  done

  if [ -z "$WP_IP" ]; then
    note_fail "no external IP on service/$SERVICE after ${WAIT_MINUTES} min"
    echo ""
    dim "  Diagnostics:"
    dim "    kubectl get svc $SERVICE -o wide"
    dim "    kubectl describe svc $SERVICE | tail -25"
    dim "    kubectl get pods -o wide"
    dim "    kubectl get pvc"
    echo ""
    dim "  Common causes: pods not Ready (check the cloudsql-proxy sidecar),"
    dim "  PVC stuck Pending, or the cluster was created in the wrong subnet."
    dim "  Re-run ./gsp321.sh once the pod is Running - it is idempotent."
  else
    ok "LoadBalancer external IP: $WP_IP"

    if gcloud monitoring uptime describe "$UPTIME_CHECK" >/dev/null 2>&1; then
      info "uptime check '$UPTIME_CHECK' already exists - deleting and recreating"
      gcloud monitoring uptime delete "$UPTIME_CHECK" --quiet >/dev/null 2>&1
      sleep 5
    fi

    if gcloud monitoring uptime create "$UPTIME_CHECK" \
         --resource-type=uptime-url \
         --resource-labels="host=${WP_IP},project_id=${PROJECT_ID}" >/dev/null 2>&1; then
      ok "created uptime check '$UPTIME_CHECK'"
    else
      note_fail "uptime check creation failed - retrying with a full URL"
      gcloud monitoring uptime create "$UPTIME_CHECK" \
        --resource-type=uptime-url \
        --resource-labels="host=http://${WP_IP}/,project_id=${PROJECT_ID}" >/dev/null 2>&1 \
        && ok "created uptime check '$UPTIME_CHECK' (URL form)" \
        || note_fail "could not create uptime check"
    fi

    echo ""
    gcloud monitoring uptime list-configs \
      --format="table(name.basename(), resourceLabels.host, resourceLabels.project_id)" 2>/dev/null
    echo ""
    dim "  Console: Monitoring -> Uptime checks -> $UPTIME_CHECK"
  fi
fi

# ---------------------------------------------------------------------------
# Task 9 - promote the additional engineer
# ---------------------------------------------------------------------------
if [ "$SKIP_IAM" -eq 1 ]; then
  step "Task 9 - Additional engineer access  (skipped via --skip-iam)"
else
  step "Task 9 - Provide access for an additional engineer"

  # The additional engineer is the *other* lab account, not the one we run as.
  # The lab's own instructions are "IAM -> the second user -> Edit -> Role ->
  # Editor -> Save", and the console REPLACES the role. gcloud's
  # add-iam-policy-binding only ADDS a binding, so the viewer binding has to be
  # removed as well or the account is left on viewer *and* editor.
  VIEWER_USERS="$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/viewer" \
    --format="value(bindings.members)" 2>/dev/null \
    | grep -E '^user:[^ ]+$' || true)"

  if [ -n "$ENGINEER_OVERRIDE" ]; then
    TARGETS="user:$ENGINEER_OVERRIDE"
  else
    TARGETS=""
    for MEMBER in $VIEWER_USERS; do
      [ "$MEMBER" = "user:$ACTIVE_ACCOUNT" ] && continue
      TARGETS="$TARGETS $MEMBER"
    done
    TARGETS="${TARGETS# }"
    if [ -z "$TARGETS" ] && [ -n "$VIEWER_USERS" ]; then
      TARGETS="$VIEWER_USERS"
      warn "no other account holds roles/viewer - promoting the active account"
    fi
  fi

  if [ -z "$TARGETS" ]; then
    warn "could not find any account holding roles/viewer"
    note_fail "Task 9 skipped: no viewer account found"
    dim "  run this by hand:"
    dim "    gcloud projects get-iam-policy $PROJECT_ID --flatten='bindings[].members' \\"
    dim "      --filter='bindings.role:roles/viewer' --format='value(bindings.members)'"
  else
    for MEMBER in $TARGETS; do
      EMAIL="${MEMBER#user:}"
      if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
           --member="user:$EMAIL" --role=roles/editor --quiet >/dev/null 2>&1; then
        ok "granted roles/editor to $EMAIL"
      else
        note_fail "could not grant editor to $EMAIL"
        continue
      fi
      # Mirror the console: setting the role to Editor drops the Viewer binding.
      if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
           --member="user:$EMAIL" --role=roles/viewer --quiet >/dev/null 2>&1; then
        ok "removed roles/viewer from $EMAIL"
      else
        warn "could not remove roles/viewer from $EMAIL (it may already be gone)"
      fi
    done

    # Verify: each target holds roles/editor and no longer holds roles/viewer.
    for MEMBER in $TARGETS; do
      EMAIL="${MEMBER#user:}"
      ROLES="$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="value(bindings.role,bindings.members)" 2>/dev/null \
        | awk -F',' -v m="user:$EMAIL" '$2 == m { print $1 }')"
      if printf '%s' "$ROLES" | grep -qx "roles/editor" && ! printf '%s' "$ROLES" | grep -qx "roles/viewer"; then
        ok "$EMAIL is now editor (no leftover viewer binding)"
      elif printf '%s' "$ROLES" | grep -qx "roles/editor"; then
        warn "$EMAIL holds editor but still has a roles/viewer binding"
      else
        note_fail "$EMAIL does not hold roles/editor"
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project : $PROJECT_ID"
echo "  Region  : $REGION"
echo "  Zone    : $ZONE"
echo "  Workdir : $WORKDIR"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Verify each task in the lab console with 'Check my progress'."
echo "  Quick self-checks:"
echo "    gcloud compute networks list"
echo "    gcloud sql instances list"
echo "    gcloud container clusters list"
echo "    kubectl get svc $SERVICE -o wide"
echo "    gcloud monitoring uptime list-configs"
echo "    gcloud projects get-iam-policy $PROJECT_ID --flatten='bindings[].members' --filter='bindings.role:roles/editor' --format='value(bindings.members)'"
echo ""
dim "  Cloud Monitoring console: https://console.cloud.google.com/monitoring/uptime"
dim "  WordPress site: http://<EXTERNAL-IP> once the pod reports Running"
echo ""

# Non-zero exit when any step failed, so this is safe to use in automation.
exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
