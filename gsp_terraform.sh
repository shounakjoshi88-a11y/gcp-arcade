#!/usr/bin/env bash
# =============================================================================
#  "Automating the Deployment of Infrastructure Using Terraform"
#  Google Cloud Arcade / Cloud Skills Boost lab (CBL036).
#
#  Builds the whole Terraform configuration the lab asks for:
#    * a mynetwork auto mode VPC with a firewall rule that opens 22, 80,
#      3389 and ICMP, and two VM instances (mynet-vm-1 and mynet-vm-2) in
#      two different zones, all declared in Terraform
#    * terraform init, plan and apply with the retry that the lab needs
#      because the subnets are still provisioning in the background
#    * the verification: the two VMs, and a ping from one to the other
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_terraform.sh
#     chmod +x gsp_terraform.sh
#     ./gsp_terraform.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone1 ZONE      the zone of mynet-vm-1 (default: from the project)
#     --zone2 ZONE      the zone of mynet-vm-2 (default: from the project)
#     --workspace PATH  where to stage the Terraform files (default: ~/tfinfra)
#     --task N          run only task N (1-3)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  CHECKPOINTS (one per lab objective):
#     1. Install Terraform and set up the workspace            (end of task 1)
#     2. Initialize, plan and apply the Terraform config       (end of task 2)
#     3. Verify the deployment and the connectivity           (end of task 3)
#
#  NOTES:
#   * Cloud Shell ships a placeholder wrapper for terraform, so the script
#     checks that the real binary is there and installs it if it is not.
#   * The apply is retried a few times, because the subnets of an auto mode
#     network are still provisioning in the background when Terraform starts.
#   * The two zones are lab-assigned per run. The script takes them from the
#     shell the lab starts (ZONE_1, ZONE_2) and asks for whatever is missing.
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
ZONE1_OVERRIDE=""
ZONE2_OVERRIDE=""
WORKSPACE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Automating the Deployment of Infrastructure Using Terraform

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_terraform.sh
   chmod +x gsp_terraform.sh
   ./gsp_terraform.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone1 ZONE      the zone of mynet-vm-1 (default: from the project)
   --zone2 ZONE      the zone of mynet-vm-2 (default: from the project)
   --workspace PATH  where to stage the Terraform files (default: ~/tfinfra)
   --task N          run only task N (1-3)
   --yes             do not pause for the checkpoints
   --no-verify       do not run the ping between the VMs
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)    PROJECT_OVERRIDE="$2";    shift 2 ;;
    --zone1)      ZONE1_OVERRIDE="$2";     shift 2 ;;
    --zone2)      ZONE2_OVERRIDE="$2";     shift 2 ;;
    --workspace)  WORKSPACE_OVERRIDE="$2"; shift 2 ;;
    --task)       ONLY_TASK="$2";          shift 2 ;;
    --yes)        ASSUME_YES=1;            shift ;;
    --no-verify)  DO_VERIFY=0;             shift ;;
    -h|--help)    usage ;;
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

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

ask() {  # $1 = variable name, $2 = label, $3 = default
  local __name="$1" __label="$2" __default="$3" __ans=""
  printf "  %s%s%s [%s]: " "$C_BOLD" "$__label" "$C_RESET" "$__default"
  if ! read -r __ans; then
    echo ""
    __ans=""
  fi
  printf -v "$__name" '%s' "${__ans:-$__default}"
}

ZONE1="${ZONE1_OVERRIDE:-${ZONE_1:-${GCP_ZONE:-us-central1-a}}}"
ZONE2="${ZONE2_OVERRIDE:-${ZONE_2:-}}"

if [ -n "$ZONE1" ] && [ -n "$ZONE2" ]; then
  info "the lab's zones came from the environment: $ZONE1, $ZONE2"
fi

echo ""
warn "the lab assigns the two zones per lab run"
dim "  they are on the lab setup panel - copy them from there"
if [ -n "$GCP_ZONE" ]; then
  dim "  the gcloud default zone is $GCP_ZONE"
fi
echo ""

