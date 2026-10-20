#!/usr/bin/env bash
# =============================================================================
#  "Create and Configure VPC Networks"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19093).
#
#  Deletes the default network, creates an auto mode VPC (mynetwork) with the
#  four standard firewall rules, converts it to custom mode, then creates the
#  managementnet and privatenet custom networks with their subnets, firewall
#  rules and VM instances.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc_networks.sh
#     chmod +x gsp_vpc_networks.sh
#     ./gsp_vpc_networks.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone1 ZONE      the lab's first zone   (asked for)
#     --zone2 ZONE      the lab's second zone  (asked for)
#     --region1 REGION  region for the "-us" subnets (default: from zone1)
#     --region2 REGION  region for the "-notus" subnet (default: from zone2)
#     --image IMAGE     boot disk image family (default: from the project)
#     --network NAME    the auto mode network (default: mynetwork)
#     --task N          run only task N (1-4)
#     --yes             do not pause for the checkpoints
#     --keep-default    do not delete the default network
#     -h, --help        this help
#
#  CHECKPOINTS (100 points):
#     1. Create a VPC network and VM instances                  (30) - end of task 2
#     2. Create custom mode VPC networks with firewall rules   (40) - end of task 3
#     3. Create VM instances                                   (30) - end of task 3
#
#  NOTES:
#   * The two zones are injected by the lab per run, so the script asks for
#     them. The regions are derived from the zones, because the lab's
#     default_region is the region of default_zone.
#   * In an auto mode network the subnet is named after the NETWORK, not
#     "default" - mynetwork gets a "mynetwork" subnet in every region.
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
REGION1_OVERRIDE=""
REGION2_OVERRIDE=""
IMAGE_OVERRIDE=""
NETWORK="mynetwork"
ONLY_TASK=""
ASSUME_YES=0
KEEP_DEFAULT=0

usage() {
  cat <<'USAGE_END'
Create and Configure VPC Networks

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc_networks.sh
   chmod +x gsp_vpc_networks.sh
   ./gsp_vpc_networks.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone1 ZONE      the lab's first zone   (asked for)
   --zone2 ZONE      the lab's second zone  (asked for)
   --region1 REGION  region for the "-us" subnets (default: from zone1)
   --region2 REGION  region for the "-notus" subnet (default: from zone2)
   --image IMAGE     boot disk image family (default: from the project)
   --network NAME    the auto mode network (default: mynetwork)
   --task N          run only task N (1-4)
   --yes             do not pause for the checkpoints
   --keep-default    do not delete the default network
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2";  shift 2 ;;
    --zone1)        ZONE1_OVERRIDE="$2";    shift 2 ;;
    --zone2)        ZONE2_OVERRIDE="$2";    shift 2 ;;
    --region1)      REGION1_OVERRIDE="$2";  shift 2 ;;
    --region2)      REGION2_OVERRIDE="$2";  shift 2 ;;
    --image)        IMAGE_OVERRIDE="$2";    shift 2 ;;
    --network)      NETWORK="$2";           shift 2 ;;
    --task)         ONLY_TASK="$2";         shift 2 ;;
    --yes)          ASSUME_YES=1;           shift ;;
    --keep-default) KEEP_DEFAULT=1;         shift ;;
    -h|--help)      usage ;;
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
# the two lab zones
# ---------------------------------------------------------------------------
ask_zone() {  # $1 = variable name, $2 = label, $3 = default
  local __var="$1" label="$2" def="$3" ans
  if [ -n "${!__var}" ]; then return 0; fi
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  printf "  %s%s%s  [%s]: " "$C_BOLD" "$label" "$C_RESET" "$def"
  read -r ans
  printf -v "$__var" '%s' "${ans:-$def}"
}

# The lab's two zones are injected per run, so ask for them. The region of a
# zone is the zone with its last segment removed.
detect_zone_from_metadata() {
  local meta
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  [ -z "$meta" ] && return 1
  printf '%s' "$meta" | grep -oE '\b[a-z]+-[a-z]+[0-9]-[a-z]\b' | head -1
}

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""

META_ZONE="$(detect_zone_from_metadata || true)"

