#!/usr/bin/env bash
# =============================================================================
#  GSP156 - "Terraform Fundamentals"
#  Google Cloud Arcade / Cloud Skills Boost lab.
#
#  Installs Terraform, writes the instance.tf configuration, and provisions a
#  VM instance named "terraform" (e2-medium) in the lab's zone.
#
#  QUICK START (Cloud Shell):
#     bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp156.sh)
#
#  ...or download it:
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp156.sh
#     chmod +x gsp156.sh
#     ./gsp156.sh
#
#  OPTIONS:
#     --project ID        GCP project (default: active gcloud project)
#     --zone ZONE         e.g. us-west1-c  (default: gcloud config compute/zone)
#     --region REGION     e.g. us-west1    (default: gcloud config compute/region)
#     --image IMAGE       boot disk image (default: auto-detected Debian image)
#     --machine-type T    e.g. e2-medium
#     --name NAME         instance name (default: terraform)
#     --workdir PATH      where instance.tf lives (default: $HOME/gsp156)
#     --install-method M  binary (default) or apt - apt reproduces the lab's
#                         HashiCorp repository steps verbatim
#     --destroy           destroy the infrastructure and exit
#     --skip-install      assume terraform is already on PATH
#     -h, --help          this help
#
#  NOTES:
#   * The lab's scored checkpoint is "Create a VM instance in <zone> with
#     Terraform". The Debian image id, project and zone are injected by the
#     lab template, so this script discovers all three at runtime.
#   * The installation is persisted in ~/.customize_environment so terraform
#     survives Cloud Shell restarts, exactly as the lab asks.
#   * Idempotent: re-running imports an already-existing instance into state
#     instead of failing.
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
IMAGE_OVERRIDE=""
MACHINE_TYPE="e2-medium"
INSTANCE_NAME="terraform"
WORKDIR="${GSP156_WORKDIR:-$HOME/gsp156}"
INSTALL_METHOD="binary"
DO_DESTROY=0
SKIP_INSTALL=0

# The zone Cloud Skills Boost assigns to GSP156, used as a fallback only.
# `gcloud config compute/zone` survives Cloud Shell restarts and is very often
# still pointing at a PREVIOUS lab's zone, so it cannot be trusted.
LAB_ZONE="europe-west1-d"

usage() {
  cat <<'USAGE_END'
GSP156 - Terraform Fundamentals
Google Cloud Arcade / Cloud Skills Boost lab.

QUICK START (Google Cloud Shell):
   bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp156.sh)

OPTIONS:
   --project ID        GCP project (default: active gcloud project)
   --zone ZONE         e.g. us-west1-c  (default: gcloud config compute/zone)
   --region REGION     e.g. us-west1    (default: gcloud config compute/region)
   --image IMAGE       boot disk image (default: auto-detected Debian image)
   --machine-type T    e.g. e2-medium
   --name NAME         instance name (default: terraform)
   --workdir PATH      where instance.tf lives (default: $HOME/gsp156)
   --install-method M  binary (default) or apt
   --destroy           destroy the infrastructure and exit
   --skip-install      assume terraform is already on PATH
   -h, --help          this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)        PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)           ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)         REGION_OVERRIDE="$2";   shift 2 ;;
    --image)          IMAGE_OVERRIDE="$2";    shift 2 ;;
    --machine-type)   MACHINE_TYPE="$2";      shift 2 ;;
    --name)           INSTANCE_NAME="$2";      shift 2 ;;
    --workdir)        WORKDIR="$2";           shift 2 ;;
    --install-method) INSTALL_METHOD="$2";    shift 2 ;;
    --destroy)        DO_DESTROY=1;           shift ;;
    --skip-install)   SKIP_INSTALL=1;         shift ;;
    -h|--help)        usage ;;
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

# Zone detection. The lab's zone is the single most important value here and
# the most commonly wrong one: `gcloud config compute/zone` is a per-user
# setting that survives Cloud Shell restarts, so the zone from a PREVIOUS lab
# is often still sitting there. Sources are tried most-reliable first.
GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

