#!/usr/bin/env bash
# =============================================================================
#  "Exploring IAM"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19082).
#
#  Creates a bucket with a sample file, removes the project Viewer role from
#  the second lab user, grants that user Storage Object Viewer, then sets up
#  a service account, the Service Account User role for altostrat.com and a
#  VM that runs as that service account.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_iam.sh
#     chmod +x gsp_iam.sh
#     ./gsp_iam.sh
#
#  OPTIONS:
#     --project ID       GCP project (default: active gcloud project)
#     --user2 EMAIL      the lab's second user (detected, then asked for)
#     --zone ZONE        the lab's zone (asked for)
#     --region REGION    region (default: derived from the zone)
#     --bucket NAME      the bucket (default: the project ID)
#     --domain DOMAIN    the fake company domain (default: altostrat.com)
#     --sa NAME          the service account (default: read-bucket-objects)
#     --vm NAME          the VM (default: demoiam)
#     --task N           run only task N (3-7)
#     --yes              do not pause for the checkpoints
#     --skip-role-change leave the service account as Storage Object Viewer
#     -h, --help         this help
#
#  CHECKPOINTS (100 points, 25 each):
#     1. Create a bucket and upload a sample file
#     2. Remove project access
#     3. Add storage permissions
#     4. Set up the Service Account User and create a VM
#
#  NOTES:
#   * This lab uses TWO Google accounts. Username 1 is you; Username 2 is in
#     the lab's Connection Details panel. The script finds Username 2 on its
#     own - it is the user that holds roles/viewer and is not you - and
#     then asks you to confirm it.
#   * The IAM changes are all made from your account, so the script can do
#     them. Verifying them needs a browser tab signed in as Username 2, so
#     the script prints what to look for.
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
USER2_OVERRIDE=""
ZONE_OVERRIDE=""
REGION_OVERRIDE=""
BUCKET_OVERRIDE=""
DOMAIN="altostrat.com"
SA_NAME="read-bucket-objects"
VM_NAME="demoiam"
ONLY_TASK=""
ASSUME_YES=0
SKIP_ROLE_CHANGE=0

usage() {
  cat <<'USAGE_END'
Exploring IAM

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_iam.sh
   chmod +x gsp_iam.sh
   ./gsp_iam.sh

OPTIONS:
   --project ID       GCP project (default: active gcloud project)
   --user2 EMAIL      the lab's second user (detected, then asked for)
   --zone ZONE        the lab's zone (asked for)
   --region REGION    region (default: derived from the zone)
   --bucket NAME      the bucket (default: the project ID)
   --domain DOMAIN    the fake company domain (default: altostrat.com)
   --sa NAME          the service account (default: read-bucket-objects)
   --vm NAME          the VM (default: demoiam)
   --task N           run only task N (3-7)
   --yes              do not pause for the checkpoints
   --skip-role-change leave the service account as Storage Object Viewer
   -h, --help         this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)         PROJECT_OVERRIDE="$2";  shift 2 ;;
    --user2)           USER2_OVERRIDE="$2";    shift 2 ;;
    --zone)            ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)          REGION_OVERRIDE="$2";   shift 2 ;;
    --bucket)          BUCKET_OVERRIDE="$2";   shift 2 ;;
    --domain)          DOMAIN="$2";            shift 2 ;;
    --sa)              SA_NAME="$2";           shift 2 ;;
    --vm)              VM_NAME="$2";           shift 2 ;;
    --task)            ONLY_TASK="$2";         shift 2 ;;
    --yes)             ASSUME_YES=1;           shift ;;
    --skip-role-change) SKIP_ROLE_CHANGE=1;    shift ;;
    -h|--help)         usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# project and account
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

MY_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
if [ "$MY_ACCOUNT" = "(unset)" ]; then MY_ACCOUNT=""; fi