ask ZONE1 "Zone 1 - mynet-vm-1" "${ZONE1:-${GCP_ZONE:-us-central1-a}}"
ask ZONE2 "Zone 2 - mynet-vm-2 (a different zone)" "${ZONE2:-us-central1-b}"
[ "$ZONE1" = "$ZONE2" ] && ZONE2="us-central1-b"
[ "$ZONE1" = "$ZONE2" ] && ZONE2="us-central1-c"
echo ""

WORKSPACE="${WORKSPACE_OVERRIDE:-$HOME/tfinfra}"
mkdir -p "$WORKSPACE/instance" 2>/dev/null

printf "%s%s  Automating the Deployment of Infrastructure Using Terraform%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone1=%s  %szone2=%s  %sworkspace=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE1" "$C_DIM" "$ZONE2" "$C_DIM" "$WORKSPACE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
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

run_capture() {  # $1 = log file, rest = command
  local log="$1"; shift
  local rc=0
  "$@" > "$log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then return 0; fi
  dim "  the command that failed:"
  tail -6 "$log" 2>/dev/null | sed 's/^/    /'
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
  warn "not in Cloud Shell - the zones may be wrong, use --zone1/--zone2"
fi

info "enabling the Compute Engine API"
gcloud services enable compute.googleapis.com --quiet >/dev/null 2>&1
ok "the Compute Engine API is enabled"

# ---------------------------------------------------------------------------
# Task 1 - install Terraform and set up the workspace
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Set up Terraform and the workspace"

  if ! terraform version 2>&1 | grep -q 'Terraform v'; then
    info "Cloud Shell ships a placeholder wrapper - installing the real Terraform"
    if command -v wget >/dev/null 2>&1; then
      wget -O - https://apt.releases.hashicorp.com/gpg 2>/dev/null \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
      sudo apt update -qq && sudo apt install -y -qq terraform 2>&1 | tail -3
      hash -r
    else
      note_fail "wget is not available - install Terraform by hand and re-run"
      return 1
    fi
  fi

  if terraform version 2>&1 | grep -q 'Terraform v'; then
    ok "$(terraform version | head -1)"
  else
    note_fail "Terraform is not available on PATH"
    return 1
  fi

  # The lab stages everything in ~/tfinfra.
  mkdir -p "$WORKSPACE/instance"

  info "writing provider.tf"
  cat > "$WORKSPACE/provider.tf" <<'EOF'
provider "google" {}
EOF

  info "writing instance/variables.tf"
  cat > "$WORKSPACE/instance/variables.tf" <<'EOF'
variable "instance_name" {}
variable "instance_zone" {}
variable "instance_type" {
  default = "e2-micro"
}
variable "instance_network" {}
EOF

  info "writing instance/main.tf"
  cat > "$WORKSPACE/instance/main.tf" <<'EOF'
resource "google_compute_instance" "vm_instance" {
  name         = "${var.instance_name}"
  zone         = "${var.instance_zone}"
  machine_type = "${var.instance_type}"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "${var.instance_network}"
    access_config {
      # Allocate a one-to-one NAT IP to the instance
    }
  }
}
EOF

  info "writing mynetwork.tf"
  cat > "$WORKSPACE/mynetwork.tf" <<EOF
# Create the mynetwork network resource
resource "google_compute_network" "mynetwork" {
  name                    = "mynetwork"
  auto_create_subnetworks = "true"
}

# Add a firewall rule to allow HTTP, SSH, RDP and ICMP traffic on mynetwork
resource "google_compute_firewall" "mynetwork-allow-http-ssh-rdp-icmp" {
  name    = "mynetwork-allow-http-ssh-rdp-icmp"
  network = google_compute_network.mynetwork.self_link
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "3389"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

# Create the mynet-vm-1 instance
module "mynet-vm-1" {
  source           = "./instance"
  instance_name    = "mynet-vm-1"
  instance_zone    = "${ZONE1}"
  instance_network = google_compute_network.mynetwork.self_link
}

# Create the mynet-vm-2 instance
module "mynet-vm-2" {
  source           = "./instance"
  instance_name    = "mynet-vm-2"
  instance_zone    = "${ZONE2}"
  instance_network = google_compute_network.mynetwork.self_link
}
EOF

  info "formatting the Terraform configuration"
  ( cd "$WORKSPACE" && terraform fmt >/dev/null 2>&1 ) || true
  ok "the workspace is staged in $WORKSPACE"

  dim "  provider.tf, instance/variables.tf, instance/main.tf, mynetwork.tf"
  dim "  mynet-vm-1 in $ZONE1, mynet-vm-2 in $ZONE2"

  pause_for_check 1 "Install Terraform and set up the workspace"
}

