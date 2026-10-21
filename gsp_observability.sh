#!/usr/bin/env bash
# =============================================================================
#  "Monitor Resources with Google Cloud Observability"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 45797).
#
#  Creates a custom dashboard, an alert policy with two conditions, a
#  resource group, and an uptime check in Cloud Monitoring.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_observability.sh
#     chmod +x gsp_observability.sh
#     ./gsp_observability.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --email EMAIL     the address for the notification channel
#     --zone ZONE       the zone of the lab's VMs (detected)
#     --task N          run only task N (2-6)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  CHECKPOINTS (100 points, 25 each):
#     1. Create custom dashboard
#     2. Create alerting policies
#     3. Create Resource Group
#     4. Create uptime check
#
#  NOTES:
#   * The dashboard has to use a gridLayout. A dashboard created with any
#     other layout does not score, and the console form does not say so.
#   * The resource group has to actually MATCH the lab's nginxstack VMs. A
#     group with a plausible looking filter and no members does not score
#     either, so the script creates the group and then checks the member
#     list, trying other filter forms until it matches.
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
EMAIL_OVERRIDE=""
ZONE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0

WORKDIR="${GSP_OBS_WORKDIR:-$HOME/gsp-observability}"
DASHBOARD_NAME="My Dashboard"
POLICY_NAME="My Alert Policy"
GROUP_NAME="VM instances"
UPTIME_NAME="My Uptime check"
CHANNEL_DISPLAY="Lab Notification Channel"
API="${OBS_API:-https://monitoring.googleapis.com}"

usage() {
  cat <<'USAGE_END'
Monitor Resources with Google Cloud Observability

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_observability.sh
   chmod +x gsp_observability.sh
   ./gsp_observability.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --email EMAIL     the address for the notification channel
   --zone ZONE       the zone of the lab's VMs (detected)
   --task N          run only task N (2-6)
   --yes             do not pause for the checkpoints
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --email)   EMAIL_OVERRIDE="$2";   shift 2 ;;
    --zone)    ZONE_OVERRIDE="$2";    shift 2 ;;
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

MY_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
[ "$MY_ACCOUNT" = "(unset)" ] && MY_ACCOUNT=""

# the lab's VMs, and the zone they are in
ALL_VMS="$(gcloud compute instances list --project "$PROJECT_ID" \
             --format="value(name,zone)" 2>/dev/null)"
LAB_VMS="$(echo "$ALL_VMS" | awk '$1 ~ /nginxstack/ { print $1 }')"
DETECTED_ZONE="$(echo "$ALL_VMS" | awk '$1 ~ /nginxstack/ { print $2 }' | head -1 | sed 's|.*/||')"
[ -z "$ZONE_OVERRIDE" ] && ZONE_OVERRIDE="$DETECTED_ZONE"
ZONE="${ZONE_OVERRIDE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
[ "$ZONE" = "(unset)" ] && ZONE=""

if [ -z "$EMAIL_OVERRIDE" ] && [ "$ASSUME_YES" != "1" ]; then
  echo ""
  warn "the lab asks for an email address for the notification channel"
  dim "  the channel only has to exist, it does not have to be reachable"
  printf "  %sEmail%s  [%s]: " "$C_BOLD" "$C_RESET" "${MY_ACCOUNT:-student@qwiklabs.net}"
  read -r ans
  EMAIL_OVERRIDE="${ans:-${MY_ACCOUNT:-student@qwiklabs.net}}"
  echo ""
fi
EMAIL="${EMAIL_OVERRIDE:-${MY_ACCOUNT:-student@qwiklabs.net}}"

mkdir -p "$WORKDIR" 2>/dev/null

printf "%s%s  Monitor Resources with Google Cloud Observability%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %semail=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$EMAIL" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
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

# the members of a group
group_members() {  # $1 = the full group name
  curl -s -H "Authorization: Bearer $TOKEN" "$API/v3/$1/members" 2>/dev/null
}

