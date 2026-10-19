#!/usr/bin/env bash
# =============================================================================
#  GSP345 - "Build Infrastructure with Terraform on Google Cloud: Challenge Lab"
#  Google Cloud Arcade / Cloud Skills Boost challenge lab.
#
#  Seven tasks: configuration files, import existing infrastructure, a remote
#  GCS backend, modify/update, destroy, a module from the Terraform Registry,
#  and a firewall rule.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp345.sh
#     chmod +x gsp345.sh
#     ./gsp345.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       lab zone (default: taken from the pre-created instances)
#     --region REGION   lab region (default: derived from the zone)
#     --workdir PATH    where the configuration lives (default: $HOME/gsp345)
#     --bucket NAME     remote-backend bucket (default: the project ID)
#     --vpc NAME        VPC name (default: terraform-vpc)
#     --instance NAME   third instance name (default: tf-instance-3)
#     --task N          run only task N (1-7)
#     --yes             do not pause between tasks (for unattended runs)
#     --skip-install    assume terraform is already on PATH
#     -h, --help        this help
#
#  IMPORTANT:
#   The lab's checkpoints conflict with each other - task 4 creates a third
#   instance and task 5 destroys it again. The lab therefore only scores a
#   task when you click "Check my progress" for it, so this script STOPS
#   between tasks and waits for you to click that button. Progress is saved,
#   so re-running resumes where you left off.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# colors
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# defaults + argument parsing
# ---------------------------------------------------------------------------
PROJECT_OVERRIDE=""
ZONE_OVERRIDE=""
REGION_OVERRIDE=""
WORKDIR="${GSP345_WORKDIR:-$HOME/gsp345}"
BUCKET_OVERRIDE=""
VPC_NAME="terraform-vpc"
THIRD_INSTANCE="tf-instance-3"
ONLY_TASK=""
ASSUME_YES=0
SKIP_INSTALL=0
RECREATE_INSTANCES=0

usage() {
  cat <<'USAGE_END'
GSP345 - Build Infrastructure with Terraform on Google Cloud: Challenge Lab

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp345.sh
   chmod +x gsp345.sh
   ./gsp345.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       lab zone (default: taken from the pre-created instances)
   --region REGION   lab region (default: derived from the zone)
   --workdir PATH    where the configuration lives (default: $HOME/gsp345)
   --bucket NAME     remote-backend bucket (default: the project ID)
   --vpc NAME        VPC name (default: terraform-vpc)
   --instance NAME   third instance name (default: tf-instance-3)
   --task N          run only task N (1-7)
   --yes             do not pause between tasks
   --recreate-instances  recreate tf-instance-1/2 if they are missing
   --skip-install    assume terraform is already on PATH
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)         ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)       REGION_OVERRIDE="$2";   shift 2 ;;
    --workdir)      WORKDIR="$2";           shift 2 ;;
    --bucket)       BUCKET_OVERRIDE="$2";   shift 2 ;;
    --vpc)          VPC_NAME="$2";          shift 2 ;;
    --instance)     THIRD_INSTANCE="$2";    shift 2 ;;
    --task)         ONLY_TASK="$2";         shift 2 ;;
    --yes)          ASSUME_YES=1;           shift ;;
    --skip-install) SKIP_INSTALL=1;         shift ;;
    --recreate-instances) RECREATE_INSTANCES=1; shift ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve project
# ---------------------------------------------------------------------------
PROJECT_ID="$PROJECT_OVERRIDE"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
fi
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  err "No GCP project resolved. Pass --project ID or run: gcloud config set project ID"
  exit 1
fi

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
printf "%s%s  GSP345 - Build Infrastructure with Terraform on Google Cloud%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"

step "Preflight checks"

if ! command -v gcloud >/dev/null 2>&1; then
  err "gcloud not found on PATH. Run this inside Google Cloud Shell."
  exit 1
fi
ok "gcloud is available"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
ok "project: $PROJECT_ID"

# created early - the zone is recorded here so a later run can still find it
# even if the lab's instances are gone
mkdir -p "$WORKDIR" || { err "cannot create workdir $WORKDIR"; exit 1; }

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - zone/project defaults may be wrong"
fi