echo ""
warn "the lab assigns the zones per lab run - they cannot be read from the project"
dim "  they are on your lab setup panel (Zone and Zone 2)."
if [ -n "$META_ZONE" ]; then
  dim "  the project metadata mentions: $META_ZONE"
fi
ask_zone ZONE1_OVERRIDE "Zone 1" "${ZONE1_OVERRIDE:-${META_ZONE:-${GCP_ZONE:-us-central1-a}}}"
ask_zone ZONE2_OVERRIDE "Zone 2" "${ZONE2_OVERRIDE:-${META_ZONE:-${GCP_ZONE:-us-central1-a}}}"
echo ""

ZONE1="${ZONE1_OVERRIDE:-${GCP_ZONE:-us-central1-a}}"
ZONE2="${ZONE2_OVERRIDE:-${ZONE1}}"
REGION1="${REGION1_OVERRIDE:-${ZONE1%-*}}"
REGION2="${REGION2_OVERRIDE:-${ZONE2%-*}}"

# ---------------------------------------------------------------------------
# the boot disk image
# ---------------------------------------------------------------------------
resolve_image() {
  if [ -n "$IMAGE_OVERRIDE" ]; then echo "$IMAGE_OVERRIDE"; return 0; fi
  local meta found
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  if [ -n "$meta" ]; then
    found="$(printf '%s' "$meta" \
      | grep -oE 'debian-[0-9]+(-[a-z]+)?' | head -1)"
    if [ -n "$found" ]; then echo "$found"; return 0; fi
  fi
  echo "debian-12"
}
IMAGE="$(resolve_image)"

# ---------------------------------------------------------------------------
# names
# ---------------------------------------------------------------------------
VM_US="mynet-us-vm"
VM_NOTUS="mynet-notus-vm"
VM_MGMT="managementnet-us-vm"
VM_PRIV="privatenet-us-vm"
SUBNET_MGMT="managementsubnet-us"
SUBNET_PRIV="privatesubnet-us"
SUBNET_PRIV_NOTUS="privatesubnet-notus"

printf "%s%s  Create and Configure VPC Networks%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone1=%s  %szone2=%s  %sregion1=%s  %sregion2=%s  %simage=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE1" "$C_DIM" "$ZONE2" "$C_DIM" "$REGION1" \
  "$C_DIM" "$REGION2" "$C_DIM" "$IMAGE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
