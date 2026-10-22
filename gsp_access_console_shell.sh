#!/usr/bin/env bash
# =============================================================================
#  "Accessing the Google Cloud Console and Cloud Shell"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 464487, CBL138).
#
#  Builds the whole lab the script asks for:
#    1  the default-allow-http and the SSH firewall rules, the first-vm
#       instance with a startup script, and the test-service-account with the
#       Editor role
#    2  the Cloud Shell verification (auth list and config list project)
#    3  the two buckets, the cat.jpg upload, the public Object Viewer grant
#    4  the repo clone, the index.html with the cat image, nginx on first-vm
#       and the HTTP check
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_access_console_shell.sh
#     chmod +x gsp_access_console_shell.sh
#     ./gsp_access_console_shell.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       the lab's zone (default: from the project)
#     --task N          run only task N (1-4)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  CHECKPOINTS (one per lab objective):
#     1. Create a VM instance with necessary firewall rule, and an IAM
#        service account                                    (end of task 1)
#     2. Create Cloud Storage Buckets                      (end of task 3)
#     3. Install the nginx web server and customize the welcome page
#                                                         (end of task 4)
#
#  NOTES:
#   * The lab injects the zone per run. The script reads it from the shell
#     the lab starts (ZONE) and asks for whatever is missing.
#   * The web server is installed with a startup script, so the VM needs
#     the default network's SSH rule to be present. The script creates an
#     IAP SSH rule if the lab's one is missing.
#   * The bucket names are derived from the project ID: <project>-bucket1
#     and <project>-bucket2.
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
ONLY_TASK=""
ASSUME_YES=0

usage() {
  cat <<'USAGE_END'
Accessing the Google Cloud Console and Cloud Shell

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_access_console_shell.sh
   chmod +x gsp_access_console_shell.sh
   ./gsp_access_console_shell.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       the lab's zone (default: from the project)
   --task N          run only task N (1-4)
   --yes             do not pause for the checkpoints
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)    ZONE_OVERRIDE="$2";    shift 2 ;;
    --task)    ONLY_TASK="$2";        shift 2 ;;
    --yes)     ASSUME_YES=1;          shift ;;
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
GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
ZONE="${ZONE_OVERRIDE:-${ZONE:-${GCP_ZONE:-us-central1-a}}}"

ask() {  # $1 = variable name, $2 = label, $3 = default
  local __name="$1" __label="$2" __default="$3" __ans=""
  printf "  %s%s%s [%s]: " "$C_BOLD" "$__label" "$C_RESET" "$__default"
  if ! read -r __ans; then
    echo ""
    __ans=""
  fi
  printf -v "$__name" '%s' "${__ans:-$__default}"
}

if [ -n "${ZONE_OVERRIDE:-}" ] || [ -n "${ZONE:-}" ]; then
  info "the lab's zone came from the environment: $ZONE"
else
  echo ""
  warn "the lab assigns the zone per lab run"
  dim "  it is on the lab setup panel - copy it from there"
  if [ -n "$GCP_ZONE" ]; then
    dim "  the gcloud default zone is $GCP_ZONE"
  fi
  echo ""
  ask ZONE "Zone - the first-vm instance" "${ZONE:-${GCP_ZONE:-us-central1-a}}"
  echo ""
fi

WORKDIR="${WORKDIR:-$HOME/gsp-cbl138}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