# --- find the lab's pre-created instances -----------------------------------
# They are the most reliable source for the lab's zone, machine type and
# boot disk image. gcloud config compute/zone is NOT - it survives Cloud
# Shell restarts and is often left over from a previous lab.
inst_field() {  # $1 = instance name, $2 = format
  gcloud compute instances describe "$1" --zone "$ZONE" --project "$PROJECT_ID" \
    --format="$2" 2>/dev/null
}

ZONE="$ZONE_OVERRIDE"
ZONE_SOURCE="the --zone flag"
ZONE_SAVED_FILE="$WORKDIR/.gsp345-zone"
if [ -z "$ZONE" ]; then
  for N in tf-instance-1 tf-instance-2; do
    Z="$(gcloud compute instances list --project "$PROJECT_ID" \
          --filter="name=$N" --format="value(zone)" 2>/dev/null \
          | head -1 | sed 's|.*/||')"
    if [ -n "$Z" ]; then ZONE="$Z"; ZONE_SOURCE="the lab's pre-created instances"; break; fi
  done
fi
if [ -z "$ZONE" ] && [ -f "$ZONE_SAVED_FILE" ]; then
  ZONE="$(cat "$ZONE_SAVED_FILE" 2>/dev/null)"
  ZONE_SOURCE="the zone recorded by an earlier run"
fi

if [ -z "$ZONE" ]; then
  err "could not find the lab's pre-created instances tf-instance-1 / tf-instance-2"
  err "start the lab first - it creates them for you - or pass --zone <zone>"
  echo ""
  dim "  if a previous run deleted them, recover with:"
  dim "    ./gsp345.sh --zone <zone> --recreate-instances"
  exit 1
fi
if [ -n "$ZONE_OVERRIDE" ]; then
  REGION="${REGION_OVERRIDE:-${ZONE_OVERRIDE%-*}}"
else
  REGION="${REGION_OVERRIDE:-${ZONE%-*}}"
fi
ok "lab zone: $ZONE   region: $REGION   (from $ZONE_SOURCE)"
echo "$ZONE" > "$ZONE_SAVED_FILE"

