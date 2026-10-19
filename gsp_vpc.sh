#!/usr/bin/env bash
# =============================================================================
#  "Get Started with Virtual Private Cloud Networking and Compute Engine"
#  Google Cloud Arcade / Cloud Skills Boost lab.
#
#  Deletes the default network, creates an auto mode VPC network with the
#  standard firewall rules, creates two VM instances, then removes the
#  firewall rules one at a time to show what each one was doing.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc.sh
#     chmod +x gsp_vpc.sh
#     ./gsp_vpc.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region1 R       region for mynet-us-vm
#     --zone1 Z         zone for mynet-us-vm
#     --region2 R       region for mynet-r2-vm
#     --zone2 Z         zone for mynet-r2-vm
#     --network NAME    VPC network name (default: mynetwork)
#     --task N          run only task N (1-3)
#     --yes             do not pause for the checkpoint
#     -h, --help        this help
#
#  NOTES:
#   * The lab has ONE checkpoint - "Create a VPC network and VM instance" -
#     and it is scored right after task 2. Task 3 then DELETES three of the
#     firewall rules, so the script stops between task 2 and task 3 for you
#     to click 'Check my progress' first.
#   * The regions and zones are injected by the lab, so they are set at the
#     top of this script. The script prints them next to the lab setup
#     panel's wording so a mismatch is obvious.
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
REGION1_OVERRIDE=""
ZONE1_OVERRIDE=""
REGION2_OVERRIDE=""
ZONE2_OVERRIDE=""
NETWORK="mynetwork"
VM1="mynet-us-vm"
VM2="mynet-r2-vm"
MACHINE_TYPE="e2-micro"
ONLY_TASK=""
ASSUME_YES=0

# The lab's regions and zones. Injected per lab run, so they live here.
LAB_REGION1="us-central1"
LAB_ZONE1="us-central1-a"
LAB_REGION2="us-west1"
LAB_ZONE2="us-west1-b"

usage() {
  cat <<'USAGE_END'
Get Started with Virtual Private Cloud Networking and Compute Engine

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc.sh
   chmod +x gsp_vpc.sh
   ./gsp_vpc.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region1 R       region for mynet-us-vm
   --zone1 Z         zone for mynet-us-vm
   --region2 R       region for mynet-r2-vm
   --zone2 Z         zone for mynet-r2-vm
   --network NAME    VPC network name (default: mynetwork)
   --task N          run only task N (1-3)
   --yes             do not pause for the checkpoint
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT_OVERRIDE="$2"; shift 2 ;;
    --region1)  REGION1_OVERRIDE="$2"; shift 2 ;;
    --zone1)    ZONE1_OVERRIDE="$2";   shift 2 ;;
    --region2)  REGION2_OVERRIDE="$2"; shift 2 ;;
    --zone2)    ZONE2_OVERRIDE="$2";   shift 2 ;;
    --network)  NETWORK="$2";          shift 2 ;;
    --task)     ONLY_TASK="$2";        shift 2 ;;
    --yes)      ASSUME_YES=1;          shift ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve project / regions / zones
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

REGION1="${REGION1_OVERRIDE:-$LAB_REGION1}"
ZONE1="${ZONE1_OVERRIDE:-$LAB_ZONE1}"
REGION2="${REGION2_OVERRIDE:-$LAB_REGION2}"
ZONE2="${ZONE2_OVERRIDE:-$LAB_ZONE2}"

printf "%s%s  Virtual Private Cloud Networking and Compute Engine%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion1=%s  %szone1=%s  %sregion2=%s  %szone2=%s  %snetwork=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION1" "$C_DIM" "$ZONE1" "$C_DIM" "$REGION2" \
  "$C_DIM" "$ZONE2" "$C_DIM" "$NETWORK" "$C_RESET"

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
  warn "not in Cloud Shell - the zones may be wrong, use --region1/--zone1/--region2/--zone2"
fi

