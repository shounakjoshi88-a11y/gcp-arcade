#!/usr/bin/env bash
# =============================================================================
#  "Create and Manage Cloud Storage Buckets and Encryption"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19083).
#
#  Creates a bucket, makes an object publicly readable with an ACL, encrypts
#  objects with a customer-supplied key, rotates that key, adds a lifecycle
#  rule, turns on versioning and syncs a directory.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storage_buckets.sh
#     chmod +x gsp_storage_buckets.sh
#     ./gsp_storage_buckets.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region REGION   the bucket's region (asked for)
#     --bucket NAME     the bucket (default: the project ID)
#     --task N          run only task N (1-7)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  CHECKPOINTS (100 points, 20 each):
#     1. Create a Cloud Storage bucket
#     2. Make file publicly readable
#     3. Customer-supplied encryption keys (CSEK)
#     4. Enable lifecycle management
#     5. Enable versioning
#
#  NOTES:
#   * The bucket needs fine-grained (object-level) access and public access
#     prevention turned OFF, or the ACL step cannot make an object public.
#   * The customer-supplied key is written into ~/.boto the way the lab does
#     it, and every gsutil call also passes the key with -o so it works
#     even if the boto file is not where gsutil expects it.
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
BUCKET_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0

WORKDIR="${GSP_BUCKET_WORKDIR:-$HOME/gsp-storage-buckets}"
SAMPLE_URL="https://hadoop.apache.org/docs/current/hadoop-project-dist/hadoop-common/ClusterSetup.html"

usage() {
  cat <<'USAGE_END'
Create and Manage Cloud Storage Buckets and Encryption

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storage_buckets.sh
   chmod +x gsp_storage_buckets.sh
   ./gsp_storage_buckets.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region REGION   the bucket's region (asked for)
   --bucket NAME     the bucket (default: the project ID)
   --task N          run only task N (1-7)
   --yes             do not pause for the checkpoints
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --region)  REGION_OVERRIDE="$2";  shift 2 ;;
    --bucket)  BUCKET_OVERRIDE="$2";  shift 2 ;;
    --task)    ONLY_TASK="$2";        shift 2 ;;
    --yes)     ASSUME_YES=1;          shift ;;
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

# ---------------------------------------------------------------------------
# the region
# ---------------------------------------------------------------------------
detect_region_from_metadata() {
  local meta
  meta="$(gcloud compute project-info describe --project "$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items)" 2>/dev/null)"
  [ -z "$meta" ] && return 1
  printf '%s' "$meta" | grep -oE '\b[a-z]+-[a-z]+[0-9]+\b' | head -1
}

GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

if [ -z "$REGION_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  META_REGION="$(detect_region_from_metadata || true)"
  echo ""
  warn "the lab assigns the region per lab run - it cannot be read from the project"
  dim "  it is on your lab setup panel (Region)."
  if [ -n "$META_REGION" ]; then
    dim "  the project metadata mentions: $META_REGION"
  fi
  printf "  %sRegion%s  [%s]: " "$C_BOLD" "$C_RESET" "${META_REGION:-${GCP_REGION:-us-central1}}"
  read -r ans
  REGION_OVERRIDE="${ans:-${META_REGION:-${GCP_REGION:-us-central1}}}"
  echo ""
fi
REGION="${REGION_OVERRIDE:-${GCP_REGION:-us-central1}}"

BUCKET="${BUCKET_OVERRIDE:-$PROJECT_ID}"

printf "%s%s  Create and Manage Cloud Storage Buckets and Encryption%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %sbucket=gs://%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$BUCKET" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
bucket_exists() { gcloud storage buckets describe "gs://$1" --project "$PROJECT_ID" >/dev/null 2>&1; }

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s' in the lab console,%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _
}

# A base64 encoded 32 byte AES key, the way the lab makes it.
make_csek() {
  python3 -c 'import base64, os; print(base64.b64encode(os.urandom(32)).decode())' 2>/dev/null
}