# Read everything the configuration has to match from the lab's own
# instances. NOTE: an instance's disks[0].source is the DISK, not the image.
# The image lives on the disk as sourceImage, so the disk has to be looked up
# separately. Getting this wrong makes Terraform plan a replacement, and
# because boot_disk.initialize_params.image is ForceNew it then DELETES the
# instance and fails to recreate it.
read_instance_facts() {
  INST1_ID="$(inst_field tf-instance-1 'value(id)')"
  INST2_ID="$(inst_field tf-instance-2 'value(id)')"

  MACHINE_TYPE="$(inst_field tf-instance-1 'value(machineType)' | sed 's|.*/||')"
  [ -z "$MACHINE_TYPE" ] && MACHINE_TYPE="${GSP345_MACHINE_TYPE:-e2-micro}"

  IMAGE=""
  DISK_URL="$(inst_field tf-instance-1 'value(disks[0].source)')"
  DISK_NAME="$(basename "$DISK_URL")"
  if [ -n "$DISK_NAME" ]; then
    IMAGE_URL="$(gcloud compute disks describe "$DISK_NAME" --zone "$ZONE" \
      --project "$PROJECT_ID" --format="value(sourceImage)" 2>/dev/null)"
    IMAGE="$(printf '%s' "$IMAGE_URL" \
      | sed -e 's|.*/projects/||' -e 's|/global/images/|/|')"
  fi
  if [ -z "$IMAGE" ]; then
    # the licence is the image family, e.g. debian-cloud/debian-12
    IMAGE="$(inst_field tf-instance-1 'value(disks[0].licenses[0])')"
  fi
  # Sanity check: never accept a disk or a zone path as an image.
  case "$IMAGE" in
    */zones/*|*/disks/*|*/instances/*|"") IMAGE="" ;;
  esac
  [ -z "$IMAGE" ] && IMAGE="debian-12"
}

read_instance_facts
ok "existing machine type: $MACHINE_TYPE"
ok "existing boot disk image: $IMAGE"

# --- recreate the pre-created instances if asked -------------------------
if [ "$RECREATE_INSTANCES" = "1" ]; then
  printf '#!/bin/bash\n' > "$WORKDIR/startup.sh"
  for N in tf-instance-1 tf-instance-2; do
    if gcloud compute instances describe "$N" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; then
      ok "$N already exists"
      continue
    fi
    info "creating $N ($MACHINE_TYPE) in $ZONE"
    if printf '%s' "$IMAGE" | grep -qE '^debian-[0-9]+$'; then
      CREATE_IMG=(--image-family="$IMAGE" --image-project=debian-cloud)
    else
      CREATE_IMG=(--image="$IMAGE")
    fi
    if gcloud compute instances create "$N" --zone "$ZONE" --project "$PROJECT_ID" \
         --machine-type="$MACHINE_TYPE" "${CREATE_IMG[@]}" \
         --metadata-from-file "startup-script=$WORKDIR/startup.sh" >/dev/null 2>&1; then
      ok "created $N"
    else
      note_fail "could not create $N"
    fi
  done
  info "waiting for the instances to finish starting"
  for i in $(seq 1 60); do
    ST="$(inst_field tf-instance-1 'value(status)')"
    [ "$ST" = "RUNNING" ] && break
    sleep 5
  done
  read_instance_facts
  ok "recovered machine type: $MACHINE_TYPE"
  ok "recovered boot disk image: $IMAGE"
fi
ok "tf-instance-1 id: $INST1_ID"
ok "tf-instance-2 id: $INST2_ID"

# the existing startup script, so terraform does not have to change it
STARTUP_SCRIPT=""
META_JSON="$(inst_field tf-instance-1 'value(metadata.items)')"
if [ -n "$META_JSON" ]; then
  if command -v jq >/dev/null 2>&1; then
    STARTUP_SCRIPT="$(inst_field tf-instance-1 'value(metadata.items)' \
      | jq -r '.[] | select(.key == "startup-script") | .value' 2>/dev/null | head -1)"
  fi
fi
[ -z "$STARTUP_SCRIPT" ] && STARTUP_SCRIPT="#!/bin/bash"

BUCKET_NAME="${BUCKET_OVERRIDE:-$PROJECT_ID}"
ok "remote backend bucket: $BUCKET_NAME"
ok "vpc name: $VPC_NAME    third instance: $THIRD_INSTANCE"

PROGRESS_FILE="$WORKDIR/.gsp345-progress"
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# install terraform (same as the other gcp-arcade scripts)
# ---------------------------------------------------------------------------
tf_version_ok() {
  local have want
  have="$(terraform version 2>/dev/null | head -1 | sed -n 's/^Terraform v\([0-9.]*\).*/\1/p')"
  [ -z "$have" ] && return 1
  want="$1"
  [ "$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -1)" = "$want" ]
}

install_with_binary() {
  local ver="$1" os arch url tmp
  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac
  url="https://releases.hashicorp.com/terraform/${ver}/terraform_${ver}_${os}_${arch}.zip"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/terraform.zip" "$url" || { rm -rf "$tmp"; return 1; }
  unzip -o -q "$tmp/terraform.zip" -d "$HOME/bin" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  chmod +x "$HOME/bin/terraform" 2>/dev/null
  "$HOME/bin/terraform" version >/dev/null 2>&1 || return 1
  return 0
}

if [ "$SKIP_INSTALL" -eq 0 ]; then
  export PATH="$HOME/bin:$PATH"
  if command -v terraform >/dev/null 2>&1 && tf_version_ok "1.3"; then
    ok "terraform already installed: $(terraform version 2>/dev/null | head -1)"
  else
    TF_VERSION="$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/terraform/latest 2>/dev/null \
      | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -z "$TF_VERSION" ] && TF_VERSION="1.16.6"
    info "installing Terraform v$TF_VERSION"
    install_with_binary "$TF_VERSION" && ok "terraform v$TF_VERSION installed" \
      || note_fail "could not install terraform"
  fi

  CUSTOMIZE="$HOME/.customize_environment"
  if [ -f "$CUSTOMIZE" ] && grep -q "GSP345" "$CUSTOMIZE"; then
    :
  else
    if [ -f "$CUSTOMIZE" ]; then
      cp "$CUSTOMIZE" "$CUSTOMIZE.bak.$(date +%s 2>/dev/null || echo 0)"
      warn "backed up your existing ~/.customize_environment"
      cat >> "$CUSTOMIZE" <<'EOF'

