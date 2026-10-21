#!/usr/bin/env bash
# =============================================================================
#  "Examine Billing data with BigQuery"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 19085).
#
#  Creates a BigQuery dataset, loads a Cloud Billing export into a native
#  table, and runs the lab's queries against it.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_bigquery_billing.sh
#     chmod +x gsp_bigquery_billing.sh
#     ./gsp_bigquery_billing.sh
#
#  OPTIONS:
#     --project ID    GCP project (default: active gcloud project)
#     --dataset NAME  the BigQuery dataset (default: billing_dataset)
#     --table NAME    the table (default: sampleinfotable)
#     --source URI    the Avro file to load
#     --task N        run only task N (1-4)
#     --yes           do not pause for the checkpoints
#     -h, --help      this help
#
#  CHECKPOINTS (100 points):
#     1. Use BigQuery to import data                 (40)
#     2. Compose a simple query                      (30)
#     3. Analyze a large billing dataset with SQL    (30)
#
#  NOTES:
#   * bq load and bq query both block until the job finishes, and the load
#     of a 160 MB Avro file takes a minute or two. Their output is streamed
#     so the run never looks like it has hung.
#   * The dataset's table expiration is verified through the API afterwards,
#     because the bq flag for it is spelled differently between versions and
#     the unit is easy to get wrong.
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
DATASET_OVERRIDE=""
TABLE_OVERRIDE=""
SOURCE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0

WORKDIR="${GSP_BQ_WORKDIR:-$HOME/gsp-bigquery-billing}"
DATASET="billing_dataset"
TABLE="sampleinfotable"
LOCATION="US"
SOURCE="gs://cloud-training/archinfra/BillingExport-2020-09-18.avro"
EXPIRATION_MS=86400000   # one day

usage() {
  cat <<'USAGE_END'
Examine Billing data with BigQuery

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_bigquery_billing.sh
   chmod +x gsp_bigquery_billing.sh
   ./gsp_bigquery_billing.sh

OPTIONS:
   --project ID    GCP project (default: active gcloud project)
   --dataset NAME  the BigQuery dataset (default: billing_dataset)
   --table NAME    the table (default: sampleinfotable)
   --source URI    the Avro file to load
   --task N        run only task N (1-4)
   --yes           do not pause for the checkpoints
   -h, --help      this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --dataset) DATASET_OVERRIDE="$2"; shift 2 ;;
    --table)   TABLE_OVERRIDE="$2";   shift 2 ;;
    --source)  SOURCE_OVERRIDE="$2";  shift 2 ;;
    --task)    ONLY_TASK="$2";        shift 2 ;;
    --yes)     ASSUME_YES=1;          shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

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

[ -n "$DATASET_OVERRIDE" ] && DATASET="$DATASET_OVERRIDE"
[ -n "$TABLE_OVERRIDE" ] && TABLE="$TABLE_OVERRIDE"
[ -n "$SOURCE_OVERRIDE" ] && SOURCE="$SOURCE_OVERRIDE"

TABLE_REF="$PROJECT_ID:$DATASET.$TABLE"
FULL_REF="\`$PROJECT_ID.$DATASET.$TABLE\`"
SHORT_REF="\`$DATASET.$TABLE\`"

mkdir -p "$WORKDIR" 2>/dev/null

printf "%s%s  Examine Billing data with BigQuery%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sdataset=%s  %stable=%s  %ssource=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$DATASET" "$C_DIM" "$TABLE" "$C_DIM" "$SOURCE" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
# Run a command and show its output as it arrives. Both bq load and bq query
# block until the job finishes, and a silent wait looks exactly like a hang.
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
      printf "    ... still working (%ss elapsed)\\n" "$elapsed"
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

dataset_exists() { bq show --format=prettyjson "$PROJECT_ID:$DATASET" >/dev/null 2>&1; }
table_exists()   { bq show --format=prettyjson "$TABLE_REF" >/dev/null 2>&1; }