network_exists() {
  gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

subnet_exists() {
  gcloud compute networks subnets describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1
}

rule_exists() {
  gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

instance_exists() {
  gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1
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
  warn "not in Cloud Shell - the zones may be wrong, use --zone1 / --zone2"
fi

info "enabling the Compute Engine, IAP and Network Management APIs"
gcloud services enable compute.googleapis.com iap.googleapis.com networkmanagement.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

# ---------------------------------------------------------------------------
# Task 1 - explore (and remove) the default network
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Explore the default network"

  if network_exists "default"; then
    if [ "$KEEP_DEFAULT" = "1" ]; then
      warn "leaving the default network in place (--keep-default)"
    else
      info "deleting the four default firewall rules"
      for r in default-allow-icmp default-allow-internal default-allow-rdp default-allow-ssh; do
        if rule_exists "$r"; then
          gcloud compute firewall-rules delete "$r" --quiet --project "$PROJECT_ID" >/dev/null 2>&1 \
            && ok "deleted $r" || note_fail "could not delete $r"
        fi
      done
      info "deleting the default network"
      if gcloud compute networks delete default --quiet --project "$PROJECT_ID" >/dev/null 2>&1; then
        ok "deleted the default network"
      else
        note_fail "could not delete the default network"
        dim "  something is still attached to it - remove that and re-run"
      fi
    fi
  else
    ok "the default network is already gone"
  fi
}

# ---------------------------------------------------------------------------
# Task 2 - the auto mode network, its firewall rules and its VMs
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create an auto mode network"

  if network_exists "$NETWORK"; then
    ok "the network $NETWORK already exists"
  else
    if gcloud compute networks create "$NETWORK" --subnet-mode=auto \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $NETWORK in auto mode"
    else
      note_fail "could not create $NETWORK"
      return 1
    fi
  fi

  # The console creates these four rules when you tick "all available rules".
  # The CLI does not, so they have to be made explicitly.
  info "creating the four standard firewall rules for $NETWORK"
  create_rule() {  # $1 name, $2 priority, $3 rules, $4 source ranges
    if rule_exists "$1"; then
      ok "$1 already exists"
      return 0
    fi
    if gcloud compute firewall-rules create "$1" \
         --network="$NETWORK" --direction=INGRESS --priority="$2" \
         --action=ALLOW --rules="$3" --source-ranges="$4" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $1"
    else
      note_fail "could not create $1"
    fi
  }
  create_rule "${NETWORK}-allow-custom" 65534 "all"      "10.128.0.0/9"
  create_rule "${NETWORK}-allow-icmp"   65534 "icmp"     "0.0.0.0/0"
  create_rule "${NETWORK}-allow-rdp"    65534 "tcp:3389" "0.0.0.0/0"
  create_rule "${NETWORK}-allow-ssh"    65534 "tcp:22"   "0.0.0.0/0"

  info "creating the allow-iap-ssh rule"
  if rule_exists "allow-iap-ssh"; then
    ok "allow-iap-ssh already exists"
  else
    if gcloud compute firewall-rules create "allow-iap-ssh" \
         --network="$NETWORK" --direction=INGRESS --priority=1000 \
         --action=ALLOW --rules="tcp:22" --source-ranges="35.235.240.0/20" \
         --target-tags="iap-gce" --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created allow-iap-ssh"
    else
      note_fail "could not create allow-iap-ssh"
    fi
  fi

  info "creating the two VM instances"
  create_mynet_vm() {  # $1 name, $2 zone
    if instance_exists "$1" "$2"; then
      ok "$1 already exists in $2"
      return 0
    fi
    if gcloud compute instances create "$1" \
         --zone="$2" \
         --machine-type=e2-medium \
         --network-interface="network=$NETWORK,subnet=$NETWORK" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --tags=iap-gce \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $1 in $2"
    else
      note_fail "could not create $1"
    fi
  }
  # In an auto mode network the subnet is named after the NETWORK, and one
  # exists in every region - so the subnet name is the same in both zones.
  create_mynet_vm "$VM_US"    "$ZONE1"
  create_mynet_vm "$VM_NOTUS" "$ZONE2"

  info "converting $NETWORK to a custom mode network"
  CURRENT_MODE="$(gcloud compute networks describe "$NETWORK" --project "$PROJECT_ID" \
                  --format="value(subnetMode)" 2>/dev/null)"
  if [ "$CURRENT_MODE" = "CUSTOM" ]; then
    ok "$NETWORK is already in custom mode"
  else
    if gcloud compute networks update "$NETWORK" --switch-to-custom-subnet-mode \
         --quiet --project "$PROJECT_ID" >/dev/null 2>&1; then
      ok "$NETWORK is now in custom mode"
    else
      note_fail "could not convert $NETWORK to custom mode"
    fi
  fi

  pause_for_check 2 "Create a VPC network and VM instances"
}

# ---------------------------------------------------------------------------
# Task 3 - the custom mode networks, firewall rules and VMs
# ---------------------------------------------------------------------------
create_custom_network() {  # $1 name
  if network_exists "$1"; then
    ok "the network $1 already exists"
    return 0
  fi
  if gcloud compute networks create "$1" --subnet-mode=custom \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created $1 in custom mode"
  else
    note_fail "could not create $1"
    return 1
  fi
}

create_subnet() {  # $1 subnet, $2 network, $3 region, $4 range
  if subnet_exists "$1" "$3"; then
    ok "the subnet $1 already exists in $3"
    return 0
  fi
  if gcloud compute networks subnets create "$1" \
       --network="$2" --region="$3" --range="$4" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created $1 in $3 ($4)"
  else
    note_fail "could not create $1"
  fi
}

create_icmp_ssh_rdp_rule() {  # $1 network
  local name="${1}-allow-icmp-ssh-rdp"
  if rule_exists "$name"; then
    ok "$name already exists"
    return 0
  fi
  if gcloud compute firewall-rules create "$name" \
       --network="$1" --direction=INGRESS --priority=1000 \
       --action=ALLOW --rules="icmp,tcp:22,tcp:3389" --source-ranges="0.0.0.0/0" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created $name"
  else
    note_fail "could not create $name"
  fi
}

create_custom_vm() {  # $1 name, $2 zone, $3 subnet, $4 network
  if instance_exists "$1" "$2"; then
    ok "$1 already exists in $2"
    return 0
  fi
  if gcloud compute instances create "$1" \
       --zone="$2" \
       --machine-type=e2-micro \
       --network-interface="network=$4,subnet=$3" \
       --image-family="$IMAGE" --image-project=debian-cloud \
       --boot-disk-size=10GB --boot-disk-type=pd-standard \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created $1 in $2 on $3"
  else
    note_fail "could not create $1"
  fi
}

task3() {
  step "Task 3 - Create custom mode networks"

  create_custom_network "managementnet"
  create_subnet "$SUBNET_MGMT" "managementnet" "$REGION1" "10.240.0.0/20"

  create_custom_network "privatenet"
  create_subnet "$SUBNET_PRIV"       "privatenet" "$REGION1" "172.16.0.0/24"
  create_subnet "$SUBNET_PRIV_NOTUS" "privatenet" "$REGION2" "172.20.0.0/20"

  info "creating the firewall rules"
  create_icmp_ssh_rdp_rule "managementnet"
  create_icmp_ssh_rdp_rule "privatenet"

  pause_for_check 3 "Create custom mode VPC networks with firewall rules"

  info "creating the VM instances"
  create_custom_vm "$VM_MGMT" "$ZONE1" "$SUBNET_MGMT" "managementnet"
  create_custom_vm "$VM_PRIV" "$ZONE1" "$SUBNET_PRIV" "privatenet"

  pause_for_check 3 "Create VM instances"
}

# ---------------------------------------------------------------------------
# Task 4 - explore the connectivity across networks
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Explore the connectivity across networks"

  dim "    \$ gcloud compute instances list --sort-by=ZONE"
  gcloud compute instances list --project "$PROJECT_ID" --sort-by=ZONE \
    --format="table(name,zone,networkInterfaces[0].network,networkInterfaces[0].subnetwork,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null \
    | sed 's/^/      /'

  cat <<EOF

  ${C_BOLD}What the lab expects:${C_RESET}
    ${C_GREEN}ping the EXTERNAL IPs${C_RESET} of every instance   ${C_DIM}-> works${C_RESET}
    ${C_GREEN}ping the INTERNAL IP${C_RESET} of $VM_NOTUS
       ${C_DIM}-> works, it is on the same VPC network ($NETWORK)${C_RESET}
    ${C_RED}ping the INTERNAL IPs${C_RESET} of $VM_MGMT and $VM_PRIV
       ${C_DIM}-> 100% packet loss, they are in separate VPC networks${C_RESET}

  ${C_DIM}To try it yourself:${C_RESET}
    gcloud compute ssh $VM_US --zone=$ZONE1 --tunnel-through-iap

EOF
  ok "the connectivity table is printed above"
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
echo "  Project     : $PROJECT_ID"
echo "  Zone 1      : $ZONE1     (region $REGION1)"
echo "  Zone 2      : $ZONE2     (region $REGION2)"
echo "  Networks    : $NETWORK (custom), managementnet (custom), privatenet (custom)"
echo "  Subnets     : $SUBNET_MGMT, $SUBNET_PRIV, $SUBNET_PRIV_NOTUS"
echo "  VMs         : $VM_US, $VM_NOTUS, $VM_MGMT, $VM_PRIV"
echo ""
echo "  Checkpoints:"
echo "    1. Create a VPC network and VM instances                 (30)"
echo "    2. Create custom mode VPC networks with firewall rules  (40)"
echo "    3. Create VM instances                                  (30)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute instances delete $VM_US $VM_MGMT $VM_PRIV --zone=$ZONE1 --quiet"
echo "    gcloud compute instances delete $VM_NOTUS --zone=$ZONE2 --quiet"
echo "    gcloud compute networks delete $NETWORK managementnet privatenet --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