# GSP345 - keep terraform on PATH across Cloud Shell sessions
export PATH="$HOME/bin:$PATH"
EOF
    else
      cat > "$CUSTOMIZE" <<'EOF'
# GSP345 - keep terraform on PATH across Cloud Shell sessions
export PATH="$HOME/bin:$PATH"
EOF
    fi
    ok "PATH persistence written to ~/.customize_environment"
  fi
fi

if ! command -v terraform >/dev/null 2>&1; then
  err "terraform is not on PATH"
  exit 1
fi
ok "terraform version: $(terraform version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# terraform helpers
# ---------------------------------------------------------------------------
cd "$WORKDIR" || { err "cannot cd to $WORKDIR"; exit 1; }

tf_fmt() {
  # Formats and, more importantly, PARSES every .tf file. A syntax error in
  # the generated configuration stops the run here instead of halfway through
  # a task with a broken apply.
  info "terraform fmt (parsing the generated configuration)"
  if terraform fmt -recursive -no-color "$WORKDIR" > "$WORKDIR/fmt.log" 2>&1; then
    ok "the generated configuration is valid HCL"
    return 0
  fi
  note_fail "terraform fmt failed - the generated configuration is not valid HCL"
  sed 's/^/    /' "$WORKDIR/fmt.log"
  return 1
}

tf_init() {
  info "terraform init"
  if terraform init -input=false -no-color > "$WORKDIR/init.log" 2>&1; then
    ok "terraform init complete"
    return 0
  fi
  note_fail "terraform init failed"
  tail -25 "$WORKDIR/init.log" | sed 's/^/    /'
  return 1
}

tf_init_migrate() {
  info "terraform init -migrate-state (moving state into the GCS backend)"
  if printf 'yes\n' | terraform init -migrate-state -no-color > "$WORKDIR/init.log" 2>&1; then
    ok "state migrated to gs://$BUCKET_NAME/terraform/state"
    return 0
  fi
  note_fail "terraform init -migrate-state failed"
  tail -25 "$WORKDIR/init.log" | sed 's/^/    /'
  return 1
}

tf_plan() {
  info "terraform plan"
  if terraform plan -input=false -no-color > "$WORKDIR/plan.log" 2>&1; then
    PLAN_SUMMARY="$(grep -E '^Plan:' "$WORKDIR/plan.log" | tail -1)"
    DESTROY_COUNT="$(printf '%s' "$PLAN_SUMMARY" | sed -n 's/.*[^0-9]\([0-9]\+\) to destroy.*/\1/p')"
    [ -z "$DESTROY_COUNT" ] && DESTROY_COUNT=0
    ok "plan: ${PLAN_SUMMARY:-no changes}"
    return 0
  fi
  note_fail "terraform plan failed"
  tail -30 "$WORKDIR/plan.log" | sed 's/^/    /'
  return 1
}

tf_apply() {  # $1 = "allow" to permit destroys (only task 5 needs it)
  local allow_destroy="${1:-0}"

  tf_plan || return 1

  # SAFETY NET. boot_disk.initialize_params.image and machine_type are
  # ForceNew, so a configuration that does not match the imported instances
  # makes Terraform delete them and then fail to recreate them - which
  # destroys the lab. Never apply a plan that destroys anything unless the
  # task explicitly asked for it.
  if [ "$allow_destroy" != "allow" ] && [ "${DESTROY_COUNT:-0}" -gt 0 ]; then
    note_fail "refusing to apply: the plan would DESTROY $DESTROY_COUNT resource(s)"
    dim "  the configuration does not match the existing resources (usually the"
    dim "  boot disk image or machine type), and Terraform would delete them and"
    dim "  then fail to recreate them. Fix the configuration and re-run."
    echo ""
    grep -E "must be replaced|will be destroyed" "$WORKDIR/plan.log" | head -10 | sed 's/^/    /'
    echo ""
    dim "  the full plan is in $WORKDIR/plan.log"
    return 1
  fi

  info "terraform apply"
  if terraform apply -auto-approve -input=false -no-color > "$WORKDIR/apply.log" 2>&1; then
    ok "terraform apply complete"
    grep -E '^(Apply complete|Plan:)' "$WORKDIR/apply.log" | tail -2 | sed 's/^/    /'
    return 0
  fi
  note_fail "terraform apply failed"
  tail -35 "$WORKDIR/apply.log" | sed 's/^/    /'
  return 1
}

