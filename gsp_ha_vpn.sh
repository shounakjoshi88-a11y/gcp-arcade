#!/usr/bin/env bash
# =============================================================================
#  "Configure Google Cloud HA VPN"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 644549).
#
#  Builds the whole HA VPN topology the lab asks for:
#    * a custom mode VPC "vpc-demo" with one subnet and one VM in each of
#      the lab's two regions
#    * a second VPC "on-prem" that plays the customer's data centre, with
#      its own subnet and VM
#    * an HA VPN gateway and a Cloud Router in each VPC, four tunnels between
#      the two gateways (interface 0 to 0, interface 1 to 1) and BGP peering
#      on all four of them
#    * global dynamic routing, so the second region of vpc-demo can be
#      reached from on-prem
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_ha_vpn.sh
#     chmod +x gsp_ha_vpn.sh
#     ./gsp_ha_vpn.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region1 REGION  the lab's REGION 1 (default: from zone1)
#     --region2 REGION  the lab's REGION 2 (default: from zone2)
#     --zone1 ZONE      zone of vpc-demo-instance1  (in REGION 1)
#     --zone2 ZONE      zone of vpc-demo-instance2  (in REGION 2)
#     --zone3 ZONE      zone of on-prem-instance1   (in REGION 1)
#     --secret SECRET   the IKE shared secret (default: generated once)
#     --machine-type T  the VM machine type (default: e2-medium)
#     --task N          run only task N (1-9)
#     --yes             do not pause for the checkpoints
#     --no-verify       do not wait for the tunnels and skip the ping test
#     -h, --help        this help
#
#  CHECKPOINTS:
#     1. Create the vpc-demo VPC network, its subnets and its VMs
#     2. Create the on-prem VPC network, its subnet and its VM
#     3. Create the HA VPN gateways
#     4. Create the Cloud Routers
#     5. Create the four VPN tunnels
#     6. Create the BGP interfaces and the BGP peers
#     7. Allow the traffic between the two VPCs
#     8. Turn on global dynamic routing
#     9. Verify the HA VPN configuration
#
#  NOTES:
#   * The lab injects the two regions and the three zones per run. The script
#     reads them from the shell the lab starts (ZONE, ZONE_1, ZONE_2) and
#     asks for whatever is missing.
#   * Everything HA VPN lives in ONE region. The gateway, its router, the
#     peer gateway and the tunnels all have to be in the same region or the
#     tunnel create call is rejected. That region is REGION 1, the region of
#     the on-prem network.
#   * The two tunnels of a gateway have to be wired interface 0 to interface
#     0 and interface 1 to interface 1. A crossed pair still builds, and the
#     99.99% SLA does not hold.
#   * Creating a gateway or a tunnel blocks for about a minute, and a silent
#     wait looks exactly like a hang, so those calls stream with a heartbeat.
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
REGION2_OVERRIDE=""
ZONE1_OVERRIDE=""
ZONE2_OVERRIDE=""
ZONE3_OVERRIDE=""
SECRET_OVERRIDE=""
MACHINE_TYPE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Configure Google Cloud HA VPN

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_ha_vpn.sh
   chmod +x gsp_ha_vpn.sh
   ./gsp_ha_vpn.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region1 REGION  the lab's REGION 1 (default: from zone1)
   --region2 REGION  the lab's REGION 2 (default: from zone2)
   --zone1 ZONE      zone of vpc-demo-instance1  (in REGION 1)
   --zone2 ZONE      zone of vpc-demo-instance2  (in REGION 2)
   --zone3 ZONE      zone of on-prem-instance1   (in REGION 1)
   --secret SECRET   the IKE shared secret (default: generated once and kept)
   --machine-type T  the VM machine type (default: e2-medium)
   --task N          run only task N (1-9)
   --yes             do not pause for the checkpoints
   --no-verify       do not wait for the tunnels and skip the ping test
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2";       shift 2 ;;
    --region1)      REGION1_OVERRIDE="$2";       shift 2 ;;
    --region2)      REGION2_OVERRIDE="$2";       shift 2 ;;
    --zone1)        ZONE1_OVERRIDE="$2";         shift 2 ;;
    --zone2)        ZONE2_OVERRIDE="$2";         shift 2 ;;
    --zone3)        ZONE3_OVERRIDE="$2";         shift 2 ;;
    --secret)       SECRET_OVERRIDE="$2";        shift 2 ;;
    --machine-type) MACHINE_TYPE_OVERRIDE="$2";  shift 2 ;;
    --task)         ONLY_TASK="$2";              shift 2 ;;
    --yes)          ASSUME_YES=1;                shift ;;
    --no-verify)    DO_VERIFY=0;                 shift ;;
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

