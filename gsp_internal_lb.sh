#!/usr/bin/env bash
# =============================================================================
#  "Configure an Internal Network Load Balancer"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 644569).
#
#  Builds the whole internal passthrough Network Load Balancer the lab asks
#  for:
#    1  the two firewall rules - lb-access (10.10.0.0/16) and the health
#       check rule (130.211.0.0/22,35.191.0.0/16), both tagged lb-backend
#    2  a Cloud NAT configuration, so the backends can reach the package
#       mirrors without an external IP
#    3  two instance templates (one per subnet) and the utility VM
#    4  two managed instance groups, one per zone
#    5  the internal load balancer at 10.10.30.5 and the test from the
#       utility VM
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_internal_lb.sh
#     chmod +x gsp_internal_lb.sh
#     ./gsp_internal_lb.sh
#
#  OPTIONS:
#     --project ID    GCP project (default: active gcloud project)
#     --region REGION the lab's region (default: from the my-internal-app subnets)
#     --zone1 ZONE    the zone of instance-group-1 and subnet-a
#     --zone2 ZONE    the zone of instance-group-2 and subnet-b
#     --zone3 ZONE    the zone of the utility-vm
#     --task N        run only task N (1-5)
#     --yes           do not pause for the checkpoints
#     --no-verify     do not test the load balancer
#     -h, --help      this help
#
#  CHECKPOINTS (one per lab objective):
#     1. Create internal traffic and health check firewall rules   (end of task 1)
#     2. Create a NAT configuration using Cloud Router             (end of task 2)
#     3. Configure two instance templates                         (end of task 3)
#     4. Create two managed instance groups                        (end of task 4)
#     5. Configure and test an internal Network Load Balancer      (end of task 5)
#
#  NOTES:
#   * The lab pre-creates the my-internal-app network with subnet-a and
#     subnet-b in one region, plus the SSH/RDP/ICMP firewall rules. The
#     script detects the region from the subnets.
#   * The backends have no external IP, so the templates carry a startup
#     script that installs Apache through the Cloud NAT of task 2.
#   * The internal load balancer is a regional, passthrough TCP load
#     balancer at 10.10.30.5 on subnet-b.
#   * Creating an instance group blocks for minutes, and a silent wait
#     looks exactly like a hang, so those calls stream with a heartbeat.
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
REGION_OVERRIDE=""
ZONE1_OVERRIDE=""
ZONE2_OVERRIDE=""
ZONE3_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Configure an Internal Network Load Balancer

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_internal_lb.sh
   chmod +x gsp_internal_lb.sh
   ./gsp_internal_lb.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region REGION   the lab's region (default: from the my-internal-app subnets)
   --zone1 ZONE      the zone of instance-group-1 and subnet-a
   --zone2 ZONE      the zone of instance-group-2 and subnet-b
   --zone3 ZONE      the zone of the utility-vm
   --task N          run only task N (1-5)
   --yes             do not pause for the checkpoints
   --no-verify       do not test the load balancer
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2";   shift 2 ;;
    --region)  REGION_OVERRIDE="$2";    shift 2 ;;
    --zone1)   ZONE1_OVERRIDE="$2";    shift 2 ;;
    --zone2)   ZONE2_OVERRIDE="$2";    shift 2 ;;
    --zone3)   ZONE3_OVERRIDE="$2";    shift 2 ;;
    --task)    ONLY_TASK="$2";          shift 2 ;;
    --yes)     ASSUME_YES=1;            shift ;;
    --no-verify) DO_VERIFY=0;           shift ;;
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