# escape a string for use inside a json string value
json_escape() {  # $1 = a string
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# json value out of a json blob, without needing jq
json_str() {  # $1 = json, $2 = key
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
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

info "enabling the Monitoring and Compute APIs"
gcloud services enable monitoring.googleapis.com compute.googleapis.com \
  --project "$PROJECT_ID" --quiet >/dev/null 2>&1
ok "the APIs are enabled"

TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
if [ -z "$TOKEN" ]; then
  err "no access token - run this in Cloud Shell with your lab account"
  exit 1
fi
ok "have an access token"

# ---------------------------------------------------------------------------
# Task 1 - the resources
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Verify the resources"

  if [ -n "$LAB_VMS" ]; then
    ok "the lab's VMs are there:"
    echo "$LAB_VMS" | sed 's/^/      /'
  else
    warn "no instance whose name contains 'nginxstack' was found"
    dim "  the lab creates nginxstack-1, nginxstack-2 and nginxstack-3"
    dim "  the resource group and the uptime check need them, so wait a minute"
    dim "  and re-run if they are still not there"
  fi
  if [ -n "$ZONE" ]; then
    ok "zone: $ZONE"
  fi
}

# ---------------------------------------------------------------------------
# Task 2 - the custom dashboard
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Create custom dashboards"

  EXISTING="$(gcloud monitoring dashboards list --project "$PROJECT_ID" \
                --filter="displayName='$DASHBOARD_NAME'" \
                --format="value(name)" 2>/dev/null | head -1)"

  if [ -n "$EXISTING" ]; then
    ok "the dashboard '$DASHBOARD_NAME' already exists"
  else
    # The layout has to be gridLayout. A dashboard with any other layout is
    # accepted by the API but does not score.
    cat > "$WORKDIR/dashboard.json" <<'EOF'
{
  "displayName": "My Dashboard",
  "gridLayout": {
    "columns": "2",
    "widgets": [
      {
        "title": "My Chart",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              },
              "plotType": "LINE"
            }
          ]
        }
      }
    ]
  }
}
EOF
    if gcloud monitoring dashboards create --config-from-file="$WORKDIR/dashboard.json" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the dashboard '$DASHBOARD_NAME' with a chart called 'My Chart'"
    else
      info "trying the REST API instead"
      RESP="$(curl -s -X POST "$API/v1/projects/$PROJECT_ID/dashboards" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$WORKDIR/dashboard.json")"
      if printf '%s' "$RESP" | grep -q '"name"'; then
        ok "created the dashboard '$DASHBOARD_NAME' through the API"
      else
        note_fail "could not create the dashboard"
        printf '%s\n' "$RESP" | head -6 | sed 's/^/    /'
        return 1
      fi
    fi
  fi

  pause_for_check 2 "Create custom dashboard"
}