WORKDIR="${WORKDIR:-$HOME/gsp-ha-vpn}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

# ---------------------------------------------------------------------------
# the lab's regions and zones
#
# The lab injects them per run and they cannot be read from the project.
# Arcade starts the shell with them in the environment:
#   ZONE    - the zone of vpc-demo-instance1
#   ZONE_1  - the zone of vpc-demo-instance2
#   ZONE_2  - the zone of on-prem-instance1
# Whatever is missing is asked for. Every answer has a default, so pressing
# Enter all the way through still produces a working topology.
# ---------------------------------------------------------------------------
ask() {  # $1 = variable name, $2 = label, $3 = default
  local __name="$1" __label="$2" __default="$3" __ans=""
  printf "  %s%s%s [%s]: " "$C_BOLD" "$__label" "$C_RESET" "$__default"
  if ! read -r __ans; then
    echo ""
    __ans=""
  fi
  printf -v "$__name" '%s' "${__ans:-$__default}"
}

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""

ZONE1="${ZONE1_OVERRIDE:-${ZONE:-}}"
ZONE2="${ZONE2_OVERRIDE:-${ZONE_1:-}}"
ZONE3="${ZONE3_OVERRIDE:-${ZONE_2:-}}"

if [ -n "$ZONE1" ] && [ -n "$ZONE2" ] && [ -n "$ZONE3" ]; then
  info "the lab's zones came from the environment: $ZONE1, $ZONE2, $ZONE3"
else
  echo ""
  warn "the lab assigns the regions and the zones per lab run"
  dim "  they are on the lab setup panel - copy them from there"
  if [ -n "$GCP_ZONE" ]; then
    dim "  the gcloud default zone is $GCP_ZONE"
  fi
  echo ""
  ask ZONE1 "Zone 1 - vpc-demo-instance1 (in REGION 1)" "${ZONE1:-${GCP_ZONE:-us-central1-a}}"
  ask ZONE2 "Zone 2 - vpc-demo-instance2 (in REGION 2)" "${ZONE2:-us-east1-b}"
  ask ZONE3 "Zone 3 - on-prem-instance1   (in REGION 1)" "${ZONE3:-us-central1-b}"
  echo ""
fi

REGION1="${REGION1_OVERRIDE:-${ZONE1%-*}}"
REGION2="${REGION2_OVERRIDE:-${ZONE2%-*}}"
[ -z "$REGION1" ] && REGION1="us-central1"
[ -z "$REGION2" ] && REGION2="us-east1"

if [ "$REGION1" = "$REGION2" ]; then
  warn "REGION 1 and REGION 2 are both $REGION1 - the lab uses two different regions"
  warn "check --region1 and --region2"
fi

# ---------------------------------------------------------------------------
# names, ranges and the rest of the lab's fixed values
# ---------------------------------------------------------------------------
MACHINE_TYPE="${MACHINE_TYPE_OVERRIDE:-e2-medium}"
IMAGE_FAMILY="debian-12"

VPC="vpc-demo"
SUBNET1="vpc-demo-subnet1"
SUBNET2="vpc-demo-subnet2"
RANGE1="10.1.1.0/24"
RANGE2="10.2.1.0/24"
VM1="vpc-demo-instance1"
VM2="vpc-demo-instance2"

ONPREM="on-prem"
ONPREM_SUBNET="on-prem-subnet1"
ONPREM_RANGE="192.168.1.0/24"
ONPREM_VM="on-prem-instance1"

GW1="vpc-demo-vpn-gw1"
GW2="on-prem-vpn-gw1"
ROUTER1="vpc-demo-router1"
ROUTER2="on-prem-router1"
ASN1=65001
ASN2=65002