info "enabling the Compute Engine API"
gcloud services enable compute.googleapis.com --quiet >/dev/null 2>&1
ok "API enabled"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
net_exists()      { gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists() { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()     { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }

inst_ip() {  # $1 = name, $2 = zone, $3 = internal|external
  if [ "$3" = "internal" ]; then
    gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" \
      --format="value(networkInterfaces[0].networkIP)" 2>/dev/null
  else
    gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" \
      --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
  fi
}

wait_running() {  # $1 = name, $2 = zone
  local i
  for i in $(seq 1 "${GSP_INSTANCE_WAIT:-60}"); do
    if gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

ssh_run() {  # $1 = instance, $2 = zone, $3 = command
  gcloud compute ssh "$1" --zone "$2" --project "$PROJECT_ID" --quiet \
    --command="$3" 2>&1
}

# The internal rule is called allow-custom on an auto mode network, and
# allow-internal on the default network. Handle both.
custom_rule() {
  if rule_exists "$NETWORK-allow-custom"; then
    echo "$NETWORK-allow-custom"
  else
    echo "$NETWORK-allow-internal"
  fi
}

# ---------------------------------------------------------------------------
# Task 1 - explore and remove the default network
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Explore the default network"

  if net_exists "default"; then
    info "the default network has a subnet in every region:"
    gcloud compute networks subnets list --network default --project "$PROJECT_ID" \
      --format="table(name,region,ipCidrRange,gatewayAddress)" 2>/dev/null | head -8 | sed 's/^/    /'
    echo ""
    info "its routes:"
    gcloud compute routes list --network default --project "$PROJECT_ID" \
      --format="table(name,destRange,nextHopInstance,priority)" 2>/dev/null | head -8 | sed 's/^/    /'
    echo ""
    info "its firewall rules:"
    gcloud compute firewall-rules list --filter="network=default AND direction=INGRESS" \
      --project "$PROJECT_ID" --format="value(name)" 2>/dev/null | sed 's/^/    /'
    echo ""

    info "deleting the default network's firewall rules"
    for RULE in default-allow-icmp default-allow-rdp default-allow-ssh default-allow-internal; do
      if rule_exists "$RULE"; then
        gcloud compute firewall-rules delete "$RULE" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
          && ok "deleted $RULE" \
          || note_fail "could not delete $RULE"
      fi
    done

    info "deleting the default network"
    gcloud compute networks delete default --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "deleted the default network" \
      || note_fail "could not delete the default network"

    if net_exists "default"; then
      warn "the default network still exists - it may take a moment"
    else
      ok "no routes and no firewall rules left, and no VM can be created"
    fi
  else
    ok "the default network is already gone"
  fi
}

# ---------------------------------------------------------------------------
# Task 2 - create the VPC network and the VM instances
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create a VPC network and VM instances"

  if net_exists "$NETWORK"; then
    ok "network $NETWORK already exists"
  else
    info "creating the auto mode network $NETWORK"
    if gcloud compute networks create "$NETWORK" --subnet-mode=auto \
         --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $NETWORK (auto mode, subnets in every region)"
    else
      note_fail "could not create the network $NETWORK"
      return 1
    fi
  fi

  info "the auto mode network comes with the standard firewall rules:"
  gcloud compute firewall-rules list --filter="network=$NETWORK" --project "$PROJECT_ID" \
    --format="value(name)" 2>/dev/null | sed 's/^/    /'

  create_vm() {  # $1 = name, $2 = zone
    if instance_exists "$1" "$2"; then
      ok "$1 already exists"
      return 0
    fi
    info "creating $1 in $2 ($MACHINE_TYPE)"
    if gcloud compute instances create "$1" \
         --zone="$2" --project="$PROJECT_ID" \
         --machine-type="$MACHINE_TYPE" \
         --image-family="debian-12" --image-project="debian-cloud" \
         --network="$NETWORK" --subnet="default" --tags="$NETWORK" \
         --quiet >/dev/null 2>&1; then
      ok "created $1"
    else
      note_fail "could not create $1"
      return 1
    fi
  }

  create_vm "$VM1" "$ZONE1"
  create_vm "$VM2" "$ZONE2"

  info "waiting for the instances to boot"
  wait_running "$VM1" "$ZONE1" && ok "$VM1 is RUNNING" || warn "$VM1 is not running yet"
  wait_running "$VM2" "$ZONE2" && ok "$VM2 is RUNNING" || warn "$VM2 is not running yet"

  echo ""
  gcloud compute instances list --project "$PROJECT_ID" \
    --format="table(name,zone,machineType,networkInterface[0].networkIP,networkInterface[0].accessConfigs[0].natIP)" \
    2>/dev/null | sed 's/^/  /'
  echo ""
  dim "  $VM1 : internal $(inst_ip "$VM1" "$ZONE1" internal)   external $(inst_ip "$VM1" "$ZONE1" external)"
  dim "  $VM2 : internal $(inst_ip "$VM2" "$ZONE2" internal)   external $(inst_ip "$VM2" "$ZONE2" external)"
}

# ---------------------------------------------------------------------------
# Task 3 - explore connectivity and remove the firewall rules
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Explore the connectivity for the VM instances"

  local R2_INT R2_EXT
  R2_INT="$(inst_ip "$VM2" "$ZONE2" internal)"
  R2_EXT="$(inst_ip "$VM2" "$ZONE2" external)"

  if [ -z "$R2_INT" ] || [ -z "$R2_EXT" ]; then
    err "could not read the addresses of $VM2 - run task 2 first"
    return 1
  fi
  ok "$VM2 internal $R2_INT   external $R2_EXT"

  # --- connectivity with all the rules in place --------------------------
  echo ""
  info "ping $VM2's internal IP from $VM1 (allowed by allow-custom)"
  if ssh_run "$VM1" "$ZONE1" "ping -c 3 -W 2 $R2_INT" | grep -qE 'bytes from|3 received'; then
    ok "the internal ping works"
  else
    warn "the internal ping did not answer"
  fi

  info "ping $VM2's external IP from $VM1 (allowed by allow-icmp)"
  if ssh_run "$VM1" "$ZONE1" "ping -c 3 -W 2 $R2_EXT" | grep -qE 'bytes from|3 received'; then
    ok "the external ping works"
  else
    warn "the external ping did not answer"
  fi

  info "SSH to $VM1 from Cloud Shell (allowed by allow-ssh)"
  if ssh_run "$VM1" "$ZONE1" "echo ssh-ok" | grep -q "ssh-ok"; then
    ok "SSH works"
  else
    warn "SSH did not work"
  fi

  # --- remove the rules one at a time ------------------------------------
  echo ""
  info "removing $NETWORK-allow-icmp"
  if rule_exists "$NETWORK-allow-icmp"; then
    gcloud compute firewall-rules delete "$NETWORK-allow-icmp" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "deleted $NETWORK-allow-icmp"
  fi
  info "the external ping should now fail"
  if ssh_run "$VM1" "$ZONE1" "ping -c 3 -W 2 $R2_EXT" | grep -qE 'bytes from|3 received'; then
    warn "the external ping still answers - the rule may not have been deleted"
  else
    ok "100% packet loss, as expected"
  fi
  info "the internal ping should still work (allow-custom)"
  if ssh_run "$VM1" "$ZONE1" "ping -c 3 -W 2 $R2_INT" | grep -qE 'bytes from|3 received'; then
    ok "the internal ping still works"
  else
    warn "the internal ping stopped working too"
  fi

  echo ""
  local CUSTOM
  CUSTOM="$(custom_rule)"
  info "removing $CUSTOM"
  if rule_exists "$CUSTOM"; then
    gcloud compute firewall-rules delete "$CUSTOM" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "deleted $CUSTOM"
  fi
  info "the internal ping should now fail too"
  if ssh_run "$VM1" "$ZONE1" "ping -c 3 -W 2 $R2_INT" | grep -qE 'bytes from|3 received'; then
    warn "the internal ping still answers - the rule may not have been deleted"
  else
    ok "100% packet loss, as expected"
  fi

  echo ""
  info "removing $NETWORK-allow-ssh"
  if rule_exists "$NETWORK-allow-ssh"; then
    gcloud compute firewall-rules delete "$NETWORK-allow-ssh" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "deleted $NETWORK-allow-ssh"
  fi
  info "SSH should now fail"
  if ssh_run "$VM1" "$ZONE1" "echo ssh-ok" | grep -q "ssh-ok"; then
    warn "SSH still works - the rule may not have been deleted"
  else
    ok "the connection failed, as expected"
  fi
}