# ---------------------------------------------------------------------------
# the second lab user
#
# The lab gives Username 2 the roles/viewer role on the project, so the user
# that holds roles/viewer and is not you is Username 2.
# ---------------------------------------------------------------------------
detect_user2() {
  local policy
  policy="$(gcloud projects get-iam-policy "$PROJECT_ID" --format="json" 2>/dev/null)"
  [ -z "$policy" ] && return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$policy" | jq -r --arg me "user:$MY_ACCOUNT" \
      '.bindings[] | select(.role == "roles/viewer" or .role == "roles/storage.objectViewer")
       | .members[]? | select(startswith("user:")) | select(. != $me) | sub("user:"; "")' \
      2>/dev/null | head -1
  else
    # no jq: the only people in the policy are you and Username 2, and the
    # service accounts, so the first user that is not you is Username 2
    printf '%s' "$policy" \
      | tr ',' '\n' | grep -oE '"user:[^"]+"' | sed 's/"user://; s/"$//' \
      | grep -v -x -F "$MY_ACCOUNT" | head -1
  fi
}

WORKDIR="${GSP_IAM_WORKDIR:-$HOME/gsp-iam}"
mkdir -p "$WORKDIR" 2>/dev/null

# Username 2 is remembered between runs: after task 4 the user no longer
# holds roles/viewer, so the policy alone would no longer name them.
DETECTED_USER2=""
if [ -f "$WORKDIR/.user2" ]; then
  DETECTED_USER2="$(cat "$WORKDIR/.user2" 2>/dev/null)"
fi
if [ -z "$DETECTED_USER2" ]; then
  DETECTED_USER2="$(detect_user2 || true)"
  if [ -n "$DETECTED_USER2" ]; then
    echo "$DETECTED_USER2" > "$WORKDIR/.user2"
  fi
fi

# ---------------------------------------------------------------------------
# the zone
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
  printf "  %sZone%s  [%s]: " "$C_BOLD" "$C_RESET" "${META_ZONE:-${GCP_ZONE:-us-central1-a}}"
  read -r ans
  ZONE_OVERRIDE="${ans:-${META_ZONE:-${GCP_ZONE:-us-central1-a}}}"
  echo ""
fi
ZONE="${ZONE_OVERRIDE:-${GCP_ZONE:-us-central1-a}}"
REGION="${REGION_OVERRIDE:-${ZONE%-*}}"

echo ""
warn "this lab uses TWO Google accounts"
dim "  Username 1 is you: $MY_ACCOUNT"
dim "  Username 2 is in the lab's Connection Details panel."
if [ -n "$DETECTED_USER2" ]; then
  dim "  the project policy points at: $DETECTED_USER2"
else
  dim "  the project policy does not name a second user yet."