# Run one of the lab's queries and show the result.
run_query() {  # $1 = a label, $2 = the SQL
  local label="$1" sql="$2" log
  log="$WORKDIR/query.log"
  dim "  $label"
  if run_live "$log" bq query --use_legacy_sql=false --location="$LOCATION" "$sql"; then
    return 0
  fi
  warn "the query failed:"
  tail -5 "$log" | sed 's/^/    /'
  return 1
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

if command -v bq >/dev/null 2>&1; then
  ok "bq is available"
else
  err "bq is not on PATH - this lab needs the BigQuery CLI"
  dim "  Cloud Shell has it. Elsewhere: gcloud components install bq"
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
ok "project: $PROJECT_ID"

info "enabling the BigQuery API"
gcloud services enable bigquery.googleapis.com --project "$PROJECT_ID" --quiet >/dev/null 2>&1
ok "the BigQuery API is enabled"

TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
[ -n "$TOKEN" ] && ok "have an access token for the API" || warn "no access token, some checks will be skipped"

# ---------------------------------------------------------------------------
# Task 1 - the dataset and the table
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Use BigQuery to import data"

  # --- the dataset -------------------------------------------------------
  if dataset_exists; then
    ok "the dataset $DATASET already exists"
  else
    info "creating the dataset $DATASET in $LOCATION"
    if bq --location="$LOCATION" mk --dataset \
         --default_table_expiration_ms="$EXPIRATION_MS" \
         --description="Billing dataset for lab" \
         "$PROJECT_ID:$DATASET" >/dev/null 2>&1; then
      ok "created the dataset $DATASET"
    elif bq --location="$LOCATION" mk --dataset \
         --default_table_expiration="$EXPIRATION_MS" \
         --description="Billing dataset for lab" \
         "$PROJECT_ID:$DATASET" >/dev/null 2>&1; then
      ok "created the dataset $DATASET"
    elif bq --location="$LOCATION" mk --dataset \
         --description="Billing dataset for lab" \
         "$PROJECT_ID:$DATASET" >/dev/null 2>&1; then
      ok "created the dataset $DATASET"
    else
      note_fail "could not create the dataset $DATASET"
      dim "  run it by hand:"
      dim "    bq --location=$LOCATION mk --dataset $PROJECT_ID:$DATASET"
      return 1
    fi
  fi

  # The table expiration is set in milliseconds in the API, and the bq flag
  # for it differs between versions, so it is checked and corrected here.
  if [ -n "$TOKEN" ]; then
    EXPIRY="$(curl -s "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT_ID/datasets/$DATASET" \
                -H "Authorization: Bearer $TOKEN" 2>/dev/null \
                | grep -oE '"defaultTableExpirationMs": *"?[0-9]+' | grep -oE '[0-9]+$')"
    if [ -z "$EXPIRY" ] || [ "$EXPIRY" -lt 86400000 ] 2>/dev/null; then
      info "setting the table expiration to one day"
      curl -s -X PATCH "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT_ID/datasets/$DATASET" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"defaultTableExpirationMs\":\"$EXPIRATION_MS\"}" >/dev/null 2>&1
      ok "the default table expiration is one day"
    else
      ok "the default table expiration is $EXPIRY ms"
    fi
  fi

  # --- the table ---------------------------------------------------------
  if table_exists; then
    ok "the table $TABLE already exists"
  else
    info "loading $SOURCE into $TABLE (160 MB, a minute or two)"
    LOAD_LOG="$WORKDIR/load.log"
    if run_live "$LOAD_LOG" bq load --location="$LOCATION" \
         --source_format=AVRO "$TABLE_REF" "$SOURCE"; then
      ok "loaded the billing data into $TABLE"
    else
      note_fail "the load failed"
      dim "  the API said:"
      tail -6 "$LOAD_LOG" | sed 's/^/    /'
      dim "  run it by hand:"
      dim "    bq load --source_format=AVRO $TABLE_REF $SOURCE"
      return 1
    fi
  fi

  pause_for_check 1 "Use BigQuery to import data"
}