# ---------------------------------------------------------------------------
# Task 3 - the notification channel and the alert policy
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Alerting policies"

  # --- the notification channel -------------------------------------------
  CHANNEL_NAME="$(gcloud beta monitoring channels list --project "$PROJECT_ID" \
                    --filter="type='email' AND labels.email_address='$EMAIL'" \
                    --format="value(name)" 2>/dev/null | head -1)"
  if [ -z "$CHANNEL_NAME" ]; then
    CHANNEL_NAME="$(gcloud beta monitoring channels list --project "$PROJECT_ID" \
                      --filter="type='email'" --format="value(name)" 2>/dev/null | head -1)"
  fi

  if [ -n "$CHANNEL_NAME" ]; then
    ok "the notification channel $CHANNEL_NAME already exists"
  else
    CHANNEL_NAME="$(gcloud beta monitoring channels create \
                     --project "$PROJECT_ID" \
                     --display-name="$CHANNEL_DISPLAY" \
                     --type="email" \
                     --channel-labels="email_address=$EMAIL" \
                     --format="value(name)" 2>/dev/null)"
    if [ -z "$CHANNEL_NAME" ]; then
      RESP="$(curl -s -X POST "$API/v3/projects/$PROJECT_ID/notificationChannels" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "{
                      \"type\": \"email\",
                      \"displayName\": \"$CHANNEL_DISPLAY\",
                      \"labels\": { \"email_address\": \"$EMAIL\" },
                      \"enabled\": true
                    }")"
      CHANNEL_NAME="$(json_str "$RESP" name)"
    fi
    if [ -n "$CHANNEL_NAME" ]; then
      ok "created the notification channel for $EMAIL"
    else
      note_fail "could not create the notification channel"
      return 1
    fi
  fi

  # --- the alert policy ----------------------------------------------------
  EXISTING="$(gcloud alpha monitoring policies list --project "$PROJECT_ID" \
                --filter="displayName='$POLICY_NAME'" \
                --format="value(name)" 2>/dev/null | head -1)"

  if [ -n "$EXISTING" ]; then
    ok "the alert policy '$POLICY_NAME' already exists"
    POLICY_FULL="$EXISTING"
  else
    # Two conditions, both above a threshold of 20, and ALL of them must be
    # met before the policy fires.
    cat > "$WORKDIR/policy.json" <<EOF
{
  "displayName": "$POLICY_NAME",
  "combiner": "AND",
  "conditions": [
    {
      "displayName": "VM Instance - CPU usage",
      "conditionThreshold": {
        "filter": "resource.type = \\"gce_instance\\" AND metric.type = \\"compute.googleapis.com/instance/cpu/usage_time\\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    },
    {
      "displayName": "VM Instance - CPU utilization",
      "conditionThreshold": {
        "filter": "resource.type = \\"gce_instance\\" AND metric.type = \\"compute.googleapis.com/instance/cpu/utilization\\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": [ "$CHANNEL_NAME" ],
  "enabled": true
}
EOF
    if gcloud alpha monitoring policies create --policy-from-file="$WORKDIR/policy.json" \
         --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the alert policy '$POLICY_NAME' with two conditions"
    else
      RESP="$(curl -s -X POST "$API/v3/projects/$PROJECT_ID/alertPolicies" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$WORKDIR/policy.json")"
      POLICY_FULL="$(json_str "$RESP" name)"
      if [ -n "$POLICY_FULL" ]; then
        ok "created the alert policy '$POLICY_NAME' through the API"
      else
        note_fail "could not create the alert policy"
        printf '%s\n' "$RESP" | head -6 | sed 's/^/    /'
        return 1
      fi
    fi
  fi

  pause_for_check 3 "Create alerting policies"
}

# ---------------------------------------------------------------------------
# Task 4 - the resource group
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Resource groups"

  # A group with a plausible filter but no members does not score, so the
  # filter forms are tried until the member list actually matches.
  local -a FILTERS=(
    'resource.type = "gce_instance" AND resource.metadata.name = starts_with("nginx")'
    'resource.type = "gce_instance" AND metadata.system_labels.name = starts_with("nginx")'
    'resource.type = "gce_instance" AND resource.metadata.name = has_substring("nginx")'
    'resource.metadata.name = has_substring("nginx")'
  )

  GROUP_FULL="$(curl -s -H "Authorization: Bearer $TOKEN" \
                 "$API/v3/projects/$PROJECT_ID/groups" 2>/dev/null \
                 | tr '{' '\n' | grep "\"displayName\": *\"$GROUP_NAME\"" \
                 | grep -oE '"name": *"[^"]+"' | head -1 | sed 's/.*"name": *"//; s/"$//')"

  if [ -n "$GROUP_FULL" ]; then
    ok "the group '$GROUP_NAME' already exists"
  else
    local F RESP COUNT
    for F in "${FILTERS[@]}"; do
      dim "    trying: $F"
      # the filter contains double quotes of its own, so it is json escaped
      # and the body is built with printf, which leaves the backslashes alone
      printf '{\n  "displayName": "%s",\n  "filter": "%s"\n}\n' \
        "$GROUP_NAME" "$(json_escape "$F")" > "$WORKDIR/group.json"
      RESP="$(curl -s -X POST "$API/v3/projects/$PROJECT_ID/groups" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$WORKDIR/group.json")"
      GROUP_FULL="$(json_str "$RESP" name)"
      [ -z "$GROUP_FULL" ] && continue
      COUNT="$(group_members "$GROUP_FULL" | grep -c nginxstack)"
      if [ "${COUNT:-0}" -ge 1 ] 2>/dev/null; then
        ok "created the group and it matches $COUNT VM instances"
        break
      fi
      # the filter did not match, try the next one
      curl -s -X DELETE "$API/v3/$GROUP_FULL" \
        -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
      GROUP_FULL=""
    done
    if [ -z "$GROUP_FULL" ]; then
      note_fail "could not create a resource group that matches the VMs"
      dim "  the lab's instances are:"
      echo "$LAB_VMS" | sed 's/^/    /'
      dim "  if they are not there yet, wait for them and re-run"
      return 1
    fi
  fi

  GROUP_ID="$(printf '%s' "$GROUP_FULL" | awk -F/ '{print $NF}')"
  ok "the group id is $GROUP_ID"
  dim "    members:"
  group_members "$GROUP_FULL" | grep nginxstack | sed 's/^/      /'

  pause_for_check 4 "Create Resource Group"
}