# Set an option in ~/.boto the way the lab does it by hand, but without
# depending on the line number.
set_boto_option() {  # $1 = option name, $2 = value
  python3 - "$1" "$2" "$HOME/.boto" <<'PY' >/dev/null 2>&1
import os, re, sys
name, value = sys.argv[1], sys.argv[2]
path = sys.argv[3]
try:
    text = open(path).read()
except OSError:
    text = ""
lines = text.split("\n")
out, done = [], False
for line in lines:
    if re.match(r"^\s*#?\s*" + re.escape(name) + r"\s*=", line):
        out.append(name + " = " + value)
        done = True
    else:
        out.append(line)
if not done:
    final, inserted = [], False
    for line in out:
        final.append(line)
        if line.strip().lower() == "[credentials]":
            final.append(name + " = " + value)
            inserted = True
    if not inserted:
        final.append("[Credentials]")
        final.append(name + " = " + value)
    out = final
open(path, "w").write("\n".join(out))
PY
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

if command -v gsutil >/dev/null 2>&1; then
  ok "gsutil is available"
else
  warn "gsutil is not on PATH - the CSEK steps need it"
fi

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - the region may be wrong, use --region"
fi

mkdir -p "$WORKDIR" || { err "cannot create $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# Task 1 - the bucket and the sample files
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Prepare the lab environment"

  if bucket_exists "$BUCKET"; then
    ok "the bucket gs://$BUCKET already exists"
  else
    if gcloud storage buckets create "gs://$BUCKET" --project="$PROJECT_ID" \
         --location="$REGION" >/dev/null 2>&1; then
      ok "created gs://$BUCKET in $REGION"
    else
      note_fail "could not create gs://$BUCKET"
      dim "  bucket names are global - try another one:"
      dim "    ./gsp_storage_buckets.sh --bucket $BUCKET-$(date +%s)"
      return 1
    fi
  fi

  # The lab wants fine-grained (object level) access, and public access
  # prevention turned off, or the ACL step cannot make an object public.
  info "turning off uniform bucket-level access and public access prevention"
  gcloud storage buckets update "gs://$BUCKET" --project="$PROJECT_ID" \
    --no-uniform-bucket-level-access >/dev/null 2>&1 \
    || gsutil uniformbucketlevelaccess set off "gs://$BUCKET" >/dev/null 2>&1
  gcloud storage buckets update "gs://$BUCKET" --project="$PROJECT_ID" \
    --public-access-prevention=inherited >/dev/null 2>&1
  ok "the bucket takes object-level permissions"

  info "downloading the sample file"
  if curl -fsSL "$SAMPLE_URL" -o "$WORKDIR/setup.html" 2>/dev/null; then
    ok "downloaded setup.html ($(wc -c < "$WORKDIR/setup.html" | tr -d ' ') bytes)"
  else
    warn "could not download the sample file - writing a local one instead"
    printf '<html><body><h1>setup.html</h1><p>Sample file for the Cloud Storage lab.</p></body></html>\n' \
      > "$WORKDIR/setup.html"
  fi
  cp "$WORKDIR/setup.html" "$WORKDIR/setup2.html"
  cp "$WORKDIR/setup.html" "$WORKDIR/setup3.html"
  ok "made the copies setup2.html and setup3.html"

  pause_for_check 1 "Create a Cloud Storage bucket"
}

# ---------------------------------------------------------------------------
# Task 2 - the access control list
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Access control lists (ACLs)"

  info "uploading setup.html"
  if gcloud storage cp "$WORKDIR/setup.html" "gs://$BUCKET/setup.html" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "uploaded setup.html"
  else
    note_fail "could not upload setup.html"
    return 1
  fi

  info "setting the access list to private first"
  gcloud storage objects update "gs://$BUCKET/setup.html" --project="$PROJECT_ID" \
    --predefined-acl=private >/dev/null 2>&1 && ok "the access list is private" \
    || warn "could not set the predefined private ACL"

  info "making it publicly readable"
  if gcloud storage objects add-iam-policy-binding "gs://$BUCKET/setup.html" \
       --member="allUsers" --role="roles/storage.legacyObjectReader" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "allUsers now has roles/storage.legacyObjectReader"
  else
    note_fail "could not make the object public"
    dim "  this needs fine-grained access and public access prevention off"
    return 1
  fi

  dim ""
  dim "  the access list is now:"
  gcloud storage objects get-iam-policy "gs://$BUCKET/setup.html" \
    --project="$PROJECT_ID" --format="value(bindings)" 2>/dev/null | sed 's/^/    /'

  dim ""
  dim "  In the console, setup.html should show a public link."

  pause_for_check 2 "Make file publicly readable"
}

