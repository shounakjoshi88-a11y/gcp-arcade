#!/usr/bin/env bash
# =============================================================================
#  "Configure an Application Load Balancer with Autoscaling"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 644564).
#
#  Builds the whole application load balancer the lab asks for:
#    1  the firewall rule that lets the health checkers and the load balancer
#       reach the backends on port 80
#    2  a Cloud NAT configuration, so the web server VM can install Apache
#       without an external IP
#    3  a custom image with a running Apache, taken from a throw away VM
#    4  an instance template, a health check and two managed instance groups
#       with autoscaling, one in each of the lab's two regions
#    5  the global Application Load Balancer with an IPv4 and an IPv6
#       frontend, and the two backends
#    6  the stress test that makes the instance groups scale up
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_alb_autoscaling.sh
#     chmod +x gsp_alb_autoscaling.sh
#     ./gsp_alb_autoscaling.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region1 REGION  the lab's first region  (us-* , the NAT and us-1-mig)
#     --region2 REGION  the lab's second region (not us-*, the notus-1-mig)
#     --zone1 ZONE      the zone of the web server VM (in REGION 1)
#     --stress-region R the region of the stress test VM
#     --stress-zone Z   the zone of the stress test VM
#     --task N          run only task N (1-6)
#     --yes             do not pause for the checkpoints
#     --no-verify       do not wait for the load balancer and skip the stress test
#     -h, --help        this help
#
#  CHECKPOINTS (one per lab objective):
#     1. Create a health check firewall rule                 (end of task 1)
#     2. Create a NAT configuration using Cloud Router       (end of task 2)
#     3. Create a custom image for a web server              (end of task 3)
#     4. Create an instance template and two instance groups  (end of task 4)
#     5. Configure an Application Load Balancer (HTTP)       (end of task 5)
#     6. Stress test an Application Load Balancer (HTTP)     (end of task 6)
#
#  NOTES:
#   * The lab fixes the first region, the first zone and the second region:
#     the Cloud NAT, the web server VM and the us-1-mig group live in
#     us-east4 (zone us-east4-c), the notus-1-mig group in asia-south1. Only
#     the stress test VM is left to the student - it goes in a region that is
#     different but closer to us-east4 than to asia-south1, so the load
#     balancer has to pick the closer backend.
#   * The instance template must NOT pin a subnet. A template is a global
#     resource and both instance groups use it - one in each region - so the
#     VM has to pick up the default subnet of its own region.
#   * The web server VM has no external IP on purpose, so Apache is
#     installed by a startup script that goes out through the Cloud NAT of
#     task 2. That is the only way the VM can reach the package mirrors.
#   * The health check is HTTP, not TCP. A global HTTP health check is also
#     what the autohealing of a regional instance group accepts.
#   * Creating an image, an instance group or a load balancer blocks for
#     minutes, and a silent wait looks exactly like a hang, so those calls
#     stream with a heartbeat.
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

# The autohealing of a regional instance group only accepts a legacy
# health check. A health check that was created in the newer form has to
# be replaced, and that is done once.
HC_REPLACED=0

PROJECT_OVERRIDE=""
REGION1_OVERRIDE=""
REGION2_OVERRIDE=""
ZONE1_OVERRIDE=""
STRESS_REGION_OVERRIDE=""
STRESS_ZONE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Configure an Application Load Balancer with Autoscaling

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_alb_autoscaling.sh
   chmod +x gsp_alb_autoscaling.sh
   ./gsp_alb_autoscaling.sh

OPTIONS:
   --project ID       GCP project (default: active gcloud project)
   --region1 REGION   the lab's first region  (the NAT and us-1-mig)
   --region2 REGION   the lab's second region (the notus-1-mig)
   --zone1 ZONE       the zone of the web server VM (in REGION 1)
   --stress-region R  the region of the stress test VM
   --stress-zone Z    the zone of the stress test VM
   --task N           run only task N (1-6)
   --yes              do not pause for the checkpoints
   --no-verify        do not wait for the load balancer and skip the stress test
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)       PROJECT_OVERRIDE="$2";        shift 2 ;;
    --region1)       REGION1_OVERRIDE="$2";        shift 2 ;;
    --region2)       REGION2_OVERRIDE="$2";        shift 2 ;;
    --zone1)         ZONE1_OVERRIDE="$2";          shift 2 ;;
    --stress-region) STRESS_REGION_OVERRIDE="$2";  shift 2 ;;
    --stress-zone)   STRESS_ZONE_OVERRIDE="$2";    shift 2 ;;
    --task)          ONLY_TASK="$2";               shift 2 ;;
    --yes)           ASSUME_YES=1;                 shift ;;
    --no-verify)     DO_VERIFY=0;                  shift ;;
    -h|--help)       usage ;;
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

WORKDIR="${WORKDIR:-$HOME/gsp-alb-autoscaling}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

# ---------------------------------------------------------------------------
# the lab's regions and zones
#
# The lab injects them per run and they cannot be read from the project.
# Arcade starts the shell with some of them in the environment - ZONE,
# ZONE_1, ZONE_2, REGION, REGION_1, REGION_2. Whatever is missing is asked
# for, and every answer is checked against the API before it is used: a lab
# project does not necessarily allow every zone, and a zone that cannot be
# fetched comes back as
#   Permission denied on 'locations/<zone>' (or it may not exist)
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