# ---------------------------------------------------------------------------
# Task 2 - initialize, plan and apply
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Initialize, plan and apply the Terraform configuration"

  cd "$WORKSPACE" || { note_fail "could not enter $WORKSPACE"; return 1; }

  info "initializing Terraform"
  if run_live "$WORKSPACE/init.log" terraform init; then
    ok "Terraform initialized"
  else
    note_fail "terraform init failed"
    dim "  the log is in $WORKSPACE/init.log"
    return 1
  fi

  info "planning the deployment"
  if run_live "$WORKSPACE/plan.log" terraform plan; then
    ok "the plan looks good"
  else
    note_fail "terraform plan failed"
    dim "  the log is in $WORKSPACE/plan.log"
    return 1
  fi

  info "applying the configuration (creating the network, the firewall rule and the two VMs)"
  local i applied=0
  for i in 1 2 3 4; do
    if run_live "$WORKSPACE/apply.log" terraform apply -auto-approve; then
      applied=1
      break
    fi
    if [ "$i" -lt 4 ]; then
      warn "the subnets are still provisioning in the background - retrying in 15s"
      sleep 15
    fi
  done
  if [ "$applied" -ne 1 ]; then
    note_fail "terraform apply failed after 4 attempts"
    dim "  the log is in $WORKSPACE/apply.log"
    return 1
  fi
  ok "the infrastructure is deployed"

  pause_for_check 2 "Initialize, plan and apply the Terraform configuration"
}

# ---------------------------------------------------------------------------
# Task 3 - verify the deployment and the connectivity
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Verify the deployment and the connectivity"

  info "the VM instances"
  gcloud compute instances list --filter="name:(mynet-vm-1 OR mynet-vm-2)" \
    --format="table(name,zone,networkInterfaces[0].networkIP,status)" \
    --project "$PROJECT_ID" 2>/dev/null | sed 's/^/    /'

  local vm2_ip=""
  vm2_ip="$(gcloud compute instances describe mynet-vm-2 --zone="$ZONE2" \
              --project "$PROJECT_ID" --format="value(networkInterfaces[0].networkIP)" 2>/dev/null)"
  if [ -z "$vm2_ip" ]; then
    warn "could not read the IP of mynet-vm-2 - skipping the ping"
    pause_for_check 3 "Verify the deployment and the connectivity"
    return 0
  fi
  dim "    mynet-vm-2 is at $vm2_ip"

  if [ "${DO_VERIFY:-1}" = "1" ]; then
    info "waiting for the VMs to be ready"
    sleep 15
    info "pinging mynet-vm-2 from mynet-vm-1"
    gcloud compute ssh mynet-vm-1 --zone="$ZONE1" --project "$PROJECT_ID" \
      --tunnel-through-iap --quiet --command="ping -c 3 $vm2_ip" 2>&1 | sed 's/^/    /'
  fi

  pause_for_check 3 "Verify the deployment and the connectivity"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
DO_VERIFY="${DO_VERIFY:-1}"
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
echo "  Project          : $PROJECT_ID"
echo "  Zones            : $ZONE1 (mynet-vm-1), $ZONE2 (mynet-vm-2)"
echo "  Workspace        : $WORKSPACE"
echo ""
echo "  Checkpoints:"
echo "    1. Install Terraform and set up the workspace"
echo "    2. Initialize, plan and apply the Terraform configuration"
echo "    3. Verify the deployment and the connectivity"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    cd $WORKSPACE && terraform destroy -auto-approve"
echo "    rm -rf $WORKSPACE"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