tf_import() {  # $1 = address, $2 = id
  if terraform state list 2>/dev/null | grep -qx "$1"; then
    ok "$1 is already in the state - skipping the import"
    return 0
  fi
  info "terraform import $1"
  if terraform import -input=false -no-color "$1" "$2" > "$WORKDIR/import.log" 2>&1; then
    ok "imported $2"
    return 0
  fi
  note_fail "terraform import $1 failed"
  tail -20 "$WORKDIR/import.log" | sed 's/^/    /'
  return 1
}

# ---------------------------------------------------------------------------
# file writers
# ---------------------------------------------------------------------------
write_variables() {  # $1 = target path
  cat > "$1" <<EOF_END
variable "region" {
  default = "$REGION"
}

variable "zone" {
  default = "$ZONE"
}

variable "project_id" {
  default = "$PROJECT_ID"
}
EOF_END
}

write_main_tf() {  # $1 = with_storage, $2 = with_backend, $3 = with_vpc, $4 = with_firewall
  local with_storage="$1" with_backend="$2" with_vpc="$3" with_firewall="$4"

  {
    echo "terraform {"
    if [ "$with_backend" = "1" ]; then
      echo "  backend \"gcs\" {"
      echo "    bucket = \"$BUCKET_NAME\""
      echo "    prefix = \"terraform/state\""
      echo "  }"
      echo ""
    fi
    echo "  required_providers {"
    echo "    google = {"
    echo "      source  = \"hashicorp/google\""
    echo "      version = \"~> 6.0\""
    echo "    }"
    echo "  }"
    echo "}"
    echo ""
    echo "provider \"google\" {"
    echo "  project = var.project_id"
    echo "  region  = var.region"
    echo "  zone    = var.zone"
    echo "}"
    echo ""
    echo "module \"instances\" {"
    echo "  source     = \"./modules/instances\""
    echo "  region     = var.region"
    echo "  zone       = var.zone"
    echo "  project_id = var.project_id"
    echo "}"
    echo ""
    if [ "$with_storage" = "1" ]; then
      echo "module \"storage\" {"
      echo "  source     = \"./modules/storage\""
      echo "  region     = var.region"
      echo "  zone       = var.zone"
      echo "  project_id = var.project_id"
      echo "}"
      echo ""
    fi
    if [ "$with_vpc" = "1" ]; then
      echo "module \"vpc\" {"
      echo "  source  = \"terraform-google-modules/network/google\""
      echo "  version = \"10.0.0\""
      echo ""
      echo "  project_id   = var.project_id"
      echo "  network_name = \"$VPC_NAME\""
      echo "  routing_mode = \"GLOBAL\""
      echo ""
      echo "  subnets = ["
      echo "    {"
      echo "      subnet_name   = \"subnet-01\""
      echo "      subnet_ip     = \"10.10.10.0/24\""
      echo "      subnet_region = var.region"
      echo "    },"
      echo "    {"
      echo "      subnet_name   = \"subnet-02\""
      echo "      subnet_ip     = \"10.10.20.0/24\""
      echo "      subnet_region = var.region"
      echo "    }"
      echo "  ]"
      echo "}"
      echo ""
    fi
    if [ "$with_firewall" = "1" ]; then
      echo "resource \"google_compute_firewall\" \"tf-firewall\" {"
      echo "  name    = \"tf-firewall\""
      echo "  network = \"projects/$PROJECT_ID/global/networks/$VPC_NAME\""
      echo ""
      echo "  allow {"
      echo "    protocol = \"tcp\""
      echo "    ports    = [\"80\"]"
      echo "  }"
      echo ""
      echo "  source_ranges = [\"0.0.0.0/0\"]"
      echo "}"
      echo ""
    fi
  } > "$WORKDIR/main.tf"
}