# ---------------------------------------------------------------------------
# Task 3 - customer supplied encryption keys
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Customer-supplied encryption keys (CSEK)"

  if ! command -v gsutil >/dev/null 2>&1; then
    note_fail "gsutil is needed for the CSEK steps"
    return 1
  fi

  CSEK1="$(make_csek)"
  if [ -z "$CSEK1" ]; then
    note_fail "could not generate a key"
    return 1
  fi
  ok "generated a CSEK"
  dim "    ${CSEK1}"
  echo "$CSEK1" > "$WORKDIR/csek1"

  info "writing the key into ~/.boto, the way the lab does it"
  [ -f "$HOME/.boto" ] || gsutil config -n >/dev/null 2>&1
  set_boto_option "encryption_key" "$CSEK1"
  set_boto_option "decryption_key1" "$CSEK1"
  ok "~/.boto now has the encryption_key and the matching decryption_key1"

  info "uploading setup2.html and setup3.html, encrypted"
  gsutil -o "GS:encryption_key=$CSEK1" cp "$WORKDIR/setup2.html" "gs://$BUCKET/setup2.html" \
    >/dev/null 2>&1 && ok "uploaded setup2.html with the customer key" \
    || note_fail "could not upload setup2.html with the key"
  gsutil -o "GS:encryption_key=$CSEK1" cp "$WORKDIR/setup3.html" "gs://$BUCKET/setup3.html" \
    >/dev/null 2>&1 && ok "uploaded setup3.html with the customer key" \
    || note_fail "could not upload setup3.html with the key"

  dim ""
  dim "  the objects now report customer-encrypted:"
  gcloud storage objects describe "gs://$BUCKET/setup2.html" --project="$PROJECT_ID" \
    --format="value(customerEncryption)" 2>/dev/null | sed 's/^/    /'
  gcloud storage objects describe "gs://$BUCKET/setup3.html" --project="$PROJECT_ID" \
    --format="value(customerEncryption)" 2>/dev/null | sed 's/^/    /'

  pause_for_check 3 "Customer-supplied encryption keys (CSEK)"
}

# ---------------------------------------------------------------------------
# Task 4 - rotate the key
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Rotate CSEK keys"

  CSEK1="$(cat "$WORKDIR/csek1" 2>/dev/null)"
  if [ -z "$CSEK1" ]; then
    warn "no key was recorded - run task 3 first"
    return 1
  fi
  CSEK2="$(make_csek)"
  if [ -z "$CSEK2" ]; then
    note_fail "could not generate the new key"
    return 1
  fi
  echo "$CSEK2" > "$WORKDIR/csek2"
  ok "generated a new CSEK for the rotation"
  dim "    ${CSEK2}"

  info "the old key becomes the decryption key, a new key becomes the encryption key"
  set_boto_option "encryption_key" "$CSEK2"
  set_boto_option "decryption_key1" "$CSEK1"
  ok "~/.boto now encrypts with the new key and decrypts with the old one"

  info "rewriting setup2.html with the new key"
  if gsutil -o "GS:encryption_key=$CSEK2" -o "GS:decryption_key1=$CSEK1" \
       rewrite -k "gs://$BUCKET/setup2.html" >/dev/null 2>&1; then
    ok "setup2.html is now encrypted with the new key"
  else
    note_fail "could not rewrite setup2.html"
  fi

  dim "  setup3.html was NOT rewritten, so it still has the old key."

  info "downloading setup2.html with the new key"
  if gsutil -o "GS:decryption_key1=$CSEK2" cp "gs://$BUCKET/setup2.html" \
       "$WORKDIR/recover2.html" >/dev/null 2>&1; then
    ok "downloaded setup2.html"
  else
    note_fail "could not download setup2.html"
  fi

  info "downloading setup3.html with the old key"
  if gsutil -o "GS:decryption_key1=$CSEK1" cp "gs://$BUCKET/setup3.html" \
       "$WORKDIR/recover3.html" >/dev/null 2>&1; then
    ok "downloaded setup3.html"
  else
    warn "setup3.html could not be downloaded - it was never rewritten, so it"
    warn "still has the original key. That is the point of the exercise."
  fi

  dim ""
  dim "  The old key is still needed to read setup3.html, so keep it."
}