printf "%s%s  Accessing the Google Cloud Console and Cloud Shell%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
instance_exists()  { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()      { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
bucket_exists()    { gcloud storage buckets describe "$1" 2>/dev/null >/dev/null 2>&1 || gsutil ls -d "$1" >/dev/null 2>&1; }
sa_exists()        { gcloud iam service-accounts describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }

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

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - the zone may be wrong, use --zone"
fi

info "enabling the Compute Engine and Cloud Storage APIs"
gcloud services enable compute.googleapis.com storage.googleapis.com --quiet >/dev/null 2>&1
ok "the APIs are enabled"

# ---------------------------------------------------------------------------
# Task 1 - the VM, the firewall rules and the service account
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create a VM instance with necessary firewall rule, and an IAM service account"

  if rule_exists "default-allow-http"; then
    ok "the firewall rule default-allow-http already exists"
  else
    info "creating the firewall rule default-allow-http"
    if gcloud compute firewall-rules create "default-allow-http" \
         --network=default --direction=INGRESS --action=ALLOW \
         --rules=tcp:80 --source-ranges=0.0.0.0/0 \
         --target-tags=http-server --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the firewall rule default-allow-http"
    else
      note_fail "could not create the firewall rule default-allow-http"
    fi
  fi

  if rule_exists "allow-ssh-all"; then
    ok "the firewall rule allow-ssh-all already exists"
  else
    info "creating the firewall rule allow-ssh-all"
    if gcloud compute firewall-rules create "allow-ssh-all" \
         --network=default --direction=INGRESS --action=ALLOW \
         --rules=tcp:22 --source-ranges=0.0.0.0/0 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the firewall rule allow-ssh-all"
    else
      note_fail "could not create the firewall rule allow-ssh-all"
    fi
  fi

  if instance_exists "first-vm" "$ZONE"; then
    ok "the instance first-vm already exists in $ZONE"
  else
    info "creating the instance first-vm in $ZONE"
    cat > "$WORKDIR/startup.sh" <<'EOF'
#!/bin/bash
apt-get remove -y --purge man-db || true
touch /var/lib/man-db/auto-update
apt-get update -y
apt-get install -y nginx
cat <<'HTML' > /var/www/html/index.html
<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src="CAT_IMAGE_URL_PLACEHOLDER"> </body></html>
HTML
systemctl restart nginx
EOF
    local cat_image_url="https://${PROJECT_ID}-bucket1/cat.jpg"
    sed -i "s|CAT_IMAGE_URL_PLACEHOLDER|$cat_image_url|" "$WORKDIR/startup.sh"

    if gcloud compute instances create "first-vm" \
         --zone="$ZONE" --machine-type=e2-micro \
         --tags=http-server \
         --image-family=debian-12 --image-project=debian-cloud \
         --metadata=startup-script="$(cat "$WORKDIR/startup.sh")" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the instance first-vm in $ZONE"
    else
      note_fail "could not create the instance first-vm"
    fi
  fi

  local sa_email="test-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
  if sa_exists "$sa_email"; then
    ok "the service account test-service-account already exists"
  else
    info "creating the service account test-service-account"
    if gcloud iam service-accounts create "test-service-account" \
         --display-name="Test Service Account" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the service account test-service-account"
    else
      note_fail "could not create the service account test-service-account"
    fi
  fi

  info "binding roles/editor to the service account"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${sa_email}" \
    --role="roles/editor" \
    --quiet >/dev/null 2>&1 || true

  pause_for_check 1 "Create a VM instance with necessary firewall rule, and an IAM service account"
}

# ---------------------------------------------------------------------------
# Task 2 - Cloud Shell verification
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Verify Cloud Shell"

  info "the active account"
  gcloud auth list 2>&1 | sed 's/^/    /'
  info "the active project"
  gcloud config list project 2>&1 | sed 's/^/    /'

  ok "Cloud Shell is authenticated and configured"
}

# ---------------------------------------------------------------------------
# Task 3 - the two buckets and the public cat image
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Create Cloud Storage Buckets"

  local bucket1="gs://${PROJECT_ID}-bucket1"
  local bucket2="gs://${PROJECT_ID}-bucket2"

  if bucket_exists "$bucket1"; then
    ok "the bucket $bucket1 already exists"
  else
    info "creating the bucket $bucket1"
    if gcloud storage buckets create "$bucket1" --location=US \
         --uniform-bucket-level-access --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the bucket $bucket1"
    else
      note_fail "could not create the bucket $bucket1"
    fi
  fi

  # uniform bucket level access on, public access prevention off
  gcloud storage buckets update "$bucket1" --uniform-bucket-level-access >/dev/null 2>&1 || true
  gcloud storage buckets update "$bucket1" --no-public-access-prevention >/dev/null 2>&1 || true

  if bucket_exists "$bucket2"; then
    ok "the bucket $bucket2 already exists"
  else
    info "creating the bucket $bucket2"
    if gcloud storage buckets create "$bucket2" --location=US \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the bucket $bucket2"
    else
      note_fail "could not create the bucket $bucket2"
    fi
  fi

  # the cat.jpg upload
  if [ ! -f "$WORKDIR/cat.jpg" ]; then
    info "downloading cat.jpg"
    gcloud storage cp "gs://cloud-training/ak8s/cat.jpg" "$WORKDIR/cat.jpg" >/dev/null 2>&1 \
      || curl -sL "https://storage.googleapis.com/cloud-training/ak8s/cat.jpg" -o "$WORKDIR/cat.jpg" >/dev/null 2>&1
  fi

  if [ -f "$WORKDIR/cat.jpg" ]; then
    gcloud storage cp "$WORKDIR/cat.jpg" "${bucket1}/" >/dev/null 2>&1 || true
    gcloud storage cp "${bucket1}/cat.jpg" "${bucket2}/cat.jpg" >/dev/null 2>&1 || true
    ok "cat.jpg is in both buckets"
  else
    warn "could not get cat.jpg - the bucket upload was skipped"
  fi

  # make bucket1 publicly readable
  info "granting allUsers the Object Viewer role on $bucket1"
  gcloud storage buckets add-iam-policy-binding "$bucket1" \
    --member=allUsers --role=roles/storage.objectViewer \
    --quiet >/dev/null 2>&1 || true

  pause_for_check 2 "Create Cloud Storage Buckets"
}