write_instance_resource() {  # $1 = resource label, $2 = instance name, $3 = machine type,
                             # $4 = network, $5 = subnetwork ("" for none)
  {
    printf 'resource "google_compute_instance" "%s" {\n' "$1"
    printf '  name         = "%s"\n' "$2"
    printf '  machine_type = "%s"\n' "$3"
    printf '  zone         = var.zone\n'
    printf '\n'
    printf '  allow_stopping_for_update = true\n'
    printf '\n'
    printf '  metadata_startup_script = <<-EOT\n'
    printf '\t%s\n' "$STARTUP_SCRIPT"
    printf '\tEOT\n'
    printf '\n'
    printf '  boot_disk {\n'
    printf '    initialize_params {\n'
    printf '      image = "%s"\n' "$IMAGE"
    printf '    }\n'
    printf '  }\n'
    printf '\n'
    printf '  network_interface {\n'
    printf '    network = "%s"\n' "$4"
    if [ -n "$5" ]; then
      printf '    subnetwork = "%s"\n' "$5"
    fi
    printf '  }\n'
    printf '}\n'
  }
}

write_instances_tf() {  # $1 = variant: two | three | vpc
  local variant="$1"
  {
    if [ "$variant" = "vpc" ]; then
      write_instance_resource "tf-instance-1" "tf-instance-1" "e2-standard-2" "$VPC_NAME" "subnet-01"
      echo ""
      write_instance_resource "tf-instance-2" "tf-instance-2" "e2-standard-2" "$VPC_NAME" "subnet-02"
    else
      write_instance_resource "tf-instance-1" "tf-instance-1" "$MACHINE_TYPE" "default" ""
      echo ""
      write_instance_resource "tf-instance-2" "tf-instance-2" "$MACHINE_TYPE" "default" ""
      if [ "$variant" = "three" ]; then
        echo ""
        write_instance_resource "tf-instance-3" "$THIRD_INSTANCE" "e2-standard-2" "default" ""
      fi
    fi
  } > "$WORKDIR/modules/instances/instances.tf"
}

write_storage_tf() {
  cat > "$WORKDIR/modules/storage/storage.tf" <<EOF_END
resource "google_storage_bucket" "storage-bucket" {
  name                       = "$BUCKET_NAME"
  location                   = "US"
  force_destroy              = true
  uniform_bucket_level_access = true
}
EOF_END
}

write_outputs() {
  cat > "$WORKDIR/modules/instances/outputs.tf" <<'EOF_END'
output "instance_ids" {
  value = {
    tf-instance-1 = google_compute_instance.tf-instance-1.id
    tf-instance-2 = google_compute_instance.tf-instance-2.id
  }
}
EOF_END
  cat > "$WORKDIR/modules/storage/outputs.tf" <<'EOF_END'
output "bucket_name" {
  value = google_storage_bucket.storage-bucket.name
}
EOF_END
}

make_structure() {
  mkdir -p "$WORKDIR/modules/instances" "$WORKDIR/modules/storage"
  write_variables "$WORKDIR/variables.tf"
  write_variables "$WORKDIR/modules/instances/variables.tf"
  write_variables "$WORKDIR/modules/storage/variables.tf"
  write_outputs
}

