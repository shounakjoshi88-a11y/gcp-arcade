#!/usr/bin/env bash
# =============================================================================
#  "Explore the Google Cloud Console and Cloud Shell"
#  Google Cloud Arcade / Cloud Skills Boost lab.
#
#  Creates the two buckets the lab asks for, uploads a file into them, and
#  sets up the persistent environment variables the lab demonstrates in task 5.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_console_shell.sh
#     chmod +x gsp_console_shell.sh
#     ./gsp_console_shell.sh
#
#  OPTIONS:
#     --project ID       GCP project (default: active gcloud project)
#     --console-bucket N name for the bucket you create in the console
#     --cli-bucket N     name for the bucket created from the command line
#     --region R         region stored in INFRACLASS_REGION
#     --file PATH        file to upload (default: a new ~/my-file.txt)
#     --task N           run only task N (1-5)
#     --yes              do not pause for the checkpoints
#     -h, --help         this help
#
#  NOTES:
#   * Task 1 has to be done in the Cloud console, not from the shell - the
#     lab grades the bucket as a *console* creation. The script prints the
#     bucket name and a pre-filled console link, then waits for you.
#   * Do NOT close the Cloud Shell terminal while this script is running.
#     The lab's task 2 asks you to close and reopen Cloud Shell, but that
#     resets the VM and would kill the script mid-run. Task 2 has no
#     checkpoint, so skipping it costs nothing.
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
CONSOLE_BUCKET_OVERRIDE=""
CLI_BUCKET_OVERRIDE=""
REGION_OVERRIDE=""
UPLOAD_FILE=""
ONLY_TASK=""
ASSUME_YES=0

usage() {
  cat <<'USAGE_END'
Explore the Google Cloud Console and Cloud Shell

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_console_shell.sh
   chmod +x gsp_console_shell.sh
   ./gsp_console_shell.sh

OPTIONS:
   --project ID       GCP project (default: active gcloud project)
   --console-bucket N name for the bucket you create in the console
   --cli-bucket N     name for the bucket created from the command line
   --region R         region stored in INFRACLASS_REGION
   --file PATH        file to upload (default: a new ~/my-file.txt)
   --task N           run only task N (1-5)
   --yes              do not pause for the checkpoints
   -h, --help         this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)        PROJECT_OVERRIDE="$2";        shift 2 ;;
    --console-bucket) CONSOLE_BUCKET_OVERRIDE="$2"; shift 2 ;;
    --cli-bucket)     CLI_BUCKET_OVERRIDE="$2";     shift 2 ;;
    --region)         REGION_OVERRIDE="$2";         shift 2 ;;
    --file)           UPLOAD_FILE="$2";             shift 2 ;;
    --task)           ONLY_TASK="$2";               shift 2 ;;
    --yes)            ASSUME_YES=1;                 shift ;;
    -h|--help)        usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve the project
# ---------------------------------------------------------------------------
PROJECT_ID="$PROJECT_OVERRIDE"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
fi
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
# helpers
# ---------------------------------------------------------------------------
list_buckets() {
  gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null
}

bucket_exists() {
  gcloud storage buckets describe "gs://$1" --project="$PROJECT_ID" >/dev/null 2>&1
}

create_bucket() {
  if gcloud storage buckets create "gs://$1" --project="$PROJECT_ID" >/dev/null 2>&1; then
    return 0
  fi
  if command -v gsutil >/dev/null 2>&1; then
    gsutil mb -p "$PROJECT_ID" "gs://$1" >/dev/null 2>&1 && return 0
  fi
  return 1
}

upload_to_bucket() {
  if gcloud storage cp "$1" "gs://$2" --project="$PROJECT_ID" >/dev/null 2>&1; then
    return 0
  fi
  if command -v gsutil >/dev/null 2>&1; then
    gsutil cp "$1" "gs://$2" >/dev/null 2>&1 && return 0
  fi
  return 1
}