zone_usable() {  # $1 = zone
  gcloud compute zones describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

region_usable() {  # $1 = region
  gcloud compute regions describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

# Ask for a region. A value that is already good is taken as it is.
# Sets REPLY.
acquire_region() {  # $1 = label, $2 = current value, $3 = region it has to differ from
  local label="$1" current="$2" other="${3:-}"
  local ans note="" tries=0 default="$2"

  if [ -n "$current" ]; then
    if ! region_usable "$current"; then
      warn "there is no region $current"
    elif [ -n "$other" ] && [ "$current" = "$other" ]; then
      warn "the two regions cannot both be $current"
    else
      REPLY="$current"
      return 0
    fi
  fi

  while :; do
    if [ -n "$note" ]; then
      warn "$note"
    fi
    printf "  %s%s%s [%s]: " "$C_BOLD" "$label" "$C_RESET" "$default"
    if ! read -r ans; then
      echo ""
      ans=""
    fi
    ans="${ans:-$default}"
    tries=$((tries + 1))
    if [ "$tries" -gt 6 ]; then
      err "too many rejected regions - giving up"
      exit 2
    fi
    if ! region_usable "$ans"; then
      note="there is no region $ans - give another one"
      continue
    fi
    if [ -n "$other" ] && [ "$ans" = "$other" ]; then
      note="the two regions have to be different - give another one"
      continue
    fi
    REPLY="$ans"
    return 0
  done
}

# The zones of a region. The API list is the source of truth, but a project
# that is restricted to a few zones can refuse the list as well, so the
# usual letters are the fallback.
region_zones() {  # $1 = region
  local out
  out="$(gcloud compute zones list --format="value(name)" 2>/dev/null | grep "^${1}-")"
  if [ -z "$out" ]; then
    out="${1}-a ${1}-b ${1}-c ${1}-f"
  fi
  printf '%s' "$out"
}

# The zones of a region that this project can use, minus $2.
usable_zones_in() {  # $1 = region, $2 = zone to avoid
  local region="$1" avoid="$2" z found=""
  for z in $(region_zones "$region"); do
    [ "$z" = "$avoid" ] && continue
    if zone_usable "$z"; then
      found="$found $z"
    fi
  done
  printf '%s' "${found# }"
}

# The zones of a region, minus $2 - whether this project can use them or not.
all_zones_in() {  # $1 = region, $2 = zone to avoid
  local region="$1" avoid="$2" z found=""
  for z in $(region_zones "$region"); do
    [ "$z" = "$avoid" ] && continue
    found="$found $z"
  done
  printf '%s' "${found# }"
}

# Ask for a zone. A value that is already good is taken as it is. The
# candidates of the region are listed, so the answer is never a guess.
# Sets REPLY.
acquire_zone() {  # $1 = label, $2 = current value, $3 = region ("" = any), $4 = zone to avoid
  local label="$1" current="$2" want_region="$3" avoid="$4"
  local ans note="" zr tries=0 default="$2" cands=""

  if [ -n "$want_region" ]; then
    cands="$(usable_zones_in "$want_region" "$avoid")"
    if [ -z "$cands" ]; then
      cands="$(all_zones_in "$want_region" "$avoid")"
    fi
    default="${cands%% *}"
    [ -z "$default" ] && default="$current"
  fi

  if [ -n "$current" ]; then
    if ! zone_usable "$current"; then
      warn "this project cannot use the zone $current"
    elif [ -n "$want_region" ] && [ "${current%-*}" != "$want_region" ]; then
      warn "the zone $current is in ${current%-*}, but the lab puts this VM in $want_region"
    elif [ -n "$avoid" ] && [ "$current" = "$avoid" ]; then
      warn "the lab wants a zone different from $avoid for this VM"
    else
      REPLY="$current"
      return 0
    fi
  fi

  while :; do
    if [ -n "$note" ]; then
      warn "$note"
    fi
    if [ -n "$cands" ]; then
      dim "  the zones of $want_region: $cands"
    fi
    printf "  %s%s%s [%s]: " "$C_BOLD" "$label" "$C_RESET" "$default"
    if ! read -r ans; then
      echo ""
      ans=""
    fi
    ans="${ans:-$default}"
    tries=$((tries + 1))
    if [ "$tries" -gt 6 ]; then
      err "too many rejected zones - giving up"
      exit 2
    fi
    if ! zone_usable "$ans"; then
      warn "this project cannot use the zone $ans - trying it anyway"
    fi
    zr="${ans%-*}"
    if [ -n "$want_region" ] && [ "$zr" != "$want_region" ]; then
      warn "the zone $ans is in $zr, but the lab puts this VM in $want_region"
    fi
    if [ -n "$avoid" ] && [ "$ans" = "$avoid" ]; then
      warn "the lab wants a zone different from $avoid for this VM"
    fi
    REPLY="$ans"
    return 0
  done
}

# ---------------------------------------------------------------------------
# the names of the lab's resources
# ---------------------------------------------------------------------------
NETWORK="default"
FW_RULE="fw-allow-health-checks"
HEALTH_TAG="allow-health-checks"
HC_RANGES="130.211.0.0/22,35.191.0.0/16"

NAT_ROUTER="nat-router-us1"
NAT_GW="nat-config"

WEBSERVER="webserver"
IMAGE="mywebserver"
IMAGE_FAMILY="webserver-family"
MACHINE_TYPE="e2-micro"

TEMPLATE="mywebserver-template"
HEALTH_CHECK="http-health-check"
MIG1="us-1-mig"
MIG2="notus-1-mig"

BACKEND="http-backend"
URL_MAP="http-lb"
PROXY="http-lb-proxy"
FW_IPV4="http-lb-ipv4"
FW_IPV6="http-lb-ipv6"

STRESS_VM="stress-test"

# ---------------------------------------------------------------------------
# the lab's regions and zones
# ---------------------------------------------------------------------------
GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

# The lab fixes the first region, the first zone and the second region:
# the Cloud NAT, the web server VM and the us-1-mig group live in us-east4
# (zone us-east4-c), the notus-1-mig group in asia-south1. Only the stress
# test VM is left to the student - it has to go in a region that is
# different but closer to us-east4 than to asia-south1.
REGION1="${REGION1_OVERRIDE:-${REGION_1:-${REGION:-us-east4}}}"
REGION2="${REGION2_OVERRIDE:-${REGION_2:-${REGION_NOTUS:-asia-south1}}}"
ZONE1="${ZONE1_OVERRIDE:-${ZONE:-${ZONE_1:-us-east4-c}}}"
STRESS_REGION="${STRESS_REGION_OVERRIDE:-${STRESS_REGION_ENV:-us-east1}}"
STRESS_ZONE="${STRESS_ZONE_OVERRIDE:-${STRESS_ZONE_ENV:-}}"

if [ -n "$ZONE1" ] || [ -n "$STRESS_ZONE" ]; then
  info "the lab's zones came from the environment: zone1=$ZONE1 stress=$STRESS_ZONE"
fi

echo ""
warn "the lab assigns the regions and the zones per lab run"
dim "  they are on the lab setup panel - copy them from there"
dim "  the lab uses $REGION1 (zone $ZONE1) and $REGION2"
echo ""

acquire_region "Region 1 - the NAT and the $MIG1 group" "$REGION1" "$REGION2"
REGION1="$REPLY"
acquire_region "Region 2 - the $MIG2 group (a different region)" "$REGION2" "$REGION1"
REGION2="$REPLY"

acquire_zone "Zone 1 - the $WEBSERVER VM (in REGION 1 = $REGION1)" \
             "${ZONE1:-}" "$REGION1" ""
ZONE1="$REPLY"

acquire_zone "Zone for the stress test VM (in $STRESS_REGION)" \
             "${STRESS_ZONE:-}" "$STRESS_REGION" ""
STRESS_ZONE="$REPLY"
STRESS_REGION="${STRESS_ZONE%-*}"
if [ "$STRESS_REGION" = "$REGION1" ]; then
  warn "the stress test VM is in the same region as $MIG1 - the lab puts it"
  warn "somewhere else, so the load balancer has to spread the traffic"
fi
echo ""

printf "%s%s  Configure an Application Load Balancer with Autoscaling%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sREGION 1=%s  %sREGION 2=%s  %sstress=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION1" "$C_DIM" "$REGION2" "$C_DIM" "$STRESS_ZONE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
network_exists()   { gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()      { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists()  { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
image_exists()     { gcloud compute images describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
disk_exists()      { gcloud compute disks describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
template_exists()  { gcloud compute instance-templates describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
hcheck_exists()    { gcloud compute health-checks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
mig_exists()       { gcloud compute instance-groups managed describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
backend_exists()   { gcloud compute backend-services describe "$1" --global --project "$PROJECT_ID" >/dev/null 2>&1; }
urlmap_exists()    { gcloud compute url-maps describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
proxy_exists()     { gcloud compute target-http-proxies describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
fwd_exists()       { gcloud compute forwarding-rules describe "$1" --global --project "$PROJECT_ID" >/dev/null 2>&1; }
router_exists()    { gcloud compute routers describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
nat_exists()       { gcloud compute routers nats describe "$1" --router="$2" --region "$3" --project "$PROJECT_ID" >/dev/null 2>&1; }

# Run a command and show its output as it arrives. Creating an image, an
# instance group or a load balancer blocks for minutes, and a silent wait
# looks exactly like a hang.
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

# Run a gcloud command, keep its output and show it when it fails. The
# error is the whole point - "could not turn on autohealing" without the
# reason is useless.
run_capture() {  # $1 = log file, rest = command
  local log="$1"; shift
  local rc=0
  "$@" > "$log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  dim "  the command that failed:"
  tail -6 "$log" 2>/dev/null | sed 's/^/    /'
  return $rc
}

pause_for_check() {  # $1 = task number, $2 = checkpoint name, $3 = extra note
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  if [ -n "${3:-}" ]; then
    printf "  %s    %s%s\n" "$C_DIM" "$3" "$C_RESET"
  fi
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
  warn "not in Cloud Shell - the regions and zones may be wrong, use --region1/--region2/--zone1..."
fi

info "enabling the Compute Engine API"
gcloud services enable compute.googleapis.com --quiet >/dev/null 2>&1
ok "the Compute Engine API is enabled"

# The lab puts everything on the default network. It exists in a fresh
# project, but some labs remove it.
if network_exists "$NETWORK"; then
  ok "the network $NETWORK exists"
else
  warn "the network $NETWORK does not exist - creating it in auto mode"
  if gcloud compute networks create "$NETWORK" --subnet-mode=auto \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "created the network $NETWORK"
  else
    note_fail "could not create the network $NETWORK"
  fi
fi

# ---------------------------------------------------------------------------
# Task 1 - the health check firewall rule
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Configure a health check firewall rule"

  if rule_exists "$FW_RULE"; then
    ok "the firewall rule $FW_RULE already exists"
  else
    info "creating the firewall rule $FW_RULE"
    if gcloud compute firewall-rules create "$FW_RULE" \
         --network="$NETWORK" --direction=INGRESS --action=ALLOW \
         --rules=tcp:80 --source-ranges="$HC_RANGES" \
         --target-tags="$HEALTH_TAG" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the firewall rule $FW_RULE"
    else
      note_fail "could not create the firewall rule $FW_RULE"
    fi
  fi
  dim "    the health checkers and the load balancer come from $HC_RANGES"
  dim "    the rule only applies to the instances with the tag $HEALTH_TAG"

  pause_for_check 1 "Create a health check firewall rule"
}

# ---------------------------------------------------------------------------
# Task 2 - the NAT configuration
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create a NAT configuration using Cloud Router"

  if router_exists "$NAT_ROUTER" "$REGION1"; then
    ok "the Cloud Router $NAT_ROUTER already exists in $REGION1"
  else
    info "creating the Cloud Router $NAT_ROUTER in $REGION1"
    if run_live "$WORKDIR/router.log" gcloud compute routers create "$NAT_ROUTER" \
         --network="$NETWORK" --region="$REGION1" \
         --project "$PROJECT_ID" --quiet; then
      ok "created the Cloud Router $NAT_ROUTER"
    else
      note_fail "could not create the Cloud Router $NAT_ROUTER"
      dim "  the log is in $WORKDIR/router.log"
    fi
  fi

  if nat_exists "$NAT_GW" "$NAT_ROUTER" "$REGION1"; then
    ok "the Cloud NAT $NAT_GW already exists on $NAT_ROUTER"
  else
    info "creating the Cloud NAT $NAT_GW on $NAT_ROUTER"
    if run_live "$WORKDIR/nat.log" gcloud compute routers nats create "$NAT_GW" \
         --router="$NAT_ROUTER" --region="$REGION1" \
         --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips \
         --project "$PROJECT_ID" --quiet; then
      ok "created the Cloud NAT $NAT_GW"
    else
      note_fail "could not create the Cloud NAT $NAT_GW"
      dim "  the log is in $WORKDIR/nat.log"
    fi
  fi

  info "waiting for the Cloud NAT to be RUNNING"
  local i status=""
  for i in $(seq 1 24); do
    status="$(gcloud compute routers nats describe "$NAT_GW" --router="$NAT_ROUTER" \
                --region="$REGION1" --project "$PROJECT_ID" \
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

  dim "    the web server VM of task 3 has no external IP and needs this"
  dim "    to reach the package mirrors"

  pause_for_check 2 "Create a NAT configuration using Cloud Router"
}

# ---------------------------------------------------------------------------
# Task 3 - the custom image with a web server
# ---------------------------------------------------------------------------
# The VM has no external IP, so Apache is installed by a startup script that
# goes out through the Cloud NAT of task 2.
STARTUP_SCRIPT='#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
# the NAT route can take a moment to appear
for i in $(1 2 3 4 5 6 7 8 9 10 11 12); do
  if getent hosts deb.debian.org >/dev/null 2>&1; then break; fi
  sleep 5
done
apt-get update -y
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2
echo "RKSHA-STARTUP-SCRIPT-DONE apache=$(systemctl is-active apache2) enabled=$(systemctl is-enabled apache2)"'

task3() {
  step "Task 3 - Create a custom image for a web server"

  if image_exists "$IMAGE"; then
    ok "the image $IMAGE already exists"
    pause_for_check 3 "Create a custom image for a web server"
    return 0
  fi

  if ! instance_exists "$WEBSERVER" "$ZONE1"; then
    info "creating the $WEBSERVER VM in $ZONE1 (no external IP)"
    if run_live "$WORKDIR/webserver.log" gcloud compute instances create "$WEBSERVER" \
         --zone="$ZONE1" --machine-type="$MACHINE_TYPE" \
         --network-interface="network=$NETWORK,no-address" \
         --tags="$HEALTH_TAG" \
         --metadata="startup-script=$STARTUP_SCRIPT" \
         --image-family=debian-12 --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --boot-disk-device-name="$WEBSERVER" \
         --project "$PROJECT_ID" --quiet; then
      ok "created the $WEBSERVER VM in $ZONE1"
    else
      note_fail "could not create the $WEBSERVER VM"
      dim "  the log is in $WORKDIR/webserver.log"
    fi
  else
    ok "the $WEBSERVER VM already exists in $ZONE1"
  fi

  info "waiting for the startup script to install Apache (it goes out through the NAT)"
  local i done="" state=""
  for i in $(seq 1 60); do
    state="$(gcloud compute instances get-serial-port-output "$WEBSERVER" \
              --zone="$ZONE1" --project "$PROJECT_ID" 2>/dev/null \
              | grep "RKSHA-STARTUP-SCRIPT-DONE" | tail -1)"
    if [ -n "$state" ]; then
      done=1
      ok "the startup script finished: ${state#*RKSHA-STARTUP-SCRIPT-DONE }"
      break
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the startup script (${i}0s)"
    fi
    sleep 10
  done
  if [ "${done:-0}" -lt 1 ] 2>/dev/null; then
    warn "the startup script did not report back - check the serial console:"
    dim "    gcloud compute instances get-serial-port-output $WEBSERVER --zone=$ZONE1"
  fi

  info "stopping the $WEBSERVER VM so the disk can be imaged"
  if gcloud compute instances stop "$WEBSERVER" --zone="$ZONE1" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "stopped the $WEBSERVER VM"
  else
    note_fail "could not stop the $WEBSERVER VM"
  fi

  info "creating the image $IMAGE from the boot disk (a couple of minutes)"
  if run_live "$WORKDIR/image.log" gcloud compute images create "$IMAGE" \
       --source-disk="$WEBSERVER" --source-disk-zone="$ZONE1" \
       --family="$IMAGE_FAMILY" \
       --project "$PROJECT_ID" --quiet; then
    ok "created the image $IMAGE"
  else
    note_fail "could not create the image $IMAGE"
    dim "  the log is in $WORKDIR/image.log"
  fi

  info "deleting the $WEBSERVER VM, the image takes its place"
  gcloud compute instances delete "$WEBSERVER" --zone="$ZONE1" \
    --keep-disks=boot --project "$PROJECT_ID" --quiet >/dev/null 2>&1
  ok "deleted the $WEBSERVER VM (the boot disk $WEBSERVER is kept)"

  pause_for_check 3 "Create a custom image for a web server"
}

# ---------------------------------------------------------------------------
# Task 4 - the instance template, the health check and the two groups
# ---------------------------------------------------------------------------
ensure_mig() {  # $1 = name, $2 = region
  local n="$1" region="$2"
  if mig_exists "$n" "$region"; then
    ok "the instance group $n already exists in $region"
  else
    info "creating the instance group $n in $region (a couple of minutes)"
    if run_live "$WORKDIR/mig-$n.log" gcloud compute instance-groups managed create "$n" \
         --template="$TEMPLATE" --region="$region" --size=1 \
         --base-instance-name="$n" \
         --health-check="$HEALTH_CHECK" --initial-delay=60 \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance group $n"
    elif run_live "$WORKDIR/mig-$n.log" gcloud compute instance-groups managed create "$n" \
         --template="$TEMPLATE" --region="$region" --size=1 \
         --base-instance-name="$n" \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance group $n (without the health check on the group)"
    else
      note_fail "could not create the instance group $n"
      dim "  the log is in $WORKDIR/mig-$n.log"
      return 0
    fi
  fi

  # The backend service refers to the port by name, so the group needs it.
  if gcloud compute instance-groups managed set-named-ports "$n" --region="$region" \
       --named-ports=http:80 --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the named port http:80 is set on $n"
  else
    warn "could not set the named port http:80 on $n - the backend may stay unhealthy"
  fi

  info "turning on autoscaling for $n"
  if run_capture "$WORKDIR/autoscaling-$n.log" \
       gcloud compute instance-groups managed set-autoscaling "$n" --region="$region" \
       --min-num-replicas=1 --max-num-replicas=2 \
       --target-load-balancing-utilization=0.8 --cool-down-period=60 \
       --project "$PROJECT_ID" --quiet; then
    ok "autoscaling on $n: 1 to 2 instances, target 80% load balancing utilization"
  else
    note_fail "could not turn on autoscaling for $n"
  fi

  info "turning on autohealing for $n"
  if run_capture "$WORKDIR/autohealing-$n.log" \
       gcloud compute instance-groups managed set-autohealing "$n" --region="$region" \
       --health-check="$HEALTH_CHECK" --initial-delay=60 \
       --project "$PROJECT_ID" --quiet; then
    ok "autohealing on $n with the health check $HEALTH_CHECK"
  elif [ "$HC_REPLACED" = "0" ]; then
    # The health check in the project is probably the newer kind, and the
    # autohealing only takes a legacy one. Replace it and try again.
    HC_REPLACED=1
    warn "the health check $HEALTH_CHECK is not accepted by the autohealing - replacing it"
    gcloud compute health-checks describe "$HEALTH_CHECK" --project "$PROJECT_ID" \
      --format="yaml(type,checkIntervalSec,port)" 2>/dev/null | sed 's/^/    /'
    gcloud compute health-checks delete "$HEALTH_CHECK" \
      --project "$PROJECT_ID" --quiet >/dev/null 2>&1
    if run_capture "$WORKDIR/healthcheck.log" gcloud compute health-checks create http "$HEALTH_CHECK" \
         --port=80 --project "$PROJECT_ID" --quiet; then
      ok "recreated the health check $HEALTH_CHECK in the legacy form"
      if run_capture "$WORKDIR/autohealing-$n.log" \
           gcloud compute instance-groups managed set-autohealing "$n" --region="$region" \
           --health-check="$HEALTH_CHECK" --initial-delay=60 \
           --project "$PROJECT_ID" --quiet; then
        ok "autohealing on $n with the health check $HEALTH_CHECK"
      else
        warn "could not turn on autohealing for $n"
        dim "  the log is in $WORKDIR/autohealing-$n.log"
      fi
    else
      warn "could not recreate the health check $HEALTH_CHECK"
    fi
  else
    # A missing autohealing does not stop the lab - the load balancer only
    # needs the group and the backend service.
    warn "could not turn on autohealing for $n"
    dim "  the log is in $WORKDIR/autohealing-$n.log"
  fi
  return 0
}

wait_for_mig() {  # $1 = name, $2 = region
  local n="$1" region="$2" i stable=""
  for i in $(seq 1 40); do
    stable="$(gcloud compute instance-groups managed describe "$n" --region="$region" \
                --project "$PROJECT_ID" --format="value(status.isStable)" 2>/dev/null)"
    if [ "$stable" = "True" ]; then
      ok "the instance group $n is stable"
      return 0
    fi
    if [ $((i % 3)) -eq 0 ]; then
      info "waiting for the instance group $n (${i}0s)"
    fi
    sleep 5
  done
  warn "the instance group $n is not stable yet"
  return 1
}

task4() {
  step "Task 4 - Configure an instance template and create instance groups"

  if ! hcheck_exists "$HEALTH_CHECK"; then
    info "creating the health check $HEALTH_CHECK (HTTP, port 80)"
    # The lab uses HTTP, not TCP. The legacy HTTP health check is the one
    # that the autohealing of a regional instance group accepts, so it is
    # created without --global.
    if run_capture "$WORKDIR/healthcheck.log" gcloud compute health-checks create http "$HEALTH_CHECK" \
         --port=80 --project "$PROJECT_ID" --quiet; then
      ok "created the health check $HEALTH_CHECK"
    else
      note_fail "could not create the health check $HEALTH_CHECK"
    fi
  else
    ok "the health check $HEALTH_CHECK already exists"
  fi

  if ! template_exists "$TEMPLATE"; then
    info "creating the instance template $TEMPLATE"
    # No subnet in the template: it is a global resource and both instance
    # groups use it, one in each region, so the VM has to pick up the
    # default subnet of its own region.
    if run_live "$WORKDIR/template.log" gcloud compute instance-templates create "$TEMPLATE" \
         --machine-type="$MACHINE_TYPE" \
         --network-interface="network=$NETWORK,no-address" \
         --tags="$HEALTH_TAG" \
         --image="$IMAGE" \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --boot-disk-device-name="$TEMPLATE" \
         --project "$PROJECT_ID" --quiet; then
      ok "created the instance template $TEMPLATE"
    else
      note_fail "could not create the instance template $TEMPLATE"
      dim "  the log is in $WORKDIR/template.log"
    fi
  else
    ok "the instance template $TEMPLATE already exists"
  fi

  ensure_mig "$MIG1" "$REGION1"
  ensure_mig "$MIG2" "$REGION2"

  wait_for_mig "$MIG1" "$REGION1"
  wait_for_mig "$MIG2" "$REGION2"

  pause_for_check 4 "Create an instance template and create instance groups"
}

# ---------------------------------------------------------------------------
# Task 5 - the Application Load Balancer
# ---------------------------------------------------------------------------
add_backend() {  # $1 = backend service, $2 = mig, $3 = region, $4 = mode, $5 = value
  local bs="$1" mig="$2" region="$3" mode="$4" value="$5" extra=""
  case "$mode" in
    RATE)        extra="--balancing-mode=RATE --max-rate-per-instance=$value" ;;
    UTILIZATION) extra="--balancing-mode=UTILIZATION --max-utilization=$value" ;;
  esac
  if gcloud compute backend-services describe "$bs" --global --project "$PROJECT_ID" \
       --format="value(backends[].group)" 2>/dev/null | grep -q "$mig"; then
    ok "the backend $mig is already attached to $bs"
    return 0
  fi
  info "attaching the $mig ($mode) to the backend service $bs"
  # shellcheck disable=SC2086
  if run_capture "$WORKDIR/backend-$mig.log" gcloud compute backend-services add-backend "$bs" \
       --instance-group="$mig" --instance-group-region="$region" \
       $extra --capacity-scaler=1.0 \
       --global --project "$PROJECT_ID" --quiet; then
    ok "attached the $mig to $bs"
  else
    note_fail "could not attach the $mig to $bs"
    warn "  the instance group $mig has to exist in $region - run task 4 again"
  fi
  return 0
}

lb_ip() {  # $1 = forwarding rule
  gcloud compute forwarding-rules describe "$1" --global --project "$PROJECT_ID" \
    --format="value(IPAddress)" 2>/dev/null
}

task5() {
  step "Task 5 - Configure the Application Load Balancer (HTTP)"

  if ! backend_exists "$BACKEND"; then
    info "creating the backend service $BACKEND"
    if gcloud compute backend-services create "$BACKEND" \
         --global --protocol=HTTP --port-name=http \
         --health-checks="$HEALTH_CHECK" --global-health-checks \
         --enable-logging --logging-sample-rate=1.0 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the backend service $BACKEND"
    else
      note_fail "could not create the backend service $BACKEND"
    fi
  else
    ok "the backend service $BACKEND already exists"
  fi

  # The health check may have been replaced in task 4, so point the backend
  # service at the one that is in the project now.
  if gcloud compute backend-services update "$BACKEND" --global \
       --health-checks="$HEALTH_CHECK" --global-health-checks \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the backend service uses the health check $HEALTH_CHECK"
  fi

  # The first group is rate based, the second one is utilization based.
  add_backend "$BACKEND" "$MIG1" "$REGION1" RATE 50
  add_backend "$BACKEND" "$MIG2" "$REGION2" UTILIZATION 0.8

  if ! urlmap_exists "$URL_MAP"; then
    info "creating the URL map $URL_MAP"
    if gcloud compute url-maps create "$URL_MAP" --default-service="$BACKEND" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the URL map $URL_MAP"
    else
      note_fail "could not create the URL map $URL_MAP"
    fi
  else
    ok "the URL map $URL_MAP already exists"
  fi

  if ! proxy_exists "$PROXY"; then
    info "creating the target HTTP proxy $PROXY"
    if gcloud compute target-http-proxies create "$PROXY" --url-map="$URL_MAP" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the target HTTP proxy $PROXY"
    else
      note_fail "could not create the target HTTP proxy $PROXY"
    fi
  else
    ok "the target HTTP proxy $PROXY already exists"
  fi

  if ! fwd_exists "$FW_IPV4"; then
    info "creating the IPv4 forwarding rule $FW_IPV4"
    if gcloud compute forwarding-rules create "$FW_IPV4" --global \
         --target-http-proxy="$PROXY" --ports=80 --ip-version=IPV4 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the IPv4 forwarding rule $FW_IPV4"
    else
      note_fail "could not create the IPv4 forwarding rule $FW_IPV4"
    fi
  else
    ok "the IPv4 forwarding rule $FW_IPV4 already exists"
  fi

  if ! fwd_exists "$FW_IPV6"; then
    info "creating the IPv6 forwarding rule $FW_IPV6"
    if gcloud compute forwarding-rules create "$FW_IPV6" --global \
         --target-http-proxy="$PROXY" --ports=80 --ip-version=IPV6 \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the IPv6 forwarding rule $FW_IPV6"
    else
      note_fail "could not create the IPv6 forwarding rule $FW_IPV6"
    fi
  else
    ok "the IPv6 forwarding rule $FW_IPV6 already exists"
  fi

  local ip4 ip6
  ip4="$(lb_ip "$FW_IPV4")"
  ip6="$(lb_ip "$FW_IPV6")"
  dim "    IPv4: $ip4"
  dim "    IPv6: $ip6"

  if [ "$DO_VERIFY" = "1" ] && [ -n "$ip4" ]; then
    info "waiting for the load balancer to answer (a few minutes)"
    local i body=""
    for i in $(seq 1 40); do
      body="$(curl -s -m 10 "http://$ip4/" 2>/dev/null)"
      if printf '%s' "$body" | grep -qi "apache\|html"; then
        ok "the load balancer answers on http://$ip4/"
        break
      fi
      if [ $((i % 3)) -eq 0 ]; then
        info "waiting for the load balancer (${i}0s)"
      fi
      sleep 10
    done
    if ! printf '%s' "$body" | grep -qi "apache\|html"; then
      warn "the load balancer did not answer yet - it can take a few minutes"
      dim "    try: curl http://$ip4/"
    fi
  fi

  pause_for_check 5 "Configure an Application Load Balancer (HTTP) with IPv4 and IPv6"
}

# ---------------------------------------------------------------------------
# Task 6 - the stress test
# ---------------------------------------------------------------------------
task6() {
  step "Task 6 - Stress test the Application Load Balancer (HTTP)"

  if [ "$DO_VERIFY" != "1" ]; then
    dim "  --no-verify was given, skipping the stress test"
    pause_for_check 6 "Stress test an Application Load Balancer (HTTP)"
    return 0
  fi

  local ip4
  ip4="$(lb_ip "$FW_IPV4")"
  if [ -z "$ip4" ]; then
    note_fail "the forwarding rule $FW_IPV4 has no IP yet - run task 5 first"
  fi
  ok "the load balancer is at http://$ip4/"

  if ! instance_exists "$STRESS_VM" "$STRESS_ZONE"; then
    info "creating the stress test VM $STRESS_VM in $STRESS_ZONE"
    # With an external IP: it has to reach the public load balancer.
    if run_live "$WORKDIR/stress.log" gcloud compute instances create "$STRESS_VM" \
         --zone="$STRESS_ZONE" --machine-type="$MACHINE_TYPE" \
         --network-interface="network=$NETWORK" \
         --image="$IMAGE" \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --boot-disk-device-name="$STRESS_VM" \
         --project "$PROJECT_ID" --quiet; then
      ok "created the stress test VM $STRESS_VM"
    else
      note_fail "could not create the stress test VM $STRESS_VM"
      dim "  the log is in $WORKDIR/stress.log"
    fi
  else
    ok "the stress test VM $STRESS_VM already exists in $STRESS_ZONE"
  fi

  info "waiting for the stress test VM to start"
  local i status=""
  for i in $(seq 1 40); do
    status="$(gcloud compute instances describe "$STRESS_VM" --zone="$STRESS_ZONE" \
                --project "$PROJECT_ID" --format="value(status)" 2>/dev/null)"
    if [ "$status" = "RUNNING" ]; then
      ok "the stress test VM is RUNNING"
      break
    fi
    if [ $((i % 4)) -eq 0 ]; then
      info "waiting for the stress test VM (${i}0s)"
    fi
    sleep 5
  done
  if [ "$status" != "RUNNING" ]; then
    warn "the stress test VM is '${status:-unknown}', not RUNNING yet"
  fi

  info "installing ApacheBench on the stress test VM"
  if gcloud compute ssh "$STRESS_VM" --zone="$STRESS_ZONE" --project "$PROJECT_ID" \
       --quiet --command="sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq apache2-utils >/dev/null 2>&1; which ab" 2>&1 \
       | sed 's/^/    /'; then
    ok "ApacheBench is installed"
  else
    warn "could not install ApacheBench on the stress test VM"
  fi

  info "a short run first, to prove the load balancer is serving"
  gcloud compute ssh "$STRESS_VM" --zone="$STRESS_ZONE" --project "$PROJECT_ID" \
    --quiet --command="ab -n 2000 -c 50 http://$ip4/ 2>&1 | grep -E 'Complete requests|Requests per second|Failed requests'" \
    2>&1 | sed 's/^/    /'

  info "starting the real stress test in the background"
  gcloud compute ssh "$STRESS_VM" --zone="$STRESS_ZONE" --project "$PROJECT_ID" \
    --quiet --command="nohup ab -n 500000 -c 1000 http://$ip4/ > /tmp/ab.log 2>&1 &" \
    >/dev/null 2>&1
  ok "the stress test is running on the VM - the log is /tmp/ab.log there"

  info "waiting for the instance groups to scale up"
  local j size1 size2
  for j in $(seq 1 24); do
    size1="$(gcloud compute instance-groups managed describe "$MIG1" --region="$REGION1" \
                --project "$PROJECT_ID" --format="value(targetSize)" 2>/dev/null)"
    size2="$(gcloud compute instance-groups managed describe "$MIG2" --region="$REGION2" \
                --project "$PROJECT_ID" --format="value(targetSize)" 2>/dev/null)"
    if [ "${size1:-0}" -ge 2 ] 2>/dev/null || [ "${size2:-0}" -ge 2 ] 2>/dev/null; then
      ok "$MIG1 has $size1 instances, $MIG2 has $size2 - the autoscaler is working"
      break
    fi
    if [ $((j % 3)) -eq 0 ]; then
      info "waiting for the autoscaler ($MIG1: $size1, $MIG2: $size2)"
    fi
    sleep 10
  done

  echo ""
  info "watch it in the console:"
  dim "    Load balancing  >  $URL_MAP  >  Monitoring"
  dim "    Compute Engine >  Instance groups >  $MIG1  >  Monitoring"
  dim "    the stress test log: gcloud compute ssh $STRESS_VM --zone=$STRESS_ZONE --command='cat /tmp/ab.log'"

  pause_for_check 6 "Stress test an Application Load Balancer (HTTP)"
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
  "")
    task1
    task2
    task3
    task4
    task5
    task6
    ;;
  *)
    err "--task must be between 1 and 6"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  REGION 1         : $REGION1   (the NAT and $MIG1)"
echo "  REGION 2         : $REGION2   ($MIG2)"
echo "  Zones            : $ZONE1 (the $WEBSERVER VM), $STRESS_ZONE (the $STRESS_VM)"
echo "  Network          : $NETWORK"
echo "  Firewall rule    : $FW_RULE (tag $HEALTH_TAG, from $HC_RANGES)"
echo "  Cloud NAT        : $NAT_GW on the router $NAT_ROUTER in $REGION1"
echo "  Image            : $IMAGE (family $IMAGE_FAMILY)"
echo "  Template         : $TEMPLATE"
echo "  Health check     : $HEALTH_CHECK (TCP port 80)"
echo "  Instance groups  : $MIG1 in $REGION1, $MIG2 in $REGION2 (1 to 2 instances)"
echo "  Backend service  : $BACKEND"
echo "  URL map / proxy  : $URL_MAP, $PROXY"
echo "  Forwarding rules : $FW_IPV4 (IPv4), $FW_IPV6 (IPv6)"
echo ""
echo "  Checkpoints:"
echo "    1. Create a health check firewall rule"
echo "    2. Create a NAT configuration using Cloud Router"
echo "    3. Create a custom image for a web server"
echo "    4. Create an instance template and create instance groups"
echo "    5. Configure an Application Load Balancer (HTTP) with IPv4 and IPv6"
echo "    6. Stress test an Application Load Balancer (HTTP)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute instances delete $STRESS_VM --zone=$STRESS_ZONE --quiet"
echo "    gcloud compute forwarding-rules delete $FW_IPV4 $FW_IPV6 --global --quiet"
echo "    gcloud compute target-http-proxies delete $PROXY --quiet"
echo "    gcloud compute url-maps delete $URL_MAP --quiet"
echo "    gcloud compute backend-services delete $BACKEND --global --quiet"
echo "    gcloud compute instance-groups managed delete $MIG1 --region=$REGION1 --quiet"
echo "    gcloud compute instance-groups managed delete $MIG2 --region=$REGION2 --quiet"
echo "    gcloud compute instance-templates delete $TEMPLATE --quiet"
echo "    gcloud compute health-checks delete $HEALTH_CHECK --quiet"
echo "    gcloud compute images delete $IMAGE --quiet"
echo "    gcloud compute disks delete $WEBSERVER --zone=$ZONE1 --quiet"
echo "    gcloud compute routers nats delete $NAT_GW --router=$NAT_ROUTER --region=$REGION1 --quiet"
echo "    gcloud compute routers delete $NAT_ROUTER --region=$REGION1 --quiet"
echo "    gcloud compute firewall-rules delete $FW_RULE --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