fi
if [ -z "$USER2_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  printf "  %sUsername 2%s  [%s]: " "$C_BOLD" "$C_RESET" "${DETECTED_USER2:-your-user-2@example.com}"
  read -r ans
  USER2_OVERRIDE="${ans:-${DETECTED_USER2:-}}"
  echo ""
fi
USER2="${USER2_OVERRIDE:-${DETECTED_USER2:-}}"
if [ -z "$USER2" ]; then
  err "could not work out Username 2 - pass it with --user2 EMAIL"
  exit 1
fi

BUCKET="${BUCKET_OVERRIDE:-$PROJECT_ID}"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

printf "%s%s  Exploring IAM%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %suser2=%s  %szone=%s  %sbucket=%s  %ssa=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$USER2" "$C_DIM" "$ZONE" "$C_DIM" "$BUCKET" \
  "$C_DIM" "$SA_EMAIL" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
bucket_exists()   { gcloud storage buckets describe "gs://$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
sa_exists()       { gcloud iam service-accounts describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; }
instance_exists() { gcloud compute instances describe "$1" --zone "$2" --project "$PROJECT_ID" >/dev/null 2>&1; }

# Does the member hold the role on the project?
has_project_role() {  # $1 = member, $2 = role
  local policy
  policy="$(gcloud projects get-iam-policy "$PROJECT_ID" --format="json" 2>/dev/null)"
  [ -z "$policy" ] && return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$policy" | jq -e --arg m "$1" --arg r "$2" \
      '.bindings[]? | select(.role == $r) | .members[]? | select(. == $m)' \
      >/dev/null 2>&1
  else
    printf '%s' "$policy" | grep -q "\"$1\"" && printf '%s' "$policy" | grep -q "\"$2\""
  fi
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
  warn "not in Cloud Shell - the zone may be wrong, use --zone"
fi

# ---------------------------------------------------------------------------
# Task 3 - the bucket and the sample file
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Create a bucket and upload a sample file"

  if bucket_exists "$BUCKET"; then
    ok "the bucket gs://$BUCKET already exists"
  else
    if gcloud storage buckets create "gs://$BUCKET" --project="$PROJECT_ID" \
         --location=US --uniform-bucket-level-access >/dev/null 2>&1; then
      ok "created the bucket gs://$BUCKET"
    else
      note_fail "could not create gs://$BUCKET"
      dim "  bucket names are global - try another one:"
      dim "    ./gsp_iam.sh --bucket $BUCKET-$(date +%s)"
      return 1
    fi
  fi

  info "uploading sample.txt"
  printf 'This is a sample file for the Exploring IAM lab.\n' > "$HOME/sample.txt"
  if gcloud storage cp "$HOME/sample.txt" "gs://$BUCKET/sample.txt" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "uploaded sample.txt to gs://$BUCKET"
  else
    note_fail "could not upload sample.txt"
    return 1
  fi

  gcloud storage ls "gs://$BUCKET" --project="$PROJECT_ID" 2>/dev/null | sed 's/^/      /'

  dim ""
  dim "  In the Username 2 tab, Cloud Storage > Buckets should now show the bucket."

  pause_for_check 3 "Create a bucket and upload a sample file"
}

# ---------------------------------------------------------------------------
# Task 4 - remove the project access
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Remove project access"

  if has_project_role "user:$USER2" "roles/viewer"; then
    info "removing roles/viewer from $USER2"
    if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
         --member="user:$USER2" --role="roles/viewer" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "removed roles/viewer from $USER2"
    else
      note_fail "could not remove roles/viewer"
      return 1
    fi
  else
    ok "$USER2 does not have roles/viewer any more"
  fi

  if has_project_role "user:$USER2" "roles/viewer"; then
    note_fail "roles/viewer is still on $USER2"
  else
    ok "confirmed: $USER2 has no project Viewer role"
  fi

  dim ""
  dim "  In the Username 2 tab, Cloud Storage > Buckets should now show an error."

  pause_for_check 4 "Remove project access"
}

# ---------------------------------------------------------------------------
# Task 5 - add the storage permissions
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Add storage permissions"

  if has_project_role "user:$USER2" "roles/storage.objectViewer"; then
    ok "$USER2 already has roles/storage.objectViewer"
  else
    info "granting roles/storage.objectViewer to $USER2"
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
         --member="user:$USER2" --role="roles/storage.objectViewer" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "granted roles/storage.objectViewer to $USER2"
    else
      note_fail "could not grant roles/storage.objectViewer"
      return 1
    fi
  fi

  dim ""
  dim "  In the Username 2 tab, open Cloud Shell and run:"
  dim "    gcloud storage ls gs://$BUCKET"
  dim "  Username 2 has no project Viewer role, so it cannot see the project in"
  dim "  the console - only this one bucket."

  pause_for_check 5 "Add storage permissions"
}