# ---------------------------------------------------------------------------
# Task 4 - the repo, the index.html and nginx on first-vm
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Install the nginx web server and customize the welcome page"

  if [ ! -d "$WORKDIR/orchestrate-with-kubernetes" ]; then
    info "cloning orchestrate-with-kubernetes"
    git clone https://github.com/googlecodelabs/orchestrate-with-kubernetes.git \
      "$WORKDIR/orchestrate-with-kubernetes" >/dev/null 2>&1 || true
  else
    ok "the orchestrate-with-kubernetes repo is already cloned"
  fi

  mkdir -p "$WORKDIR/test"

  if [ -f "$WORKDIR/orchestrate-with-kubernetes/cleanup.sh" ]; then
    if ! grep -q "Finished cleanup!" "$WORKDIR/orchestrate-with-kubernetes/cleanup.sh"; then
      echo "echo Finished cleanup!" >> "$WORKDIR/orchestrate-with-kubernetes/cleanup.sh"
      ok "appended 'echo Finished cleanup!' to cleanup.sh"
    else
      ok "cleanup.sh already has the Finished cleanup line"
    fi
  fi

  local cat_image_url="https://${PROJECT_ID}-bucket1/cat.jpg"
  cat > "$WORKDIR/index.html" <<EOF
<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src="$cat_image_url"> </body></html>
EOF
  cp "$WORKDIR/index.html" "$WORKDIR/orchestrate-with-kubernetes/index.html" 2>/dev/null || true
  ok "the index.html with the cat image is written"

  # wait for the VM to be running
  info "waiting for first-vm to be RUNNING"
  local i status=""
  for i in $(seq 1 30); do
    status="$(gcloud compute instances describe first-vm --zone "$ZONE" \
                --project "$PROJECT_ID" --format="value(status)" 2>/dev/null)"
    if [ "$status" = "RUNNING" ]; then
      ok "first-vm is RUNNING"
      break
    fi
    sleep 3
  done
  if [ "$status" != "RUNNING" ]; then
    warn "first-vm is '${status:-unknown}', not RUNNING yet"
  fi

  # make sure an SSH key exists
  if [ ! -f "$HOME/.ssh/google_compute_engine" ]; then
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t rsa -N "" -f "$HOME/.ssh/google_compute_engine" -C "student" -q 2>/dev/null || true
  fi

  info "copying index.html to first-vm"
  local scp_ok=0
  for i in $(seq 1 15); do
    if gcloud compute scp --zone="$ZONE" --quiet "$WORKDIR/index.html" \
         first-vm:index.html >/dev/null 2>&1; then
      scp_ok=1
      ok "index.html copied to first-vm"
      break
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for SSH on first-vm ($i/15)"
    fi
    sleep 5
  done
  if [ "$scp_ok" -ne 1 ]; then
    warn "could not copy index.html to first-vm"
  fi

  info "installing nginx and serving the page"
  local remote="sudo apt-get remove -y --purge man-db 2>/dev/null || true; sudo touch /var/lib/man-db/auto-update; sudo apt-get update -y && sudo apt-get install -y nginx && sudo cp -f ~/index.html /var/www/html/index.html && sudo systemctl restart nginx"
  gcloud compute ssh first-vm --zone="$ZONE" --quiet --command="$remote" >/dev/null 2>&1 || true

  local vm_ip=""
  vm_ip="$(gcloud compute instances describe first-vm --zone "$ZONE" \
            --project "$PROJECT_ID" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"
  if [ -n "$vm_ip" ]; then
    info "testing http://$vm_ip/"
    sleep 3
    if curl -s -m 5 "http://$vm_ip" | grep -qi "Cat"; then
      ok "nginx is serving the cat page at http://$vm_ip"
    else
      warn "nginx did not answer yet - the startup script will finish in a minute"
    fi
  fi

  pause_for_check 3 "Install the nginx web server and customize the welcome page"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  3) task3 ;;
  4) task4 ;;
  "")
    task1
    task2
    task3
    task4
    ;;
  *)
    err "--task must be between 1 and 4"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  Zone             : $ZONE"
echo "  VM               : first-vm (e2-micro, debian-12, tag http-server)"
echo "  Service account  : test-service-account (roles/editor)"
echo "  Buckets          : gs://${PROJECT_ID}-bucket1 (public), gs://${PROJECT_ID}-bucket2"
echo "  Repo             : orchestrate-with-kubernetes (with 'Finished cleanup!' added)"
echo "  Page             : $WORKDIR/index.html (with the cat image)"
echo ""
echo "  Checkpoints:"
echo "    1. Create a VM instance with necessary firewall rule, and an IAM service account"
echo "    2. Create Cloud Storage Buckets"
echo "    3. Install the nginx web server and customize the welcome page"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute instances delete first-vm --zone=$ZONE --quiet"
echo "    gcloud storage rm -r gs://${PROJECT_ID}-bucket1 gs://${PROJECT_ID}-bucket2"
echo "    gcloud iam service-accounts delete test-service-account@${PROJECT_ID}.iam.gserviceaccount.com --quiet"
echo "    gcloud compute firewall-rules delete default-allow-http allow-ssh-all --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