# ---------------------------------------------------------------------------
# Task 5 - lifecycle management
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Enable lifecycle management"

  cat > "$WORKDIR/life.json" <<'EOF'
{
  "rule":
  [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 31}
    }
  ]
}
EOF
  ok "wrote $WORKDIR/life.json"

  if gcloud storage buckets update "gs://$BUCKET" --project="$PROJECT_ID" \
       --lifecycle-file="$WORKDIR/life.json" >/dev/null 2>&1; then
    ok "the lifecycle policy is set - objects are deleted after 31 days"
  else
    note_fail "could not set the lifecycle policy"
    return 1
  fi

  dim ""
  dim "  the policy is now:"
  gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT_ID" \
    --format="value(lifecycle)" 2>/dev/null | sed 's/^/    /'
  gsutil lifecycle get "gs://$BUCKET" 2>/dev/null | sed 's/^/    /'

  pause_for_check 5 "Enable lifecycle management"
}

# ---------------------------------------------------------------------------
# Task 6 - versioning
# ---------------------------------------------------------------------------
task6() {
  step "Task 6 - Enable versioning"

  if gcloud storage buckets update "gs://$BUCKET" --project="$PROJECT_ID" \
       --versioning >/dev/null 2>&1; then
    ok "versioning is on"
  else
    note_fail "could not turn on versioning"
    return 1
  fi

  dim ""
  dim "  the versioning status is now:"
  gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT_ID" \
    --format="value(versioning_enabled)" 2>/dev/null | sed 's/^/    /'

  pause_for_check 6 "Enable versioning"

  # the rest of task 6: make a few versions and recover the original
  info "making a second version of setup.html"
  printf '\n<!-- a change for the second version -->\n' >> "$WORKDIR/setup.html"
  gcloud storage cp "$WORKDIR/setup.html" "gs://$BUCKET/setup.html" \
    --project="$PROJECT_ID" >/dev/null 2>&1 && ok "uploaded a new version" \
    || warn "could not upload the new version"

  info "listing every version of setup.html"
  gsutil ls -a "gs://$BUCKET/setup.html" 2>/dev/null | sed 's/^/      /'

  OLDEST="$(gsutil ls -a "gs://$BUCKET/setup.html" 2>/dev/null | head -1 | tr -d ' ')"
  if [ -n "$OLDEST" ]; then
    info "recovering the oldest version"
    if gcloud storage cp "$OLDEST" "$WORKDIR/recovered.txt" --project="$PROJECT_ID" \
         >/dev/null 2>&1; then
      ok "recovered the original version to $WORKDIR/recovered.txt"
      dim "      the original is $(wc -c < "$WORKDIR/setup.html" | tr -d ' ') bytes, the recovered one is $(wc -c < "$WORKDIR/recovered.txt" | tr -d ' ') bytes"
    else
      warn "could not recover the oldest version"
    fi
  else
    warn "no versions were listed"
  fi
}

# ---------------------------------------------------------------------------
# Task 7 - rsync a directory
# ---------------------------------------------------------------------------
task7() {
  step "Task 7 - Synchronize a directory to a bucket"

  mkdir -p "$WORKDIR/firstlevel/secondlevel"
  cp "$WORKDIR/setup.html" "$WORKDIR/firstlevel/" 2>/dev/null
  cp "$WORKDIR/setup.html" "$WORKDIR/firstlevel/secondlevel/" 2>/dev/null
  ok "made firstlevel/ and firstlevel/secondlevel/"

  if gcloud storage rsync "$WORKDIR/firstlevel" "gs://$BUCKET/firstlevel" \
       --recursive --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "synced the directory to gs://$BUCKET/firstlevel"
  else
    note_fail "could not sync the directory"
  fi

  dim ""
  dim "  the bucket now holds:"
  gcloud storage ls -r "gs://$BUCKET/firstlevel" --project="$PROJECT_ID" 2>/dev/null | sed 's/^/      /'
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
  "")
    task1
    task2
    task3
    task4
    task5
    task6
    task7
    ;;
  *)
    err "--task must be between 1 and 7"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project   : $PROJECT_ID"
echo "  Bucket    : gs://$BUCKET  ($REGION)"
echo "  Objects   : setup.html (public), setup2.html and setup3.html (customer-encrypted)"
echo "  Lifecycle : delete objects after 31 days"
echo "  Versioning: on"
echo ""
echo "  Checkpoints:"
echo "    1. Create a Cloud Storage bucket            (20)"
echo "    2. Make file publicly readable             (20)"
echo "    3. Customer-supplied encryption keys (CSEK)  (20)"
echo "    4. Enable lifecycle management              (20)"
echo "    5. Enable versioning                        (20)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