T_VPC0="vpc-demo-tunnel0"
T_VPC1="vpc-demo-tunnel1"
T_ONP0="on-prem-tunnel0"
T_ONP1="on-prem-tunnel1"

# The IKE shared secret. It is generated once and kept, so that a re-run
# recreates the tunnels with the same secret.
SECRET_FILE="$WORKDIR/shared_secret"
if [ -n "$SECRET_OVERRIDE" ]; then
  SECRET="$SECRET_OVERRIDE"
elif [ -f "$SECRET_FILE" ]; then
  SECRET="$(cat "$SECRET_FILE" 2>/dev/null)"
else
  SECRET="$(head -c 24 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [ -z "$SECRET" ] && SECRET="raksha-ha-vpn-shared-secret-0001"
  printf '%s' "$SECRET" > "$SECRET_FILE" 2>/dev/null
fi

printf "%s%s  Configure Google Cloud HA VPN%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sREGION 1=%s  %sREGION 2=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION1" "$C_DIM" "$REGION2" "$C_RESET"
printf "  %szone1=%s  %szone2=%s  %szone3=%s  %ssecret=%s%s\n" \
  "$C_DIM" "$ZONE1" "$C_DIM" "$ZONE2" "$C_DIM" "$ZONE3" "$C_DIM" "kept in $SECRET_FILE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
