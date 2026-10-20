#!/usr/bin/env bash
# =============================================================================
#  "Implement Private Google Access and Cloud NAT"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 45795).
#
#  Creates a VPC and a VM instance with no external IP address, reaches it
#  through an IAP tunnel, enables Private Google Access on the subnet, and
#  adds a Cloud NAT gateway so the instance can reach the internet.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_pga_nat.sh
#     chmod +x gsp_pga_nat.sh
#     ./gsp_pga_nat.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       the lab's zone (asked for)
#     --region REGION   region (default: derived from the zone)
#     --network NAME    the VPC network (default: privatenet)
#     --subnet NAME     the subnet (default: privatenet-us)
#     --vm NAME         the instance (default: vm-internal)
#     --bucket NAME     the Cloud Storage bucket (default: the project ID)
#     --machine-type T  e2-standard-2
#     --image IMAGE     boot disk image family (default: from the project)
#     --task N          run only task N (1-4)
#     --yes             do not pause for the checkpoints
#     --no-verify       skip the connectivity tests
#     -h, --help        this help
#
#  CHECKPOINTS (100 points):
#     1. Create the VM instance                                        (30)
#     2. Create a Cloud Storage bucket and Enable Private Google Access (40)
#     3. Configure a Cloud NAT gateway                                 (30)
#
#  NOTES:
#   * The zone is injected by the lab per run, so the script asks for it.
#   * The connectivity tests are informational only - they never fail the
#     run, because they need an IAP tunnel and the student account's
#     permissions.
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
NETWORK_OVERRIDE=""
SUBNET_OVERRIDE=""
VM_OVERRIDE=""
BUCKET_OVERRIDE=""
MACHINE_TYPE_OVERRIDE=""
IMAGE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
DO_VERIFY=1

usage() {
  cat <<'USAGE_END'
Implement Private Google Access and Cloud NAT

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_pga_nat.sh
   chmod +x gsp_pga_nat.sh
   ./gsp_pga_nat.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       the lab's zone (asked for)
   --region REGION   region (default: derived from the zone)
   --network NAME    the VPC network (default: privatenet)
   --subnet NAME     the subnet (default: privatenet-us)
   --vm NAME         the instance (default: vm-internal)
   --bucket NAME     the Cloud Storage bucket (default: the project ID)
   --machine-type T  e2-standard-2
   --image IMAGE     boot disk image family (default: from the project)
   --task N          run only task N (1-4)
   --yes             do not pause for the checkpoints
   --no-verify       skip the connectivity tests
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2";      shift 2 ;;
    --zone)         ZONE_OVERRIDE="$2";         shift 2 ;;
    --region)       REGION_OVERRIDE="$2";       shift 2 ;;
    --network)      NETWORK_OVERRIDE="$2";      shift 2 ;;
    --subnet)       SUBNET_OVERRIDE="$2";       shift 2 ;;
    --vm)           VM_OVERRIDE="$2";           shift 2 ;;
    --bucket)       BUCKET_OVERRIDE="$2";       shift 2 ;;
    --machine-type) MACHINE_TYPE_OVERRIDE="$2"; shift 2 ;;
    --image)        IMAGE_OVERRIDE="$2";        shift 2 ;;
    --task)         ONLY_TASK="$2";             shift 2 ;;
    --yes)          ASSUME_YES=1;               shift ;;
    --no-verify)    DO_VERIFY=0;                shift ;;
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
# the lab's zone
# ---------------------------------------------------------------------------
detect_zone_from_metadata() {
  local meta
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  [ -z "$meta" ] && return 1
  printf '%s' "$meta" | grep -oE '\b[a-z]+-[a-z]+[0-9]-[a-z]\b' | head -1
}

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""