# ---------------------------------------------------------------------------
# task runner
# ---------------------------------------------------------------------------
pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue (Ctrl-C stops - just re-run%s\n" "$C_DIM"
  printf "  %s    ./gsp345.sh later and it picks up where you left off).%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

DONE_N=0
[ -f "$PROGRESS_FILE" ] && DONE_N="$(cat "$PROGRESS_FILE" 2>/dev/null || echo 0)"

run_task() {  # $1 = number
  local n="$1"
  case "$n" in
  1)
    step "Task 1 - Create the configuration files"
    make_structure
    write_main_tf 0 0 0 0
    ok "wrote main.tf, variables.tf and the module tree"
    tf_fmt
    dim "    main.tf, variables.tf, modules/{instances,storage}/{*.tf,variables.tf,outputs.tf}"
    tf_init
    ;;
  2)
    step "Task 2 - Import infrastructure"
    make_structure
    write_main_tf 0 0 0 0
    write_instances_tf "two"
    tf_fmt
    tf_init
    tf_import "module.instances.google_compute_instance.tf-instance-1" "$INST1_ID"
    tf_import "module.instances.google_compute_instance.tf-instance-2" "$INST2_ID"
    tf_apply
    ;;
  3)
    step "Task 3 - Configure a remote backend"
    make_structure
    write_storage_tf
    write_main_tf 1 0 0 0
    tf_fmt
    tf_init
    tf_apply
    info "switching the backend to gs://$BUCKET_NAME/terraform/state"
    write_main_tf 1 1 0 0
    tf_fmt
    tf_init_migrate
    ;;
  4)
    step "Task 4 - Modify and update infrastructure"
    make_structure
    write_main_tf 1 1 0 0
    write_instances_tf "three"
    tf_fmt
    tf_init
    tf_apply
    dim "    all three instances are now e2-standard-2"
    ;;
  5)
    step "Task 5 - Destroy resources"
    make_structure
    write_main_tf 1 1 0 0
    write_instances_tf "two"
    tf_fmt
    tf_init
    tf_apply "allow"
    dim "    $THIRD_INSTANCE has been removed from the configuration and destroyed"
    ;;
  6)
    step "Task 6 - Use a module from the Registry"
    make_structure
    write_instances_tf "vpc"
    write_main_tf 1 1 1 0
    tf_fmt
    tf_init
    tf_apply
    dim "    VPC $VPC_NAME with subnet-01 (10.10.10.0/24) and subnet-02 (10.10.20.0/24)"
    dim "    tf-instance-1 -> subnet-01, tf-instance-2 -> subnet-02"
    ;;
  7)
    step "Task 7 - Configure a firewall"
    make_structure
    write_main_tf 1 1 1 1
    tf_fmt
    tf_init
    tf_apply
    dim "    tf-firewall: tcp:80 from 0.0.0.0/0 on $VPC_NAME"
    ;;
  esac
}

TASK_NAMES="Create the configuration files|Import infrastructure|Configure a remote backend|Modify and update infrastructure|Destroy resources|Use a module from the Registry|Configure a firewall"

if [ -n "$ONLY_TASK" ]; then
  if ! printf '%s' "$ONLY_TASK" | grep -qE '^[1-7]$'; then
    err "--task must be between 1 and 7"
    exit 2
  fi
  run_task "$ONLY_TASK"
  echo "$ONLY_TASK" > "$PROGRESS_FILE"
  exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
fi

if [ "$DONE_N" -ge 7 ]; then
  info "all seven tasks are already done - re-running from task 1 to re-apply everything"
  DONE_N=0
fi

for n in 1 2 3 4 5 6 7; do
  if [ "$n" -le "$DONE_N" ]; then
    dim "  (task $n already done, skipping)"
    continue
  fi
  run_task "$n"
  if [ "$FAILURES" -eq 0 ]; then
    echo "$n" > "$PROGRESS_FILE"
  else
    note_fail "task $n did not complete cleanly - fix the errors above and re-run"
    break
  fi
  NAME="$(printf '%s' "$TASK_NAMES" | cut -d'|' -f"$n")"
  pause_for_check "$n" "$NAME"
done

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------
step "Verify"
echo "  instances:"
gcloud compute instances list --project "$PROJECT_ID" \
  --filter="zone=$ZONE" --format="table(name,zone,machineType,status)" 2>/dev/null | sed 's/^/    /'
echo "  networks:"
gcloud compute networks list --project "$PROJECT_ID" \
  --filter="name!~^default$" --format="table(name,subnetMode,autoCreateSubnetworks)" 2>/dev/null | sed 's/^/    /'
echo "  subnets in $REGION:"
gcloud compute networks subnets list --project "$PROJECT_ID" \
  --filter="region=$REGION" --format="table(name,network,ipCidrRange,region)" 2>/dev/null | sed 's/^/    /'
echo "  firewall rules:"
gcloud compute firewall-rules list --project "$PROJECT_ID" \
  --format="table(name,network,direction,priority,allow,sourceRanges)" 2>/dev/null | sed 's/^/    /'
echo "  buckets:"
gcloud storage ls --project "$PROJECT_ID" 2>/dev/null | sed 's/^/    /'
echo ""
dim "  remote backend state: gs://$BUCKET_NAME/terraform/state"

step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Region   : $REGION"
echo "  Zone     : $ZONE"
echo "  Workdir  : $WORKDIR"
echo "  Bucket   : $BUCKET_NAME"
echo "  VPC      : $VPC_NAME"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
dim "  Clean up: cd $WORKDIR && terraform destroy -auto-approve"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