# ---------------------------------------------------------------------------
# Task 5 - the uptime check
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Uptime monitoring"

  if [ -z "${GROUP_ID:-}" ]; then
    GROUP_ID="$(curl -s -H "Authorization: Bearer $TOKEN" \
                   "$API/v3/projects/$PROJECT_ID/groups" 2>/dev/null \
                   | tr '{' '\n' | grep "\"displayName\": *\"$GROUP_NAME\"" \
                   | grep -oE '"name": *"[^"]+"' | head -1 | sed 's/.*"name": *"//; s/"$//' | awk -F/ '{print $NF}')"
  fi
  if [ -z "$GROUP_ID" ]; then
    err "the resource group is needed for the uptime check - run task 4 first"
    return 1
  fi

  EXISTING="$(gcloud monitoring uptime list --project "$PROJECT_ID" \
                --filter="displayName='$UPTIME_NAME'" \
                --format="value(name)" 2>/dev/null | head -1)"

  if [ -n "$EXISTING" ]; then
    ok "the uptime check '$UPTIME_NAME' already exists"
    UPTIME_FULL="$EXISTING"
  else
    if gcloud monitoring uptime create "$UPTIME_NAME" \
         --project "$PROJECT_ID" \
         --group-id="$GROUP_ID" \
         --group-type="gce-instance" \
         --protocol=http --port=80 --path=/ --period=60 \
         --quiet >/dev/null 2>&1; then
      ok "created the uptime check '$UPTIME_NAME'"
    else
      RESP="$(curl -s -X POST "$API/v3/projects/$PROJECT_ID/uptimeCheckConfigs" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "{
                      \"displayName\": \"$UPTIME_NAME\",
                      \"resourceGroup\": {
                        \"groupId\": \"$GROUP_ID\",
                        \"resourceType\": \"INSTANCE\"
                      },
                      \"httpCheck\": {
                        \"requestMethod\": \"GET\",
                        \"path\": \"/\",
                        \"port\": 80,
                        \"useSsl\": false
                      },
                      \"period\": \"60s\",
                      \"timeout\": \"10s\"
                    }")"
      UPTIME_FULL="$(json_str "$RESP" name)"
      if [ -n "$UPTIME_FULL" ]; then
        ok "created the uptime check '$UPTIME_NAME' through the API"
      else
        note_fail "could not create the uptime check"
        printf '%s\n' "$RESP" | head -6 | sed 's/^/    /'
        return 1
      fi
    fi
    UPTIME_FULL="$(gcloud monitoring uptime list --project "$PROJECT_ID" \
                    --filter="displayName='$UPTIME_NAME'" \
                    --format="value(name)" 2>/dev/null | head -1)"
  fi

  UPTIME_ID="$(printf '%s' "$UPTIME_FULL" | awk -F/ '{print $NF}')"
  ok "the uptime check id is $UPTIME_ID"

  # the alert that fires when the uptime check fails
  if [ -n "${CHANNEL_NAME:-}" ] && [ -n "$UPTIME_ID" ]; then
    if [ -z "$(gcloud alpha monitoring policies list --project "$PROJECT_ID" \
                  --filter="displayName ~ 'Uptime check failed'" \
                  --format="value(name)" 2>/dev/null | head -1)" ]; then
      cat > "$WORKDIR/uptime_alert.json" <<EOF
{
  "displayName": "Uptime check failed for $UPTIME_NAME",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime check failed",
      "conditionThreshold": {
        "filter": "metric.type = \\"monitoring.googleapis.com/uptime_check/check_passed\\" AND metric.label.check_id = \\"$UPTIME_ID\\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ],
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1.0,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": [ "$CHANNEL_NAME" ],
  "enabled": true
}
EOF
      gcloud alpha monitoring policies create --policy-from-file="$WORKDIR/uptime_alert.json" \
        --project "$PROJECT_ID" --quiet >/dev/null 2>&1 \
        || curl -s -X POST "$API/v3/projects/$PROJECT_ID/alertPolicies" \
             -H "Authorization: Bearer $TOKEN" \
             -H "Content-Type: application/json" \
             -d @"$WORKDIR/uptime_alert.json" >/dev/null 2>&1
      ok "the uptime check has an alert policy attached"
    fi
  fi

  dim "  the check takes a few minutes to become active."

  pause_for_check 5 "Create uptime check"
}