# ---------------------------------------------------------------------------
# Task 6 - the service account, the role and the VM
# ---------------------------------------------------------------------------
task6() {
  step "Task 6 - Set up the Service Account User"

  if sa_exists "$SA_EMAIL"; then
    ok "the service account $SA_EMAIL already exists"
  else
    if gcloud iam service-accounts create "$SA_NAME" \
         --display-name="$SA_NAME" --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the service account $SA_NAME"
    else
      note_fail "could not create the service account"
      return 1
    fi
  fi

  info "giving the service account Storage Object Viewer on the project"
  if has_project_role "serviceAccount:$SA_EMAIL" "roles/storage.objectViewer"; then
    ok "the service account already has roles/storage.objectViewer"
  else
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectViewer" \
      --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
      && ok "granted roles/storage.objectViewer to the service account" \
      || note_fail "could not grant the storage role to the service account"
  fi

  info "giving domain:$DOMAIN the Service Account User role on the service account"
  if gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
       --member="domain:$DOMAIN" --role="roles/iam.serviceAccountUser" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "granted roles/iam.serviceAccountUser to domain:$DOMAIN on the service account"
  else
    note_fail "could not grant the Service Account User role"
  fi

  info "giving domain:$DOMAIN Compute Instance Admin on the project"
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
       --member="domain:$DOMAIN" --role="roles/compute.instanceAdmin.v1" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "granted roles/compute.instanceAdmin.v1 to domain:$DOMAIN"
  else
    note_fail "could not grant Compute Instance Admin"
  fi

  info "creating the VM $VM_NAME with that service account"
  if instance_exists "$VM_NAME" "$ZONE"; then
    ok "$VM_NAME already exists in $ZONE"
  else
    if gcloud compute instances create "$VM_NAME" \
         --zone="$ZONE" --project "$PROJECT_ID" \
         --machine-type=e2-micro \
         --image-family=debian-12 --image-project=debian-cloud \
         --boot-disk-size=10GB --boot-disk-type=pd-standard \
         --service-account="$SA_EMAIL" \
         --scopes="https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.read_write" \
         --quiet >/dev/null 2>&1; then
      ok "created $VM_NAME running as $SA_EMAIL"
    else
      note_fail "could not create $VM_NAME"
      return 1
    fi
  fi

  pause_for_check 6 "Set up the Service Account User and create a VM"
}

# ---------------------------------------------------------------------------
# Task 7 - explore the Service Account User role
# ---------------------------------------------------------------------------
task7() {
  step "Task 7 - Explore the Service Account User role"

  cat <<EOF

  ${C_BOLD}This part is done inside the VM, where the service account is the${C_RESET}
  ${C_BOLD}identity that acts. Connect with the console's SSH button on${C_RESET}
  ${C_BOLD}$VM_NAME and run:${C_RESET}

    ${C_CYAN}gcloud compute instances list${C_RESET}
      ${C_DIM}-> fails: the service account has no compute.instance.list${C_RESET}

    ${C_CYAN}gcloud storage cp gs://$BUCKET/sample.txt .${C_RESET}
      ${C_DIM}-> works: the service account may read objects${C_RESET}

    ${C_CYAN}mv sample.txt sample2.txt${C_RESET}
    ${C_CYAN}gcloud storage cp sample2.txt gs://$BUCKET${C_RESET}
      ${C_DIM}-> 403: it may read objects, not create them${C_RESET}

EOF

  if [ "$SKIP_ROLE_CHANGE" = "1" ]; then
    dim "  --skip-role-change is set, so the service account keeps roles/storage.objectViewer."
    dim "  To change it, run in the console:"
    dim "    IAM & Admin > Service Accounts > $SA_NAME > Edit > Storage Object Creator"
    return 0
  fi

  info "changing the service account to Storage Object Creator"
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
       --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectCreator" \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the service account can now create objects as well"
    dim "  (it keeps Storage Object Viewer too, so the download still works)"
  else
    note_fail "could not change the service account's role"
  fi

  dim ""
  dim "  Now the upload works too:"
  dim "    gcloud storage cp sample2.txt gs://$BUCKET"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  3) task3 ;;
  4) task4 ;;
  5) task5 ;;
  6) task6 ;;
  7) task7 ;;
  "")
    task3
    task4
    task5
    task6
    task7
    ;;
  *)
    err "--task must be between 3 and 7"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  Username 1       : $MY_ACCOUNT"
echo "  Username 2       : $USER2"
echo "  Bucket           : gs://$BUCKET  (with sample.txt)"
echo "  Service account  : $SA_EMAIL"
echo "  domain:$DOMAIN   : roles/iam.serviceAccountUser on the service account"
echo "                    : roles/compute.instanceAdmin.v1 on the project"
echo "  VM               : $VM_NAME  (e2-micro, runs as the service account)"
echo ""
echo "  Checkpoints:"
echo "    1. Create a bucket and upload a sample file      (25)"
echo "    2. Remove project access                       (25)"
echo "    3. Add storage permissions                      (25)"
echo "    4. Set up the Service Account User and create a VM (25)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