bucket_has_object() {
  gcloud storage ls "gs://$1" --project="$PROJECT_ID" 2>/dev/null | grep -q .
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

wait_for_enter() {  # $1 = prompt
  printf "  %s%s%s\n" "$C_YELLOW" "$1" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

# ---------------------------------------------------------------------------
# names
# ---------------------------------------------------------------------------
CONSOLE_BUCKET="${CONSOLE_BUCKET_OVERRIDE:-$PROJECT_ID}"
CLI_BUCKET="${CLI_BUCKET_OVERRIDE:-${CONSOLE_BUCKET}-2}"
REGION="$REGION_OVERRIDE"
FILE_TO_UPLOAD="$UPLOAD_FILE"

printf "%s%s  Explore the Google Cloud Console and Cloud Shell%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sconsole-bucket=%s  %scli-bucket=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$CONSOLE_BUCKET" "$C_DIM" "$CLI_BUCKET" "$C_RESET"

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
  warn "not in Cloud Shell - the console link and the shell steps assume it"
fi

EXISTING_BUCKETS="$(list_buckets)"
if [ -n "$EXISTING_BUCKETS" ]; then
  info "buckets already in the project:"
  printf "%s\n" "$EXISTING_BUCKETS" | sed 's/^/      /'
else
  info "the project has no buckets yet"
fi

# ---------------------------------------------------------------------------
# Task 1 - create a bucket using the Cloud console
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Create a bucket using the Cloud console"

  if bucket_exists "$CONSOLE_BUCKET"; then
    ok "the bucket $CONSOLE_BUCKET already exists - nothing to click"
  else
    cat <<EOF

  ${C_BOLD}This one has to be done in the console, not from the shell.${C_RESET}
  ${C_DIM}The lab grades it as a *console* creation, so the script cannot do it for you.${C_RESET}

  1. Open this link (it is pre-filled with your project):
       ${C_CYAN}https://console.cloud.google.com/storage/create-bucket?project=${PROJECT_ID}${C_RESET}
  2. For ${C_BOLD}Name${C_RESET}, type exactly:
       ${C_BOLD}${CONSOLE_BUCKET}${C_RESET}
  3. Leave every other value as it is and click ${C_BOLD}Create${C_RESET}.
  4. If it says ${C_BOLD}Public access will be prevented${C_RESET}, click ${C_BOLD}Confirm${C_RESET}.
  5. Come back here and press Enter.

EOF
    wait_for_enter "Create the bucket in the console, then press Enter here."
  fi

  if bucket_exists "$CONSOLE_BUCKET"; then
    ok "the bucket $CONSOLE_BUCKET exists"
  else
    note_fail "the bucket $CONSOLE_BUCKET was not found"
    dim "  if the console said the name is taken, retry with a different one:"
    dim "    ./gsp_console_shell.sh --console-bucket ${CONSOLE_BUCKET}-$(date +%s)"
  fi

  pause_for_check 1 "Create a bucket using the GCP Console"
}

# ---------------------------------------------------------------------------
# Task 2 - access Cloud Shell
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Access Cloud Shell"

  info "you are already in Cloud Shell - this script is running inside it"
  dim "    \$ gcloud config list project"
  gcloud config list project 2>/dev/null | sed 's/^/      /'
  dim "    \$ echo \$DEVSHELL_PROJECT_ID"
  printf "      %s\n" "${DEVSHELL_PROJECT_ID:-$PROJECT_ID}"

  cat <<EOF

  ${C_DIM}The lab asks you to close Cloud Shell here. Do not do that while this${C_RESET}
  ${C_DIM}script is running - closing Cloud Shell resets the VM and kills the${C_RESET}
  ${C_DIM}script. Task 2 has no checkpoint, so close it afterwards instead.${C_RESET}

EOF
  ok "Cloud Shell is active and authenticated"
}

# ---------------------------------------------------------------------------
# Task 3 - create a bucket using Cloud Shell
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Use Cloud Shell to create a Cloud Storage bucket"

  if bucket_exists "$CLI_BUCKET"; then
    ok "the bucket $CLI_BUCKET already exists"
  else
    info "creating gs://$CLI_BUCKET"
    if create_bucket "$CLI_BUCKET"; then
      ok "created gs://$CLI_BUCKET"
    else
      note_fail "could not create gs://$CLI_BUCKET"
      dim "  the name has to be globally unique. Try another one:"
      dim "    ./gsp_console_shell.sh --cli-bucket ${CLI_BUCKET}-$(date +%s)"
      return 1
    fi
  fi

  dim "    \$ gcloud storage buckets list"
  list_buckets | sed 's/^/      /'

  pause_for_check 3 "Create a bucket using Cloud Shell"
}

# ---------------------------------------------------------------------------
# Task 4 - upload a file to a storage bucket
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Upload a file to Storage bucket"

  if [ -z "$FILE_TO_UPLOAD" ]; then
    FILE_TO_UPLOAD="$HOME/my-file.txt"
    cat > "$FILE_TO_UPLOAD" <<EOF