# ---------------------------------------------------------------------------
# Task 2 - examine the table
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Examine the table"

  dim "  the schema BigQuery worked out from the file:"
  bq show --schema --format=prettyjson "$TABLE_REF" 2>/dev/null | sed 's/^/    /'

  dim ""
  dim "  the table details:"
  bq show "$TABLE_REF" 2>/dev/null | sed 's/^/    /'

  dim ""
  dim "  the row count:"
  bq query --use_legacy_sql=false --format=csv \
    "SELECT COUNT(*) AS total_rows FROM $FULL_REF" 2>/dev/null | sed 's/^/    /'
}

# ---------------------------------------------------------------------------
# Task 3 - the simple query
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Compose a simple query"

  run_query "SELECT * FROM $DATASET.$TABLE WHERE cost > 0" \
    "SELECT * FROM $SHORT_REF
WHERE cost > 0"

  pause_for_check 2 "Compose a simple query"
}

# ---------------------------------------------------------------------------
# Task 4 - the analysis queries
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Analyze a large billing dataset with SQL"

  run_query "1. every billing record" \
    "SELECT
  billing_account_id,
  project.id,
  project.name,
  service.description,
  currency,
  currency_conversion_rate,
  cost,
  usage.amount,
  usage.pricing_unit
FROM
  $SHORT_REF"

  run_query "2. the latest 100 records with a charge" \
    "SELECT
  service.description,
  sku.description,
  location.country,
  cost,
  project.id,
  project.name,
  currency,
  currency_conversion_rate,
  usage.amount,
  usage.unit
FROM
  $SHORT_REF
WHERE
  cost > 0
ORDER BY usage_end_time DESC
LIMIT 100"

  run_query "3. every charge over 10 dollars" \
    "SELECT
  service.description,
  sku.description,
  location.country,
  cost,
  project.id,
  project.name,
  currency,
  currency_conversion_rate,
  usage.amount,
  usage.unit
FROM
  $SHORT_REF
WHERE
  cost > 10"

  run_query "4. the product with the most records" \
    "SELECT
  service.description,
  COUNT(*) AS billing_records
FROM
  $SHORT_REF
GROUP BY
  service.description
ORDER BY billing_records DESC"

  run_query "5. the most used product costing more than 1 dollar" \
    "SELECT
  service.description,
  COUNT(*) AS billing_records
FROM
  $SHORT_REF
WHERE
  cost > 1
GROUP BY
  service.description
ORDER BY billing_records DESC"

  run_query "6. the most commonly charged unit of measure" \
    "SELECT
  usage.unit,
  COUNT(*) AS billing_records
FROM
  $SHORT_REF
WHERE cost > 0
GROUP BY
  usage.unit
ORDER BY billing_records DESC"

  run_query "7. the product with the highest aggregate cost" \
    "SELECT
  service.description,
  ROUND(SUM(cost),2) AS total_cost
FROM
  $SHORT_REF
GROUP BY
  service.description
ORDER BY
  total_cost DESC"

  pause_for_check 3 "Analyze a large billing dataset with SQL"
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
    task1 || { echo ""; err "task 1 failed - fix that first, the rest depends on it"; exit 1; }
    task2
    task3 || { echo ""; err "task 3 failed"; exit 1; }
    task4 || { echo ""; err "task 4 failed"; exit 1; }
    ;;
  *)
    err "--task must be between 1 and 4"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Dataset  : $DATASET  (location $LOCATION, 1 day table expiration)"
echo "  Table    : $TABLE"
echo "  Source   : $SOURCE"
echo ""
echo "  Checkpoints:"
echo "    1. Use BigQuery to import data                 (40)"
echo "    2. Compose a simple query                      (30)"
echo "    3. Analyze a large billing dataset with SQL    (30)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