WORKDIR="${WORKDIR:-$HOME/gsp-internal-lb}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
network_exists()   { gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
subnet_exists()    { gcloud compute networks subnets describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()      { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists()  { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
template_exists()  { gcloud compute instance-templates describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
mig_exists()       { gcloud compute instance-groups managed describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
hcheck_exists()    { gcloud compute health-checks describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
backend_exists()   { gcloud compute backend-services describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
addr_exists()      { gcloud compute addresses describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
fwd_exists()       { gcloud compute forwarding-rules describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
router_exists()    { gcloud compute routers describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
nat_exists()       { gcloud compute routers nats describe "$1" --router="$2" --region "$3" --project "$PROJECT_ID" >/dev/null 2>&1; }
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
# the lab's region
#
# The lab pre-creates the my-internal-app network with two subnets in one
# region. That region is the lab's region, so the script reads it from the
# subnets instead of asking for it.
# ---------------------------------------------------------------------------
NETWORK="my-internal-app"
SUBNET_A="subnet-a"
SUBNET_B="subnet-b"
TAG="backend-service"
HC_RANGES="130.211.0.0/22,35.191.0.0/16"
IAP_RANGE="35.235.240.0/20"

REGION="${REGION_OVERRIDE:-}"
if [ -z "$REGION" ]; then
  REGION="$(gcloud compute networks subnets list --network="$NETWORK" \
            --format="value(region)" 2>/dev/null | sed 's#.*/regions/##' | head -1)"
fi
if [ -z "$REGION" ]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null)"
fi
[ -z "$REGION" ] || [ "$REGION" = "(unset)" ] && REGION="us-central1"
ZONE1="${ZONE1_OVERRIDE:-${REGION}-c}"
ZONE2="${ZONE2_OVERRIDE:-${REGION}-b}"
ZONE3="${ZONE3_OVERRIDE:-${REGION}-c}"
[ "$ZONE1" = "$ZONE2" ] && ZONE2="${REGION}-b"
[ "$ZONE1" = "$ZONE3" ] && ZONE3="${REGION}-a"

printf "%s%s  Configure an Internal Network Load Balancer%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %szone1=%s  %szone2=%s  %szone3=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$ZONE1" "$C_DIM" "$ZONE2" "$C_DIM" "$ZONE3" "$C_RESET"

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
  warn "not in Cloud Shell - the region may be wrong, use --region"
fi

info "enabling the Compute Engine API"
gcloud services enable compute.googleapis.com --quiet >/dev/null 2>&1
ok "the Compute Engine API is enabled"

if network_exists "$NETWORK"; then
  ok "the network $NETWORK exists"
  if subnet_exists "$SUBNET_A" "$REGION"; then
    ok "the subnet $SUBNET_A exists in $REGION"
  fi
  if subnet_exists "$SUBNET_B" "$REGION"; then
    ok "the subnet $SUBNET_B exists in $REGION"
  fi
else
  err "the network $NETWORK does not exist - the lab creates it before you start"
  exit 1
fi

# the utility VM has no external IP, so it needs the IAP range to be allowed
if ! gcloud compute firewall-rules describe fw-allow-iap-ssh --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute firewall-rules create fw-allow-iap-ssh \
    --network="$NETWORK" --direction=INGRESS --action=ALLOW \
    --rules=tcp:22 --source-ranges="$IAP_RANGE" \
    --project "$PROJECT_ID" --quiet >/dev/null 2>&1
fi

# ---------------------------------------------------------------------------
# Task 1 - the two firewall rules
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Configure internal traffic and health check firewall rules"

  if rule_exists "fw-allow-lb-access"; then
    ok "the firewall rule fw-allow-lb-access already exists"
  else
    info "creating the firewall rule fw-allow-lb-access"
    if gcloud compute firewall-rules create "fw-allow-lb-access" \
         --network="$NETWORK" --direction=INGRESS --action=ALLOW \
         --rules=tcp,udp,icmp --source-ranges=10.10.0.0/16 \
         --target-tags="$TAG" --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the firewall rule fw-allow-lb-access"
    else
      note_fail "could not create the firewall rule fw-allow-lb-access"
    fi
  fi

  if rule_exists "fw-allow-health-checks"; then
    ok "the firewall rule fw-allow-health-checks already exists"
  else
    info "creating the firewall rule fw-allow-health-checks"
    if gcloud compute firewall-rules create "fw-allow-health-checks" \
         --network="$NETWORK" --direction=INGRESS --action=ALLOW \
         --rules=tcp:80 --source-ranges="$HC_RANGES" \
         --target-tags="$TAG" --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the firewall rule fw-allow-health-checks"
    else
      note_fail "could not create the firewall rule fw-allow-health-checks"
    fi
  fi

  dim "    both rules apply to the instances with the tag $TAG"
  dim "    the health checkers come from $HC_RANGES"

  pause_for_check 1 "Create internal traffic and health check firewall rules"
}

# ---------------------------------------------------------------------------
# Task 2 - the NAT configuration
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create a NAT configuration using Cloud Router"

  local router="nat-router-$REGION"
  if router_exists "$router" "$REGION"; then
    ok "the Cloud Router $router already exists in $REGION"
  else
    info "creating the Cloud Router $router in $REGION"
    if run_live "$WORKDIR/router.log" gcloud compute routers create "$router" \
         --network="$NETWORK" --region="$REGION" --project "$PROJECT_ID" --quiet; then
      ok "created the Cloud Router $router"
    else
      note_fail "could not create the Cloud Router $router"
      dim "  the log is in $WORKDIR/router.log"
    fi
  fi

  if nat_exists "nat-config" "$router" "$REGION"; then
    ok "the Cloud NAT nat-config already exists on $router"
  else
    info "creating the Cloud NAT nat-config on $router"
    if run_live "$WORKDIR/nat.log" gcloud compute routers nats create "nat-config" \
         --router="$router" --region="$REGION" \
         --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips \
         --project "$PROJECT_ID" --quiet; then
      ok "created the Cloud NAT nat-config"
    else
      note_fail "could not create the Cloud NAT nat-config"
      dim "  the log is in $WORKDIR/nat.log"
    fi
  fi

  info "waiting for the Cloud NAT to be RUNNING"
  local i status=""
  for i in $(seq 1 24); do
    status="$(gcloud compute routers nats describe nat-config --router="$router" \
                --region="$REGION" --project "$PROJECT_ID" \
                --format="value(status)" 2>/dev/null)"
    if [ "$status" = "RUNNING" ]; then
      ok "the Cloud NAT is RUNNING"
      break
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the Cloud NAT (${i}0s)"
    fi
    sleep 5
  done
  if [ "$status" != "RUNNING" ]; then
    warn "the Cloud NAT is '${status:-unknown}', not RUNNING yet"
  fi

  dim "    the backends have no external IP and need this NAT to reach the"
  dim "    package mirrors of the startup script"

  pause_for_check 2 "Create a NAT configuration using Cloud Router"
}

# ---------------------------------------------------------------------------
# Task 3 - the two instance templates and the utility VM
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Configure two instance templates"

  local tmpl1="instance-template-1"
  local tmpl2="instance-template-2"

  if template_exists "$tmpl1"; then
    ok "the instance template $tmpl1 already exists"
  else
    info "creating the instance template $tmpl1 (subnet-a)"
    if run_live "$WORKDIR/template1.log" gcloud compute instance-templates create "$tmpl1" \
         --machine-type=e2-micro \
         --network-interface="network=$NETWORK,subnet=$SUBNET_A" \
         --tags="$TAG" \
         --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
         --image-family=debian-12 --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance template $tmpl1"
    else
      note_fail "could not create the instance template $tmpl1"
      dim "  the log is in $WORKDIR/template1.log"
    fi
  fi

  if template_exists "$tmpl2"; then
    ok "the instance template $tmpl2 already exists"
  else
    info "creating the instance template $tmpl2 (subnet-b)"
    if run_live "$WORKDIR/template2.log" gcloud compute instance-templates create "$tmpl2" \
         --machine-type=e2-micro \
         --network-interface="network=$NETWORK,subnet=$SUBNET_B" \
         --tags="$TAG" \
         --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
         --image-family=debian-12 --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance template $tmpl2"
    else
      note_fail "could not create the instance template $tmpl2"
      dim "  the log is in $WORKDIR/template2.log"
    fi
  fi

  if instance_exists "utility-vm" "$ZONE3"; then
    ok "the utility-vm already exists in $ZONE3"
  else
    info "creating the utility-vm in $ZONE3 (no external IP)"
    if run_live "$WORKDIR/utility-vm.log" gcloud compute instances create "utility-vm" \
         --zone="$ZONE3" --machine-type=e2-medium \
         --network-interface="network=$NETWORK,subnet=$SUBNET_A,private-network-ip=10.10.20.50,no-address" \
         --image-family=debian-12 --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet; then
      ok "created the utility-vm in $ZONE3"
    else
      note_fail "could not create the utility-vm"
      dim "  the log is in $WORKDIR/utility-vm.log"
    fi
  fi

  dim "    both templates carry the startup script of the lab"
  dim "    the utility VM sits at 10.10.20.50 in $SUBNET_A"

  pause_for_check 3 "Configure two instance templates"
}

# ---------------------------------------------------------------------------
# Task 4 - the two managed instance groups
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Create two managed instance groups"

  if mig_exists "instance-group-1" "$ZONE1"; then
    ok "the instance group instance-group-1 already exists in $ZONE1"
  else
    info "creating the instance group instance-group-1 in $ZONE1 (a couple of minutes)"
    if run_live "$WORKDIR/ig1.log" gcloud compute instance-groups managed create "instance-group-1" \
         --template="instance-template-1" --zone="$ZONE1" --size=1 \
         --base-instance-name="instance-group-1" \
         --health-check="my-ilb-health-check" --initial-delay=45 \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance group instance-group-1"
    else
      note_fail "could not create the instance group instance-group-1"
      dim "  the log is in $WORKDIR/ig1.log"
    fi
  fi

  if mig_exists "instance-group-2" "$ZONE2"; then
    ok "the instance group instance-group-2 already exists in $ZONE2"
  else
    info "creating the instance group instance-group-2 in $ZONE2 (a couple of minutes)"
    if run_live "$WORKDIR/ig2.log" gcloud compute instance-groups managed create "instance-group-2" \
         --template="instance-template-2" --zone="$ZONE2" --size=1 \
         --base-instance-name="instance-group-2" \
         --health-check="my-ilb-health-check" --initial-delay=45 \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance group instance-group-2"
    else
      note_fail "could not create the instance group instance-group-2"
      dim "  the log is in $WORKDIR/ig2.log"
    fi
  fi

  # The health check has to exist before the backend service of task 5
  # can reference it.
  if ! hcheck_exists "my-ilb-health-check" "$REGION"; then
    info "creating the health check my-ilb-health-check"
    if gcloud compute health-checks create tcp "my-ilb-health-check" \
         --port=80 --region="$REGION" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the health check my-ilb-health-check"
    else
      note_fail "could not create the health check my-ilb-health-check"
    fi
  else
    ok "the health check my-ilb-health-check already exists"
  fi

  dim "    the backends get an IP from subnet-a (10.10.20.x) and subnet-b (10.10.30.x)"

  pause_for_check 4 "Create two managed instance groups"
}

# ---------------------------------------------------------------------------
# Task 5 - the internal load balancer and the test
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Configure and test an internal Network Load Balancer"

  if ! addr_exists "my-ilb-ip" "$REGION"; then
    info "reserving the static address my-ilb-ip (10.10.30.5)"
    if gcloud compute addresses create "my-ilb-ip" \
         --region="$REGION" --subnet="$SUBNET_B" --addresses=10.10.30.5 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "reserved the static address my-ilb-ip"
    else
      note_fail "could not reserve the static address my-ilb-ip"
    fi
  else
    ok "the static address my-ilb-ip already exists"
  fi

  if ! backend_exists "my-ilb" "$REGION"; then
    info "creating the backend service my-ilb"
    if gcloud compute backend-services create "my-ilb" \
         --load-balancing-scheme=INTERNAL \
         --protocol=TCP \
         --region="$REGION" \
         --health-checks="my-ilb-health-check" \
         --health-checks-region="$REGION" \
         --enable-logging --logging-sample-rate=1.0 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the backend service my-ilb"
    else
      note_fail "could not create the backend service my-ilb"
    fi
  else
    ok "the backend service my-ilb already exists"
  fi

  info "attaching instance-group-1 to the backend service"
  if gcloud compute backend-services add-backend "my-ilb" \
       --instance-group="instance-group-1" \
       --instance-group-zone="$ZONE1" \
       --region="$REGION" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "attached instance-group-1 to my-ilb"
  else
    note_fail "could not attach instance-group-1 to my-ilb"
  fi

  info "attaching instance-group-2 to the backend service"
  if gcloud compute backend-services add-backend "my-ilb" \
       --instance-group="instance-group-2" \
       --instance-group-zone="$ZONE2" \
       --region="$REGION" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "attached instance-group-2 to my-ilb"
  else
    note_fail "could not attach instance-group-2 to my-ilb"
  fi

  if ! fwd_exists "my-ilb" "$REGION"; then
    info "creating the forwarding rule my-ilb at 10.10.30.5"
    if gcloud compute forwarding-rules create "my-ilb" \
         --load-balancing-scheme=INTERNAL \
         --ports=80 \
         --network="$NETWORK" \
         --subnet="$SUBNET_B" \
         --region="$REGION" \
         --backend-service="my-ilb" \
         --backend-service-region="$REGION" \
         --address="my-ilb-ip" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the forwarding rule my-ilb"
    else
      note_fail "could not create the forwarding rule my-ilb"
    fi
  else
    ok "the forwarding rule my-ilb already exists"
  fi

  if [ "$DO_VERIFY" = "1" ]; then
    info "waiting for the load balancer to be ready"
    sleep 15
    info "testing the load balancer from the utility-vm"
    gcloud compute ssh "utility-vm" --zone="$ZONE3" --project "$PROJECT_ID" \
      --tunnel-through-iap --quiet --command="
        echo '===================================='
        echo 'Sending 10 requests to 10.10.30.5:'
        echo '===================================='
        for i in \$(seq 1 10); do
          echo -n \"Request \$i: \"
          curl -s -m 3 http://10.10.30.5 | grep -o 'Server Hostname: [^<]*' || echo 'waiting...'
        done
      " 2>&1 | sed 's/^/    /'
  fi

  pause_for_check 5 "Configure and test an internal Network Load Balancer"
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
  "")
    task1
    task2
    task3
    task4
    task5
    ;;
  *)
    err "--task must be between 1 and 5"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  Region           : $REGION"
echo "  Zones            : $ZONE1 (instance-group-1, subnet-a)"
echo "                     $ZONE2 (instance-group-2, subnet-b)"
echo "                     $ZONE3 (utility-vm)"
echo "  Network          : $NETWORK  (subnet-a 10.10.20.0/24, subnet-b 10.10.30.0/24)"
echo "  Firewall rules   : fw-allow-lb-access, fw-allow-health-checks (tag $TAG)"
echo "  Cloud NAT        : nat-config on nat-router-$REGION in $REGION"
echo "  Templates        : instance-template-1 (subnet-a), instance-template-2 (subnet-b)"
echo "  Instance groups  : instance-group-1 in $ZONE1, instance-group-2 in $ZONE2"
echo "  Health check     : my-ilb-health-check (TCP port 80)"
echo "  Backend service  : my-ilb (INTERNAL, TCP)"
echo "  Forwarding rule  : my-ilb at 10.10.30.5 (subnet-b)"
echo "  Utility VM       : utility-vm at 10.10.20.50 (subnet-a)"
echo ""
echo "  Checkpoints:"
echo "    1. Create internal traffic and health check firewall rules"
echo "    2. Create a NAT configuration using Cloud Router"
echo "    3. Configure two instance templates"
echo "    4. Create two managed instance groups"
echo "    5. Configure and test an internal Network Load Balancer"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute forwarding-rules delete my-ilb --region=$REGION --quiet"
echo "    gcloud compute backend-services delete my-ilb --region=$REGION --quiet"
echo "    gcloud compute health-checks delete my-ilb-health-check --region=$REGION --quiet"
echo "    gcloud compute instance-groups managed delete instance-group-1 --zone=$ZONE1 --quiet"
echo "    gcloud compute instance-groups managed delete instance-group-2 --zone=$ZONE2 --quiet"
echo "    gcloud compute instance-templates delete instance-template-1 instance-template-2 --quiet"
echo "    gcloud compute instances delete utility-vm --zone=$ZONE3 --quiet"
echo "    gcloud compute routers nats delete nat-config --router=nat-router-$REGION --region=$REGION --quiet"
echo "    gcloud compute routers delete nat-router-$REGION --region=$REGION --quiet"
echo "    gcloud compute firewall-rules delete fw-allow-lb-access fw-allow-health-checks --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