Hello from Google Cloud Shell.
This file was uploaded to Cloud Storage by gsp_console_shell.sh.
Project: $PROJECT_ID
EOF
    ok "created $FILE_TO_UPLOAD"
  elif [ -f "$FILE_TO_UPLOAD" ]; then
    ok "using the existing file $FILE_TO_UPLOAD"
  else
    note_fail "the file $FILE_TO_UPLOAD does not exist"
    return 1
  fi

  local target
  for target in "$CLI_BUCKET" "$CONSOLE_BUCKET"; do
    if ! bucket_exists "$target"; then
      warn "skipping $target - the bucket does not exist"
      continue
    fi
    if upload_to_bucket "$FILE_TO_UPLOAD" "$target"; then
      ok "copied $(basename "$FILE_TO_UPLOAD") to gs://$target"
    else
      note_fail "could not copy the file to gs://$target"
    fi
  done

  for target in "$CLI_BUCKET" "$CONSOLE_BUCKET"; do
    if bucket_exists "$target" && bucket_has_object "$target"; then
      ok "gs://$target holds:"
      gcloud storage ls "gs://$target" --project="$PROJECT_ID" 2>/dev/null | sed 's/^/      /'
    fi
  done

  pause_for_check 4 "Upload a file to Storage bucket"
}

# ---------------------------------------------------------------------------
# Task 5 - persistent state in Cloud Shell
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Create a persistent state in Cloud Shell"

  if [ -z "$REGION" ]; then
    REGION="$(gcloud compute regions list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | head -1)"
    if [ -z "$REGION" ]; then
      REGION="us-central1"
      warn "could not list the regions, falling back to $REGION"
    fi
  fi
  ok "region: $REGION"

  mkdir -p "$HOME/infraclass"
  CONFIG="$HOME/infraclass/config"

  # the config file is rewritten from scratch so a re-run never duplicates lines
  {
    echo "INFRACLASS_REGION=$REGION"
    echo "INFRACLASS_PROJECT_ID=$PROJECT_ID"
  } > "$CONFIG"
  ok "wrote $CONFIG"
  dim "      INFRACLASS_REGION=$REGION"
  dim "      INFRACLASS_PROJECT_ID=$PROJECT_ID"

  # export them into this session too
  export INFRACLASS_REGION="$REGION"
  export INFRACLASS_PROJECT_ID="$PROJECT_ID"
  dim "    \$ echo \$INFRACLASS_PROJECT_ID"
  printf "      %s\n" "$INFRACLASS_PROJECT_ID"

  # make the shell pick them up automatically on every new Cloud Shell session
  PROFILE="$HOME/.profile"
  SOURCE_LINE="source \"\$HOME/infraclass/config\""
  if [ -f "$PROFILE" ] && grep -q "infraclass/config" "$PROFILE"; then
    ok "$PROFILE already sources infraclass/config"
  else
    {
      echo ""
      echo "# added by gsp_console_shell.sh - persistent lab environment"
      echo "$SOURCE_LINE"
    } >> "$PROFILE"
    ok "added 'source \$HOME/infraclass/config' to $PROFILE"
  fi

  # prove it survives a fresh shell, the way the lab checks it
  echo ""
  dim "    simulating a fresh Cloud Shell session:"
  OUT="$(bash -lc 'echo "$INFRACLASS_PROJECT_ID"' 2>/dev/null)"
  if [ "$OUT" = "$PROJECT_ID" ]; then
    ok "a new login shell still has INFRACLASS_PROJECT_ID=$OUT"
  else
    warn "the new shell printed '$OUT' instead of $PROJECT_ID"
  fi
  OUT2="$(bash -c 'echo "$INFRACLASS_PROJECT_ID"' 2>/dev/null)"
  if [ -z "$OUT2" ]; then
    dim "      (a plain shell without a login does not read .profile - that is expected)"
  fi
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
echo "  Project        : $PROJECT_ID"
echo "  Console bucket : gs://$CONSOLE_BUCKET"
echo "  CLI bucket     : gs://$CLI_BUCKET"
echo "  Config file    : $HOME/infraclass/config"
echo "  Profile        : $HOME/.profile"
echo ""
echo "  Checkpoints:"
echo "    1. Create a bucket using the GCP Console   (30)"
echo "    2. Create a bucket using Cloud Shell        (30)"
echo "    3. Upload a file to Storage bucket          (40)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