network_exists()   { gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
subnet_exists()    { gcloud compute networks subnets describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()      { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists()  { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
gateway_exists()   { gcloud compute vpn-gateways describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
router_exists()    { gcloud compute routers describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
tunnel_exists()    { gcloud compute vpn-tunnels describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }

router_has_interface() {  # $1 = router, $2 = interface name
  gcloud compute routers describe "$1" --region "$REGION1" --project "$PROJECT_ID" \
    --format="value(bgp[0].interfaces[].name)" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

router_has_peer() {  # $1 = router, $2 = peer name
  gcloud compute routers describe "$1" --region "$REGION1" --project "$PROJECT_ID" \
    --format="value(bgp[0].peers[].name)" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

tunnel_status() {  # $1 = tunnel
  gcloud compute vpn-tunnels describe "$1" --region "$REGION1" --project "$PROJECT_ID" \
    --format="value(status)" 2>/dev/null
}

instance_ip() {  # $1 = instance, $2 = zone
  gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" \
    --format="value(networkInterfaces[0].networkIP)" 2>/dev/null
}

# Run a command and show its output as it arrives. Creating a VPN gateway or
# a tunnel blocks for about a minute while the operation runs, and a silent
# wait looks exactly like a hang.
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

# The zone a VM goes into has to be in the region of its subnet, otherwise
# the create call fails with "subnet not found in that zone".
zone_in_region() { [ "${1%-*}" = "$2" ]; }

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
  warn "not in Cloud Shell - the regions and zones may be wrong, use --region1/--region2/--zone1..."
fi

info "enabling the Compute Engine API"
gcloud services enable compute.googleapis.com --quiet >/dev/null 2>&1
ok "the Compute Engine API is enabled"

# ---------------------------------------------------------------------------
# Task 1 - the vpc-demo VPC, its subnets, its firewall rules and its VMs
# ---------------------------------------------------------------------------
ensure_network() {  # $1 = name
  local n="$1"
  if network_exists "$n"; then
    ok "the network $n already exists"
    return 0
  fi
  info "creating the network $n in custom mode"
  if gcloud compute networks create "$n" --subnet-mode=custom \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created the network $n"
  else
    note_fail "could not create the network $n"
    return 1
  fi
}

ensure_subnet() {  # $1 = name, $2 = network, $3 = range, $4 = region
  local n="$1" net="$2" range="$3" region="$4"
  if subnet_exists "$n" "$region"; then
    ok "the subnet $n already exists in $region"
    return 0
  fi
  info "creating the subnet $n in $region ($range)"
  if gcloud compute networks subnets create "$n" \
       --network="$net" --region="$region" --range="$range" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created the subnet $n in $region"
  else
    note_fail "could not create the subnet $n in $region"
    return 1
  fi
}

ensure_firewall() {  # $1 = name, $2 = network, $3 = allow, $4 = source ranges
  local n="$1" net="$2" allow="$3" src="$4"
  if rule_exists "$n"; then
    ok "the firewall rule $n already exists"
    return 0
  fi
  info "creating the firewall rule $n"
  if gcloud compute firewall-rules create "$n" \
       --network="$net" --direction=INGRESS --action=ALLOW \
       --rules="$allow" --source-ranges="$src" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created the firewall rule $n"
  else
    note_fail "could not create the firewall rule $n"
    return 1
  fi
}

ensure_instance() {  # $1 = name, $2 = network, $3 = subnet, $4 = zone, $5 = region
  local n="$1" net="$2" subnet="$3" zone="$4" region="$5"
  if ! zone_in_region "$zone" "$region"; then
    warn "the zone $zone is not in $region - the lab puts that VM in $region"
    zone="${region}-a"
    info "using $zone instead"
  fi
  if instance_exists "$n" "$zone"; then
    ok "$n already exists in $zone"
  else
    info "creating $n in $zone (this takes about a minute)"
    if run_live "$WORKDIR/instance-$n.log" gcloud compute instances create "$n" \
         --zone="$zone" --machine-type="$MACHINE_TYPE" \
         --network-interface="network=$net,subnet=$subnet" \
         --image-family="$IMAGE_FAMILY" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet; then
      ok "created $n in $zone"
    else
      note_fail "could not create $n in $zone"
      dim "  the log is in $WORKDIR/instance-$n.log"
      return 1
    fi
  fi

  info "waiting for $n to start"
  local i status=""
  for i in $(seq 1 40); do
    status="$(gcloud compute instances describe "$n" --zone "$zone" --project "$PROJECT_ID" \
                --format="value(status)" 2>/dev/null)"
    if [ "$status" = "RUNNING" ]; then
      ok "$n is RUNNING"
      break
    fi
    if [ $((i % 4)) -eq 0 ]; then
      info "waiting for $n to start (${i}0s)"
    fi
    sleep 5
  done
  if [ "$status" != "RUNNING" ]; then
    warn "$n is '${status:-unknown}', not RUNNING yet"
  fi
  return 0
}

task1() {
  step "Task 1 - The vpc-demo VPC network, its subnets and its VMs"

  ensure_network "$VPC" || return 1
  ensure_subnet "$SUBNET1" "$VPC" "$RANGE1" "$REGION1" || return 1
  ensure_subnet "$SUBNET2" "$VPC" "$RANGE2" "$REGION2" || return 1

  ensure_firewall "vpc-demo-allow-custom" "$VPC" \
    "tcp:0-65535,udp:0-65535,icmp" "10.0.0.0/8" || return 1
  ensure_firewall "vpc-demo-allow-ssh-icmp" "$VPC" \
    "tcp:22,icmp" "0.0.0.0/0" || return 1

  ensure_instance "$VM1" "$VPC" "$SUBNET1" "$ZONE1" "$REGION1" || return 1
  ensure_instance "$VM2" "$VPC" "$SUBNET2" "$ZONE2" "$REGION2" || return 1

  pause_for_check 1 "Create the vpc-demo VPC network and the VM instances"
}

# ---------------------------------------------------------------------------
# Task 2 - the on-prem VPC, its subnet and its VM
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - The on-prem VPC network, its subnet and its VM"

  ensure_network "$ONPREM" || return 1
  ensure_subnet "$ONPREM_SUBNET" "$ONPREM" "$ONPREM_RANGE" "$REGION1" || return 1

  ensure_firewall "on-prem-allow-custom" "$ONPREM" \
    "tcp:0-65535,udp:0-65535,icmp" "192.168.0.0/16" || return 1
  ensure_firewall "on-prem-allow-ssh-icmp" "$ONPREM" \
    "tcp:22,icmp" "0.0.0.0/0" || return 1

  ensure_instance "$ONPREM_VM" "$ONPREM" "$ONPREM_SUBNET" "$ZONE3" "$REGION1" || return 1

  pause_for_check 2 "Create the on-prem VPC network and the VM instance"
}

# ---------------------------------------------------------------------------
# Task 3 - the HA VPN gateways
# ---------------------------------------------------------------------------
ensure_gateway() {  # $1 = name, $2 = network
  local n="$1" net="$2"
  if gateway_exists "$n" "$REGION1"; then
    ok "the gateway $n already exists in $REGION1"
    return 0
  fi
  info "creating the HA VPN gateway $n in $REGION1 (about a minute)"
  if run_live "$WORKDIR/gateway-$n.log" gcloud compute vpn-gateways create "$n" \
       --network="$net" --region="$REGION1" --project "$PROJECT_ID" --quiet; then
    ok "created the HA VPN gateway $n"
  elif run_live "$WORKDIR/gateway-$n.log" gcloud beta compute vpn-gateways create "$n" \
       --network="$net" --region="$REGION1" --project "$PROJECT_ID" --quiet; then
    ok "created the HA VPN gateway $n (beta command)"
  else
    note_fail "could not create the HA VPN gateway $n"
    dim "  the log is in $WORKDIR/gateway-$n.log"
    return 1
  fi

  info "waiting for the gateway $n to get its two interfaces"
  local i gw=""
  for i in $(seq 1 20); do
    gw="$(gcloud compute vpn-gateways describe "$n" --region "$REGION1" --project "$PROJECT_ID" \
            --format="value(gatewayInterfaces[0].name)" 2>/dev/null)"
    if [ -n "$gw" ]; then
      ok "the gateway $n has its interfaces"
      break
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the gateway interfaces (${i}0s)"
    fi
    sleep 5
  done
  if [ -z "$gw" ]; then
    warn "the gateway $n has no interfaces yet - check the console"
  fi
  return 0
}

task3() {
  step "Task 3 - The HA VPN gateways"

  ensure_gateway "$GW1" "$VPC" || return 1
  ensure_gateway "$GW2" "$ONPREM" || return 1

  pause_for_check 3 "Create the HA VPN gateways"
}

# ---------------------------------------------------------------------------
# Task 4 - the Cloud Routers
# ---------------------------------------------------------------------------
ensure_router() {  # $1 = name, $2 = network, $3 = asn
  local n="$1" net="$2" asn="$3"
  if router_exists "$n" "$REGION1"; then
    ok "the Cloud Router $n already exists in $REGION1"
    return 0
  fi
  info "creating the Cloud Router $n in $REGION1 (asn $asn)"
  if run_live "$WORKDIR/router-$n.log" gcloud compute routers create "$n" \
       --network="$net" --region="$REGION1" --asn="$asn" \
       --project "$PROJECT_ID" --quiet; then
    ok "created the Cloud Router $n"
  else
    note_fail "could not create the Cloud Router $n"
    dim "  the log is in $WORKDIR/router-$n.log"
    return 1
  fi
}

task4() {
  step "Task 4 - The Cloud Routers"

  ensure_router "$ROUTER1" "$VPC" "$ASN1" || return 1
  ensure_router "$ROUTER2" "$ONPREM" "$ASN2" || return 1

  pause_for_check 4 "Create the Cloud Routers"
}

# ---------------------------------------------------------------------------
# Task 5 - the four VPN tunnels
# ---------------------------------------------------------------------------
ensure_tunnel() {  # $1 = name, $2 = gateway, $3 = peer gateway, $4 = router, $5 = interface
  local n="$1" gw="$2" peer="$3" router="$4" iface="$5"
  if tunnel_exists "$n" "$REGION1"; then
    ok "the tunnel $n already exists in $REGION1"
    return 0
  fi
  info "creating the tunnel $n - gateway $gw interface $iface to $peer"
  if run_live "$WORKDIR/tunnel-$n.log" gcloud compute vpn-tunnels create "$n" \
       --vpn-gateway="$gw" --peer-gcp-gateway="$peer" \
       --router="$router" --interface="$iface" \
       --region="$REGION1" --ike-version=2 --shared-secret="$SECRET" \
       --project "$PROJECT_ID" --quiet; then
    ok "created the tunnel $n"
  elif run_live "$WORKDIR/tunnel-$n.log" gcloud beta compute vpn-tunnels create "$n" \
       --vpn-gateway="$gw" --peer-gcp-gateway="$peer" \
       --router="$router" --interface="$iface" \
       --region="$REGION1" --ike-version=2 --shared-secret="$SECRET" \
       --project "$PROJECT_ID" --quiet; then
    ok "created the tunnel $n (beta command)"
  else
    note_fail "could not create the tunnel $n"
    dim "  the log is in $WORKDIR/tunnel-$n.log"
    dim "  the gateway, the peer gateway, the router and the tunnel all have to be"
    dim "  in the same region ($REGION1) and the interfaces have to match."
    return 1
  fi
}

task5() {
  step "Task 5 - The VPN tunnels"

  ensure_tunnel "$T_VPC0" "$GW1" "$GW2" "$ROUTER1" 0 || return 1
  ensure_tunnel "$T_VPC1" "$GW1" "$GW2" "$ROUTER1" 1 || return 1
  ensure_tunnel "$T_ONP0" "$GW2" "$GW1" "$ROUTER2" 0 || return 1
  ensure_tunnel "$T_ONP1" "$GW2" "$GW1" "$ROUTER2" 1 || return 1

  pause_for_check 5 "Create the VPN tunnels"
}

# ---------------------------------------------------------------------------
# Task 6 - the BGP interfaces and the BGP peers
# ---------------------------------------------------------------------------
ensure_bgp_interface() {  # $1 = router, $2 = interface name, $3 = ip, $4 = tunnel
  local router="$1" name="$2" ip="$3" tunnel="$4"
  if router_has_interface "$router" "$name"; then
    ok "the BGP interface $name already exists on $router"
    return 0
  fi
  info "adding the BGP interface $name ($ip/30) to $router"
  if gcloud compute routers add-interface "$router" \
       --interface-name="$name" --ip-address="$ip" --mask-length=30 \
       --vpn-tunnel="$tunnel" --region="$REGION1" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "added the BGP interface $name"
  else
    note_fail "could not add the BGP interface $name to $router"
    return 1
  fi
}

ensure_bgp_peer() {  # $1 = router, $2 = peer name, $3 = interface, $4 = peer ip, $5 = peer asn
  local router="$1" name="$2" iface="$3" ip="$4" asn="$5"
  if router_has_peer "$router" "$name"; then
    ok "the BGP peer $name already exists on $router"
    return 0
  fi
  info "adding the BGP peer $name (asn $asn) to $router"
  if gcloud compute routers add-bgp-peer "$router" \
       --peer-name="$name" --interface="$iface" \
       --peer-ip-address="$ip" --peer-asn="$asn" \
       --region="$REGION1" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "added the BGP peer $name"
  else
    note_fail "could not add the BGP peer $name to $router"
    return 1
  fi
}

task6() {
  step "Task 6 - The BGP peering for every tunnel"

  ensure_bgp_interface "$ROUTER1" "if-tunnel0-to-on-prem" "169.254.0.1" "$T_VPC0" || return 1
  ensure_bgp_peer      "$ROUTER1" "bgp-on-prem-tunnel0"  "if-tunnel0-to-on-prem" "169.254.0.2" "$ASN2" || return 1

  ensure_bgp_interface "$ROUTER1" "if-tunnel1-to-on-prem" "169.254.1.1" "$T_VPC1" || return 1
  ensure_bgp_peer      "$ROUTER1" "bgp-on-prem-tunnel1"  "if-tunnel1-to-on-prem" "169.254.1.2" "$ASN2" || return 1

  ensure_bgp_interface "$ROUTER2" "if-tunnel0-to-vpc-demo" "169.254.0.2" "$T_ONP0" || return 1
  ensure_bgp_peer      "$ROUTER2" "bgp-vpc-demo-tunnel0"  "if-tunnel0-to-vpc-demo" "169.254.0.1" "$ASN1" || return 1

  ensure_bgp_interface "$ROUTER2" "if-tunnel1-to-vpc-demo" "169.254.1.2" "$T_ONP1" || return 1
  ensure_bgp_peer      "$ROUTER2" "bgp-vpc-demo-tunnel1"  "if-tunnel1-to-vpc-demo" "169.254.1.1" "$ASN1" || return 1

  pause_for_check 6 "Create the BGP peering for each tunnel"
}

# ---------------------------------------------------------------------------
# Task 7 - the firewall rules that let the two VPCs talk to each other
# ---------------------------------------------------------------------------
task7() {
  step "Task 7 - The firewall rules between the two VPCs"

  ensure_firewall "vpc-demo-allow-subnets-from-on-prem" "$VPC" \
    "tcp,udp,icmp" "$ONPREM_RANGE" || return 1
  ensure_firewall "on-prem-allow-subnets-from-vpc-demo" "$ONPREM" \
    "tcp,udp,icmp" "$RANGE1,$RANGE2" || return 1

  pause_for_check 7 "Allow the traffic between the two VPCs"
}

# ---------------------------------------------------------------------------
# Task 8 - global dynamic routing
# ---------------------------------------------------------------------------
set_routing_mode() {  # $1 = network, $2 = mode
  local n="$1" mode="$2"
  local current
  current="$(gcloud compute networks describe "$n" --project "$PROJECT_ID" \
              --format="value(bgpRoutingMode)" 2>/dev/null)"
  [ -z "$current" ] && current="$(gcloud compute networks describe "$n" --project "$PROJECT_ID" \
              --format="value(routingConfig.routingMode)" 2>/dev/null)"
  if [ "$current" = "$mode" ]; then
    ok "the network $n already has $mode dynamic routing"
    return 0
  fi
  info "setting the dynamic routing of $n to $mode"
  if gcloud compute networks update "$n" --bgp-routing-mode="$mode" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the network $n now uses $mode dynamic routing"
  elif gcloud beta compute networks update "$n" --bgp-routing-mode="$mode" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the network $n now uses $mode dynamic routing (beta command)"
  else
    note_fail "could not set the dynamic routing of $n to $mode"
    return 1
  fi
}

task8() {
  step "Task 8 - Global dynamic routing"

  # vpc-demo is the one the lab asks for: it makes the second region of
  # vpc-demo reachable from on-prem.
  set_routing_mode "$VPC" "GLOBAL" || return 1

  # on-prem is set to global as well. The lab only asks for vpc-demo, but
  # with regional routing the on-prem router would not advertise a subnet
  # that sits in another region, and the ping in task 9 would fail.
  set_routing_mode "$ONPREM" "GLOBAL"

  pause_for_check 8 "Enable global dynamic routing"
}

# ---------------------------------------------------------------------------
# Task 9 - verify the configuration
# ---------------------------------------------------------------------------
wait_for_tunnels() {
  local i n t all
  for i in $(seq 1 30); do
    all=1
    for n in "$T_VPC0" "$T_VPC1" "$T_ONP0" "$T_ONP1"; do
      t="$(tunnel_status "$n")"
      if [ "$t" != "ESTABLISHED" ]; then all=0; fi
    done
    if [ "$all" = "1" ]; then
      ok "all four tunnels are ESTABLISHED"
      return 0
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the tunnels to come up (${i}0s)"
    fi
    sleep 5
  done
  warn "the tunnels are not ESTABLISHED yet - they can take a few minutes"
  for n in "$T_VPC0" "$T_VPC1" "$T_ONP0" "$T_ONP1"; do
    dim "    $n: $(tunnel_status "$n")"
  done
  return 1
}

bgp_established_count() {  # $1 = router
  gcloud compute routers get-status "$1" --region "$REGION1" --project "$PROJECT_ID" \
    --format="value(bgp[0].peers[].state)" 2>/dev/null | tr ' ' '\n' | grep -c "ESTABLISHED"
}

wait_for_bgp() {
  local i c c2
  for i in $(seq 1 30); do
    c="$(bgp_established_count "$ROUTER1")"
    c2="$(bgp_established_count "$ROUTER2")"
    if [ "${c:-0}" -ge 2 ] 2>/dev/null && [ "${c2:-0}" -ge 2 ] 2>/dev/null; then
      ok "the BGP peers are ESTABLISHED on both routers"
      return 0
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the BGP sessions (${i}0s)"
    fi
    sleep 5
  done
  warn "the BGP sessions are not up yet - they can take a few minutes"
  return 1
}

ping_from_onprem() {  # $1 = target ip, $2 = label
  local target="$1" label="$2" out
  if [ -z "$target" ]; then
    warn "no IP for $label, skipping the ping"
    return 1
  fi
  info "pinging $label ($target) from $ONPREM_VM"
  out="$(gcloud compute ssh "$ONPREM_VM" --zone "$ZONE3" --project "$PROJECT_ID" \
          --quiet --command="ping -c 3 -W 2 $target" 2>&1)"
  if printf '%s' "$out" | grep -q "bytes from"; then
    ok "$ONPREM_VM reaches $label"
    return 0
  fi
  warn "$ONPREM_VM does not reach $label yet"
  printf '%s\n' "$out" | tail -5 | sed 's/^/      /'
  return 1
}

task9() {
  step "Task 9 - Verify the HA VPN configuration"

  if [ "$DO_VERIFY" != "1" ]; then
    dim "  --no-verify was given, skipping the checks"
    return 0
  fi

  info "the tunnels of the two gateways have to come up on their own"
  wait_for_tunnels

  info "the BGP sessions have to establish on top of that"
  wait_for_bgp

  local ip1 ip2
  ip1="$(instance_ip "$VM1" "$ZONE1")"
  ip2="$(instance_ip "$VM2" "$ZONE2")"
  dim "    $VM1: $ip1"
  dim "    $VM2: $ip2"

  ping_from_onprem "$ip1" "$VM1"
  ping_from_onprem "$ip2" "$VM2"

  echo ""
  info "the tunnel status"
  gcloud compute vpn-tunnels list --region "$REGION1" --project "$PROJECT_ID" \
    --format="table(name,status,peerGateway)" 2>/dev/null | sed 's/^/    /'

  pause_for_check 9 "Verify and test the HA VPN gateway configuration"
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
  7) task7 ;;
  8) task8 ;;
  9) task9 ;;
  "")
    task1
    task2
    task3
    task4
    task5
    task6
    task7
    task8
    task9
    ;;
  *)
    err "--task must be between 1 and 9"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  REGION 1         : $REGION1   REGION 2: $REGION2"
echo "  Zones            : $ZONE1 (vpc-demo-instance1)"
echo "                     $ZONE2 (vpc-demo-instance2)"
echo "                     $ZONE3 (on-prem-instance1)"
echo "  VPC vpc-demo     : $SUBNET1 $RANGE1 in $REGION1"
echo "                     $SUBNET2 $RANGE2 in $REGION2"
echo "  VPC on-prem      : $ONPREM_SUBNET $ONPREM_RANGE in $REGION1"
echo "  Gateways         : $GW1, $GW2  (in $REGION1)"
echo "  Cloud Routers    : $ROUTER1 (asn $ASN1), $ROUTER2 (asn $ASN2)"
echo "  Tunnels          : $T_VPC0, $T_VPC1, $T_ONP0, $T_ONP1"
echo "  Shared secret    : $SECRET_FILE"
echo ""
echo "  Checkpoints:"
echo "    1. Create the vpc-demo VPC network and the VM instances"
echo "    2. Create the on-prem VPC network and the VM instance"
echo "    3. Create the HA VPN gateways"
echo "    4. Create the Cloud Routers"
echo "    5. Create the VPN tunnels"
echo "    6. Create the BGP peering for each tunnel"
echo "    7. Allow the traffic between the two VPCs"
echo "    8. Enable global dynamic routing"
echo "    9. Verify the HA VPN configuration"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute vpn-tunnels delete $T_VPC0 $T_VPC1 --region=$REGION1 --quiet"
echo "    gcloud compute vpn-tunnels delete $T_ONP0 $T_ONP1 --region=$REGION1 --quiet"
echo "    gcloud compute routers delete $ROUTER1 $ROUTER2 --region=$REGION1 --quiet"
echo "    gcloud compute vpn-gateways delete $GW1 $GW2 --region=$REGION1 --quiet"
echo "    gcloud compute instances delete $VM1 --zone=$ZONE1 --quiet"
echo "    gcloud compute instances delete $VM2 --zone=$ZONE2 --quiet"
echo "    gcloud compute instances delete $ONPREM_VM --zone=$ZONE3 --quiet"
echo "    gcloud compute networks delete $VPC $ONPREM --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