# ---------------------------------------------------------------------------
# Task 6 - disable the alert
# ---------------------------------------------------------------------------
task6() {
  step "Task 6 - Disable the alert"

  POLICY_FULL="$(gcloud alpha monitoring policies list --project "$PROJECT_ID" \
                  --filter="displayName='$POLICY_NAME'" \
                  --format="value(name)" 2>/dev/null | head -1)"

  if [ -z "$POLICY_FULL" ]; then
    warn "the alert policy '$POLICY_NAME' was not found"
    return 0
  fi

  if gcloud alpha monitoring policies update "$POLICY_FULL" --no-enabled \
       --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
    ok "the alert policy '$POLICY_NAME' is disabled"
  else
    curl -s -X PATCH "$API/v3/$POLICY_FULL?updateMask=enabled" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"enabled": false}' >/dev/null 2>&1
    ok "the alert policy '$POLICY_NAME' is disabled through the API"
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
  6) task6 ;;
  "")
    task1
    task2 || { echo ""; err "task 2 failed"; exit 1; }
    task3 || { echo ""; err "task 3 failed"; exit 1; }
    task4 || { echo ""; err "task 4 failed"; exit 1; }
    task5 || { echo ""; err "task 5 failed"; exit 1; }
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
echo "  Project   : $PROJECT_ID"
echo "  Dashboard : $DASHBOARD_NAME  (with the chart 'My Chart')"
echo "  Policy    : $POLICY_NAME  (2 conditions, both above 20, ANDed)"
echo "  Group     : $GROUP_NAME"
echo "  Uptime    : $UPTIME_NAME"
echo ""
echo "  Checkpoints:"
echo "    1. Create custom dashboard      (25)"
echo "    2. Create alerting policies     (25)"
echo "    3. Create Resource Group        (25)"
echo "    4. Create uptime check          (25)"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