zone_exists() {
  gcloud compute zones describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

# Sets ZONE and ZONE_SOURCE directly. Deliberately NOT called in a
# subshell - a command substitution would discard the ZONE_SOURCE assignment.
detect_zone() {
  local z

  # 1. the zone Cloud Skills Boost assigns to this lab. Checked first because
  #    `gcloud config compute/zone` survives Cloud Shell restarts and is very
  #    often still pointing at a PREVIOUS lab's zone.
  if [ -n "$LAB_ZONE" ] && zone_exists "$LAB_ZONE"; then
    ZONE="$LAB_ZONE"
    ZONE_SOURCE="the lab's default zone (override with --zone)"
    return 0
  fi

  # 2. an instance that already exists in this project
  z="$(gcloud compute instances list --project "$PROJECT_ID" \
        --format="value(zone)" 2>/dev/null | head -1 | sed 's|.*/||')"
  if [ -n "$z" ] && [ "$z" != "(unset)" ]; then
    ZONE="$z"
    ZONE_SOURCE="an existing instance in this project"
    return 0
  fi

  # 3. the project's startup script metadata
  z="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null \
        | grep -oE '\b[a-z]+-[a-z]+[0-9]-[a-z]\b' | head -1)"
  if [ -n "$z" ] && zone_exists "$z"; then
    ZONE="$z"
    ZONE_SOURCE="the project startup script metadata"
    return 0
  fi

  # 4. the environment
  if [ -n "${CLOUDSDK_COMPUTE_ZONE:-}" ] && zone_exists "$CLOUDSDK_COMPUTE_ZONE"; then
    ZONE="$CLOUDSDK_COMPUTE_ZONE"
    ZONE_SOURCE="CLOUDSDK_COMPUTE_ZONE"
    return 0
  fi

  # 5. gcloud config - may well be left over from a previous lab
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
  REGION="${ZONE_OVERRIDE%-*}"
else
  REGION="${REGION_OVERRIDE:-${GCP_REGION:-${CLOUDSDK_COMPUTE_REGION:-${ZONE%-*}}}}"
fi

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
printf "%s%s  GSP156 - Terraform Fundamentals%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %stype=%s  %sworkdir=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$MACHINE_TYPE" "$C_DIM" "$WORKDIR" "$C_RESET"
printf "  %sZONE  = %s%s%s   %s(from %s)%s\n" \
  "$C_BOLD" "$C_YELLOW" "$ZONE" "$C_RESET" "$C_DIM" "$ZONE_SOURCE" "$C_RESET"
printf "  %simage = %s%s%s\n" "$C_DIM" "${IMAGE_OVERRIDE:-auto}" "$C_RESET"
echo ""
printf "  %s>> Confirm the zone matches the lab page before continuing.%s\n" "$C_YELLOW" "$C_RESET"
printf "  %s   The lab scores the VM against its own zone. If it differs, stop and%s\n" "$C_DIM"
printf "  %s   re-run with:  ./gsp156.sh --zone <lab-zone>%s\n" "$C_DIM" "$C_RESET"

step "Preflight checks"

if ! command -v gcloud >/dev/null 2>&1; then
  err "gcloud not found on PATH. Run this inside Google Cloud Shell."
  exit 1
fi
ok "gcloud is available"

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  err "neither curl nor wget found - cannot download terraform"
  exit 1
fi

ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
[ -z "$ACTIVE_ACCOUNT" ] || [ "$ACTIVE_ACCOUNT" = "(unset)" ] && ACTIVE_ACCOUNT=""
if [ -z "$ACTIVE_ACCOUNT" ]; then
  warn "no active gcloud account - run: gcloud auth login"
else
  ok "active account: $ACTIVE_ACCOUNT"
fi

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

# Terraform talks to GCP through Application Default Credentials. Cloud Shell
# is normally pre-authenticated, but check so the failure is not a mystery.
ADC_DIR="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
if [ -f "$ADC_DIR/application_default_credentials.json" ]; then
  ok "application default credentials present"
else
  warn "no ADC file at $ADC_DIR/application_default_credentials.json"
  warn "if terraform reports 'could not find default credentials', run:"
  warn "  gcloud auth application-default login"
fi

# The "default" network must exist for the instance to get an IP.
if gcloud compute networks describe default --project "$PROJECT_ID" >/dev/null 2>&1; then
  ok "default network exists"
else
  warn "no 'default' network in $PROJECT_ID - the instance will fail to start"
fi

mkdir -p "$WORKDIR" || { err "cannot create workdir $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# Task 1 - install Terraform
# ---------------------------------------------------------------------------
tf_version_ok() {
  # returns 0 when the installed terraform is at least $1
  local have want
  have="$(terraform version 2>/dev/null | head -1 | sed -n 's/^Terraform v\([0-9.]*\).*/\1/p')"
  [ -z "$have" ] && return 1
  want="$1"
  [ "$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -1)" = "$want" ]
}

install_with_apt() {
  info "using the lab's HashiCorp apt repository method (this takes a minute)"
  cat > "$HOME/.customize_environment" <<'EOF'
# Set up HashiCorp repository and install Terraform
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
  if bash "$HOME/.customize_environment" >/dev/null 2>&1; then
    return 0
  fi
  return 1
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
  if ! curl -fsSL -o "$tmp/terraform.zip" "$url"; then
    rm -rf "$tmp"
    return 1
  fi
  if ! unzip -o -q "$tmp/terraform.zip" -d "$HOME/bin" 2>/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  chmod +x "$HOME/bin/terraform" 2>/dev/null
  # Make sure the downloaded binary actually runs on this machine.
  if ! "$HOME/bin/terraform" version >/dev/null 2>&1; then
    echo "the downloaded terraform binary does not execute on this system" >&2
    return 1
  fi
  return 0
}

step "Task 1 - Terraform installation"

if [ "$SKIP_INSTALL" -eq 1 ]; then
  info "--skip-install given"
  if ! command -v terraform >/dev/null 2>&1; then
    err "terraform is not on PATH"
    exit 1
  fi
  ok "terraform found: $(terraform version 2>/dev/null | head -1)"
else
  export PATH="$HOME/bin:$PATH"

  if command -v terraform >/dev/null 2>&1 && tf_version_ok "1.5.7"; then
    ok "terraform already installed: $(terraform version 2>/dev/null | head -1)"
  else
    TF_VERSION="$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/terraform/latest 2>/dev/null \
      | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -z "$TF_VERSION" ] && TF_VERSION="1.16.6"
    info "installing Terraform v$TF_VERSION"

    INSTALLED=0
    if [ "$INSTALL_METHOD" = "apt" ]; then
      install_with_apt && INSTALLED=1
      [ "$INSTALLED" -eq 1 ] || warn "apt method failed, falling back to the release binary"
    fi
    if [ "$INSTALLED" -eq 0 ]; then
      install_with_binary "$TF_VERSION" && INSTALLED=1
    fi
    if [ "$INSTALLED" -eq 0 ]; then
      note_fail "could not install terraform"
    else
      ok "terraform v$TF_VERSION installed to $HOME/bin"
    fi
  fi

  # Persist across Cloud Shell restarts - this is what the lab asks for.
  CUSTOMIZE="$HOME/.customize_environment"
  if [ -f "$CUSTOMIZE" ] && grep -q "GSP156" "$CUSTOMIZE"; then
    ok "PATH persistence already configured in ~/.customize_environment"
  else
    if [ -f "$CUSTOMIZE" ]; then
      cp "$CUSTOMIZE" "$CUSTOMIZE.bak.$(date +%s 2>/dev/null || echo 0)"
      warn "backed up your existing ~/.customize_environment"
      cat >> "$CUSTOMIZE" <<'EOF'

# GSP156 - keep terraform on PATH across Cloud Shell sessions
export PATH="$HOME/bin:$PATH"
EOF
    else
      cat > "$CUSTOMIZE" <<'EOF'
# GSP156 - keep terraform on PATH across Cloud Shell sessions
export PATH="$HOME/bin:$PATH"
EOF
    fi
    ok "PATH persistence written to ~/.customize_environment"
  fi
fi

if ! command -v terraform >/dev/null 2>&1; then
  err "terraform is still not on PATH - check the install output above"
  exit 1
fi
ok "terraform version: $(terraform version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# Task 2 - build the infrastructure
# ---------------------------------------------------------------------------
step "Task 2 - Build the infrastructure"

cd "$WORKDIR" || { err "cannot cd to $WORKDIR"; exit 1; }

# --- resolve the boot disk image -------------------------------------------
resolve_image() {
  if [ -n "$IMAGE_OVERRIDE" ]; then
    echo "$IMAGE_OVERRIDE"
    return 0
  fi

  # The lab's own boot disk image family. Cloud Skills Boost usually leaves it
  # in the project's common instance metadata (startup script).
  local meta found
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  if [ -n "$meta" ]; then
    found="$(printf '%s' "$meta" \
      | grep -oE 'debian-[0-9]+(-[a-z]+)?(-v[0-9]+)?' | head -1)"
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
  fi

  # This is the exact image family the lab's own instance.tf uses.
  echo "debian-12"
}

IMAGE="$(resolve_image)"
ok "boot disk image: $IMAGE"

cat > "$WORKDIR/instance.tf" <<EOF_END
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_compute_instance" "default" {
  project      = "$PROJECT_ID"
  zone         = "$ZONE"
  name         = "$INSTANCE_NAME"
  machine_type = "$MACHINE_TYPE"
  boot_disk {
    initialize_params {
      image = "$IMAGE"
    }
  }
  network_interface {
    network = "default"
    access_config {
    }
  }
}
EOF_END
ok "wrote $WORKDIR/instance.tf"

echo ""
dim "  ls:"
ls -1 "$WORKDIR" | sed 's/^/    /'
echo ""

# --- init ------------------------------------------------------------------
info "terraform init (downloading the Google provider)"
if ! terraform init -input=false -no-color > "$WORKDIR/init.log" 2>&1; then
  note_fail "terraform init failed"
  tail -25 "$WORKDIR/init.log" | sed 's/^/    /'
else
  ok "terraform init complete"
  grep -E "Installing hashicorp/google" "$WORKDIR/init.log" | head -1 | sed 's/^/    /'
fi

# --- import an already existing instance instead of failing ---------------
# `terraform state list` is the canonical way to ask "is this resource
# already tracked?". Grepping the .tfstate JSON for "type.name" does not
# work - the state file stores type and name in separate fields.
if [ -f "$WORKDIR/terraform.tfstate" ] \
   && terraform state list 2>/dev/null | grep -q "^google_compute_instance.default$"; then
  info "state already contains google_compute_instance.default - nothing to create"
elif gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" \
        --project "$PROJECT_ID" >/dev/null 2>&1; then
  warn "instance '$INSTANCE_NAME' exists but is not in terraform state - importing it"
  if terraform import -input=false -no-color \
       google_compute_instance.default "$INSTANCE_NAME" > "$WORKDIR/import.log" 2>&1; then
    ok "imported $INSTANCE_NAME into terraform state"
  else
    note_fail "terraform import failed"
    tail -15 "$WORKDIR/import.log" | sed 's/^/    /'
  fi
fi

# --- plan ------------------------------------------------------------------
info "terraform plan"
if terraform plan -input=false -no-color > "$WORKDIR/plan.log" 2>&1; then
  PLAN_LINE="$(grep -E '^Plan:' "$WORKDIR/plan.log" | tail -1)"
  ok "plan succeeded${PLAN_LINE:+ - $PLAN_LINE}"
else
  note_fail "terraform plan failed"
  tail -25 "$WORKDIR/plan.log" | sed 's/^/    /'
fi

# --- apply -----------------------------------------------------------------
if [ "$DO_DESTROY" -eq 1 ]; then
  step "Destroying the infrastructure"
  if terraform destroy -auto-approve -input=false -no-color > "$WORKDIR/destroy.log" 2>&1; then
    ok "terraform destroy complete"
  else
    note_fail "terraform destroy failed"
    tail -25 "$WORKDIR/destroy.log" | sed 's/^/    /'
  fi
else
  step "Applying changes"
  if terraform apply -auto-approve -input=false -no-color > "$WORKDIR/apply.log" 2>&1; then
    ok "terraform apply complete"
    grep -E '^(Apply complete|Plan:)' "$WORKDIR/apply.log" | tail -2 | sed 's/^/    /'
  else
    note_fail "terraform apply failed"
    tail -30 "$WORKDIR/apply.log" | sed 's/^/    /'
  fi
fi

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------
step "Verify"

if [ "$DO_DESTROY" -eq 1 ]; then
  info "destroy mode - skipping the instance checks"
  gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" \
    --project "$PROJECT_ID" >/dev/null 2>&1 \
    && warn "instance '$INSTANCE_NAME' still exists in $ZONE" \
    || ok "instance '$INSTANCE_NAME' is gone"
else
  if gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" \
       --project "$PROJECT_ID" --format="table(name,zone,machineType,status)" 2>/dev/null; then
    ok "instance '$INSTANCE_NAME' exists in $ZONE"
  else
    note_fail "instance '$INSTANCE_NAME' not found in $ZONE"
  fi

  # The lab scores the VM against its own zone. If the instance ended up
  # somewhere else, say so loudly and show exactly how to move it.
  STRAY="$(gcloud compute instances list --project "$PROJECT_ID" \
    --filter="name=$INSTANCE_NAME" --format="value(zone)" 2>/dev/null \
    | sed 's|.*/||' | grep -v "^$ZONE$" | head -1)"
  if [ -n "$STRAY" ]; then
    err "instance '$INSTANCE_NAME' is in $STRAY but this script targeted $ZONE"
    dim "  If the lab wants a different zone, re-run with it - Terraform will"
    dim "  replace the instance (zone is a ForceNew field):"
    dim "    ./gsp156.sh --zone <lab-zone>"
  fi

  EXT_IP="$(gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" \
    --project "$PROJECT_ID" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"
  if [ -n "$EXT_IP" ] && [ "$EXT_IP" != "None" ]; then
    ok "external IP: $EXT_IP"
    dim "  ssh: gcloud compute ssh $INSTANCE_NAME --zone $ZONE"
  fi
fi

echo ""
dim "  terraform show:"
terraform show -no-color 2>/dev/null | head -30 | sed 's/^/    /'
echo ""

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Zone     : $ZONE"
echo "  Instance : $INSTANCE_NAME ($MACHINE_TYPE)"
echo "  Image    : $IMAGE"
echo "  Workdir  : $WORKDIR"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Click 'Check my progress' in the lab console."
echo "  Then answer the Task 3 multiple-choice questions:"
echo "    - Terraform enables you to safely and predictably create, change and"
echo "      improve infrastructure.  -> True"
echo "    - With Terraform, you can create your own custom provider plugins.  -> False"
echo ""
dim "  Clean up: ./gsp156.sh --destroy"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