# ---------------------------------------------------------------------------
# checkpoint pause
# ---------------------------------------------------------------------------
pause_for_check() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  echo ""
  printf "  %s>>> The lab has ONE checkpoint: 'Create a VPC network and VM instance'.%s\n" "$C_BOLD" "$C_RESET"
  printf "  %s    Click 'Check my progress' for it NOW - the next step deletes three%s\n" "$C_DIM"
  printf "  %s    firewall rules, and the lab scores the network and the instances.%s\n" "$C_DIM"
  printf "  %s    Then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  3) task3 ;;
  "")
    task1
    task2
    pause_for_check
    task3
    ;;
  *)
    err "--task must be 1, 2 or 3"
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Network  : $NETWORK (auto mode)"
echo "  Instance : $VM1 in $ZONE1"
echo "  Instance : $VM2 in $ZONE2"
echo ""
gcloud compute networks list --project "$PROJECT_ID" \
  --format="table(name,subnetMode,autoCreateSubnetworks)" 2>/dev/null | sed 's/^/  /'
echo ""
gcloud compute firewall-rules list --project "$PROJECT_ID" \
  --format="table(name,network,sourceRanges.list():label=sourceRanges,allowed[].map().firewall_rule().list():label=allow)" \
  2>/dev/null | sed 's/^/  /'
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