if [ -z "$ZONE_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  META_ZONE="$(detect_zone_from_metadata || true)"
  echo ""
  warn "the lab assigns the zone per lab run - it cannot be read from the project"
  dim "  it is on your lab setup panel (Zone)."
  if [ -n "$META_ZONE" ]; then
    dim "  the project metadata mentions: $META_ZONE"
  fi
  printf "  %sZone%s  [%s]: " "$C_BOLD" "$C_RESET" "${META_ZONE:-${GCP_ZONE:-us-central1-a}}"
  read -r ans
  ZONE_OVERRIDE="${ans:-${META_ZONE:-${GCP_ZONE:-us-central1-a}}}"
  echo ""
fi

ZONE="${ZONE_OVERRIDE:-${GCP_ZONE:-us-central1-a}}"
REGION="${REGION_OVERRIDE:-${ZONE%-*}}"

# ---------------------------------------------------------------------------
# the boot disk image
# ---------------------------------------------------------------------------
resolve_image() {
  if [ -n "$IMAGE_OVERRIDE" ]; then echo "$IMAGE_OVERRIDE"; return 0; fi
  local meta found
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  if [ -n "$meta" ]; then
    found="$(printf '%s' "$meta" | grep -oE 'debian-[0-9]+(-[a-z]+)?' | head -1)"
    if [ -n "$found" ]; then echo "$found"; return 0; fi
  fi
  echo "debian-12"
}
IMAGE="$(resolve_image)"

# ---------------------------------------------------------------------------
# names
# ---------------------------------------------------------------------------
NETWORK="${NETWORK_OVERRIDE:-privatenet}"
SUBNET="${SUBNET_OVERRIDE:-privatenet-us}"
VM="${VM_OVERRIDE:-vm-internal}"
BUCKET="${BUCKET_OVERRIDE:-$PROJECT_ID}"
MACHINE_TYPE="${MACHINE_TYPE_OVERRIDE:-e2-standard-2}"
ROUTER="nat-router"
NATGATEWAY="nat-config"
SUBNET_RANGE="10.130.0.0/20"
IAP_RANGE="35.235.240.0/20"
TEST_OBJECT="gs://cloud-training/gcpnet/private/access.svg"

printf "%s%s  Implement Private Google Access and Cloud NAT%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %sregion=%s  %snetwork=%s  %ssubnet=%s  %svm=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$REGION" "$C_DIM" "$NETWORK" \
  "$C_DIM" "$SUBNET" "$C_DIM" "$VM" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
network_exists()   { gcloud compute networks describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
subnet_exists()    { gcloud compute networks subnets describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
rule_exists()      { gcloud compute firewall-rules describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists()  { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
router_exists()    { gcloud compute routers describe "$1" --region "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }
nat_exists()       { gcloud compute routers nats describe "$1" --router="$2" --region "$3" --project "$PROJECT_ID" >/dev/null 2>&1; }
bucket_exists()    { gcloud storage buckets describe "gs://$1" --project "$PROJECT_ID" >/dev/null 2>&1; }

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

# Run a command inside the instance over an IAP tunnel. Informational only.
vm_run() {  # $1 = command
  if [ "$DO_VERIFY" != "1" ]; then return 0; fi
  gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT_ID" \
    --tunnel-through-iap --quiet --command="$1" 2>&1
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

info "enabling the Compute Engine, IAP and Storage APIs"
gcloud services enable compute.googleapis.com iap.googleapis.com storage.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

# ---------------------------------------------------------------------------
# Task 1 - the VPC, the firewall rule and the VM instance
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create the VM instance"

  if network_exists "$NETWORK"; then
    ok "the network $NETWORK already exists"
  else
    if gcloud compute networks create "$NETWORK" --subnet-mode=custom \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the network $NETWORK in custom mode"
    else
      note_fail "could not create $NETWORK"
      return 1
    fi
  fi

  if subnet_exists "$SUBNET" "$REGION"; then
    ok "the subnet $SUBNET already exists in $REGION"
  else
    if gcloud compute networks subnets create "$SUBNET" \
         --network="$NETWORK" --region="$REGION" --range="$SUBNET_RANGE" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $SUBNET in $REGION ($SUBNET_RANGE)"
    else
      note_fail "could not create $SUBNET"
      return 1
    fi
  fi

  # Private Google Access is deliberately left OFF here - the lab turns it
  # on in task 2 and checks the difference.
  PGA="$(gcloud compute networks subnets describe "$SUBNET" --region "$REGION" \
          --project "$PROJECT_ID" --format="value(privateIpGoogleAccess)" 2>/dev/null)"
  if [ "$PGA" = "True" ]; then
    warn "$SUBNET already has Private Google Access on - task 2 will be a no-op"
  else
    ok "Private Google Access is off, as the lab wants"
  fi

  info "creating the firewall rule for the IAP tunnel"
  if rule_exists "$NETWORK-allow-ssh"; then
    ok "$NETWORK-allow-ssh already exists"
  else
    if gcloud compute firewall-rules create "$NETWORK-allow-ssh" \
         --network="$NETWORK" --direction=INGRESS --priority=1000 \
         --action=ALLOW --rules="tcp:22" --source-ranges="$IAP_RANGE" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $NETWORK-allow-ssh (tcp:22 from $IAP_RANGE)"
    else
      note_fail "could not create $NETWORK-allow-ssh"
    fi
  fi

  info "creating $VM with no external IP address"
  if instance_exists "$VM" "$ZONE"; then
    ok "$VM already exists in $ZONE"
  else
    if gcloud compute instances create "$VM" \
         --zone="$ZONE" \
         --machine-type="$MACHINE_TYPE" \
         --network-interface="network=$NETWORK,subnet=$SUBNET,no-address" \
         --image-family="$IMAGE" --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created $VM in $ZONE with no external IP"
    else
      note_fail "could not create $VM"
      return 1
    fi
  fi

  info "waiting for $VM to start"
  local i
  for i in $(seq 1 40); do
    if gcloud compute instances describe "$VM" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      ok "$VM is RUNNING"
      break
    fi
    sleep 5
  done

  EXT_IP="$(gcloud compute instances describe "$VM" --zone "$ZONE" --project "$PROJECT_ID" \
             --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"
  if [ -z "$EXT_IP" ] || [ "$EXT_IP" = "None" ]; then
    ok "$VM has no external IP, as the lab wants"
  else
    warn "$VM has an external IP ($EXT_IP) - it should not"
  fi

  pause_for_check 1 "Create the VM instance"
}

# ---------------------------------------------------------------------------
# Task 2 - the bucket and Private Google Access
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Enable Private Google Access"

  info "creating the Cloud Storage bucket"
  if bucket_exists "$BUCKET"; then
    ok "the bucket gs://$BUCKET already exists"
  else
    if gcloud storage buckets create "gs://$BUCKET" \
         --project="$PROJECT_ID" --location=US --uniform-bucket-level-access >/dev/null 2>&1; then
      ok "created gs://$BUCKET"
    elif gcloud storage buckets create "gs://$BUCKET" \
         --project="$PROJECT_ID" --location=US >/dev/null 2>&1; then
      ok "created gs://$BUCKET"
    else
      note_fail "could not create gs://$BUCKET"
      dim "  bucket names are global - try another one:"
      dim "    ./gsp_pga_nat.sh --bucket $BUCKET-$(date +%s)"
      return 1
    fi
  fi

  info "copying the test image into the bucket"
  if gcloud storage cp "$TEST_OBJECT" "gs://$BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "copied access.svg into gs://$BUCKET"
  else
    note_fail "could not copy $TEST_OBJECT into gs://$BUCKET"
    dim "  the source object has to be reachable - check your network"
  fi

  info "checking that Cloud Shell itself can read it back"
  if gcloud storage ls "gs://$BUCKET" --project="$PROJECT_ID" 2>/dev/null | grep -q "access.svg"; then
    ok "gs://$BUCKET holds access.svg"
  else
    warn "the object is not showing up in the bucket"
  fi

  info "enabling Private Google Access on $SUBNET"
  if gcloud compute networks subnets update "$SUBNET" --region "$REGION" \
       --enable-private-ip-google-access --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "Private Google Access is now on for $SUBNET"
  else
    note_fail "could not enable Private Google Access"
  fi

  pause_for_check 2 "Create a Cloud Storage bucket and Enable Private Google Access"

  if [ "$DO_VERIFY" = "1" ]; then
    info "checking that $VM can now read the object over Private Google Access"
    OUT="$(vm_run "gcloud storage cp gs://$BUCKET/access.svg . 2>&1 && echo PGA-OK || echo PGA-FAILED")"
    case "$OUT" in
      *PGA-OK*)     ok "$VM reached Google Storage through Private Google Access" ;;
      *PGA-FAILED*) warn "$VM could not reach Google Storage - it may need a moment" ;;
      *)            warn "the IAP tunnel did not answer, skipping the check" ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Task 3 - the Cloud NAT gateway
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Configure a Cloud NAT gateway"

  if router_exists "$ROUTER" "$REGION"; then
    ok "the Cloud Router $ROUTER already exists"
  else
    if gcloud compute routers create "$ROUTER" \
         --network="$NETWORK" --region="$REGION" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the Cloud Router $ROUTER"
    else
      note_fail "could not create the Cloud Router $ROUTER"
      return 1
    fi
  fi

  if nat_exists "$NATGATEWAY" "$ROUTER" "$REGION"; then
    ok "the Cloud NAT gateway $NATGATEWAY already exists"
  else
    if gcloud compute routers nats create "$NATGATEWAY" \
         --router="$ROUTER" --region="$REGION" \
         --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the Cloud NAT gateway $NATGATEWAY"
    else
      note_fail "could not create the Cloud NAT gateway $NATGATEWAY"
      dim "  run it by hand to see the error:"
      dim "    gcloud compute routers nats create $NATGATEWAY --router=$ROUTER --region=$REGION \\"
      dim "      --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges"
      return 1
    fi
  fi

  info "waiting for the NAT gateway to be ready"
  local i
  for i in $(seq 1 24); do
    STATUS="$(gcloud compute routers nats describe "$NATGATEWAY" --router="$ROUTER" \
               --region="$REGION" --project "$PROJECT_ID" \
               --format="value(status)" 2>/dev/null)"
    if [ "$STATUS" = "RUNNING" ]; then
      ok "the NAT gateway is RUNNING"
      break
    fi
    sleep 5
  done
  [ "$STATUS" != "RUNNING" ] && warn "the NAT gateway status is '${STATUS:-unknown}'"

  pause_for_check 3 "Configure a Cloud NAT gateway"

  if [ "$DO_VERIFY" = "1" ]; then
    info "checking that $VM can reach the internet through the NAT gateway"
    dim "  the NAT config can take up to 3 minutes to propagate"
    OUT="$(vm_run "sudo apt-get update -qq >/dev/null 2>&1 && echo NAT-OK || echo NAT-FAILED")"
    case "$OUT" in
      *NAT-OK*)     ok "$VM reached the internet through Cloud NAT" ;;
      *NAT-FAILED*) warn "$VM still cannot reach the internet - wait a minute and try again" ;;
      *)            warn "the IAP tunnel did not answer, skipping the check" ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Task 4 - Cloud NAT logging
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Configure and view logs with Cloud NAT Logging"

  if ! nat_exists "$NATGATEWAY" "$ROUTER" "$REGION"; then
    warn "the NAT gateway $NATGATEWAY does not exist - run task 3 first"
    return 1
  fi

  if gcloud compute routers nats update "$NATGATEWAY" --router="$ROUTER" \
       --region="$REGION" --enable-logging \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "Cloud NAT logging is on (translation and errors)"
  else
    note_fail "could not enable Cloud NAT logging"
  fi

  cat <<EOF

  ${C_DIM}The logs land in Cloud Logging. Look for them at:${C_RESET}
    ${C_CYAN}Logging > Logs Explorer${C_RESET}
    ${C_DIM}filter: resource.type="compute_router_nat" AND resource.labels.router_name="$ROUTER"${C_RESET}

EOF
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
echo "  Project      : $PROJECT_ID"
echo "  Zone / Region: $ZONE  /  $REGION"
echo "  Network      : $NETWORK  (custom mode)"
echo "  Subnet       : $SUBNET  ($SUBNET_RANGE)  Private Google Access: ON"
echo "  Firewall     : $NETWORK-allow-ssh  tcp:22 from $IAP_RANGE"
echo "  VM           : $VM  ($MACHINE_TYPE)  no external IP"
echo "  Bucket       : gs://$BUCKET"
echo "  Router       : $ROUTER"
echo "  NAT gateway  : $NATGATEWAY"
echo ""
echo "  Checkpoints:"
echo "    1. Create the VM instance                                         (30)"
echo "    2. Create a Cloud Storage bucket and Enable Private Google Access (40)"
echo "    3. Configure a Cloud NAT gateway                                  (30)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud compute instances delete $VM --zone=$ZONE --quiet"
echo "    gcloud compute routers nats delete $NATGATEWAY --router=$ROUTER --region=$REGION --quiet"
echo "    gcloud compute routers delete $ROUTER --region=$REGION --quiet"
echo "    gcloud compute networks delete $NETWORK --quiet"
echo "    gcloud storage rm -r gs://$BUCKET"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
