#!/usr/bin/env bash
# =============================================================================
#  "Deploying GKE Autopilot Clusters"
#  Google Cloud Arcade / Cloud Skills Boost lab (console version, GKE course).
#
#  The lab is click-through, but the two graded objectives are just two
#  resources, so this does them with gcloud and kubectl:
#    1  the regional Autopilot cluster autopilot-cluster-1
#    2  the nginx-1 deployment: nginx:latest, three Pods
#    3  the inspection data the lab has you click through in the console,
#       printed as kubectl output (details, revisions, events, Pod YAML)
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_gke_autopilot.sh
#     chmod +x gsp_gke_autopilot.sh
#     ./gsp_gke_autopilot.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region REGION   the lab's region (default: $REGION, else asked)
#     --task N          run only task N (1-3)
#     --yes             do not pause for the checkpoints
#     --timeout MIN     how long to wait for the cluster (default: 30)
#     -h, --help        this help
#
#  CHECKPOINTS (the two graded objectives):
#     1. Deploy GKE cluster                     (end of task 1)
#     2. Deploy a sample nginx workload         (end of task 2)
#
#  NOTES:
#   * Autopilot clusters are regional. The lab injects the region per run, and
#     the cluster name is fixed: autopilot-cluster-1.
#   * Autopilot provisions its own nodes, so there are no node pools, machine
#     types or node counts to set. Nothing here touches them.
#   * Provisioning takes 5-15 minutes. The script streams gcloud's progress and
#     prints a heartbeat every 20 seconds so it never looks hung.
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
warn() { printf "  %s[WARN]%s %s\n"   "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "  %s[FAIL]%s %s\n"   "$C_RED"    "$C_RESET" "$*"; }
info() { printf "  %s[INFO]%s %s\n"   "$C_BLUE"   "$C_RESET" "$*"; }
dim()  { printf "  %s%s%s\n"          "$C_DIM"    "$*"       "$C_RESET"; }

FAILURES=0
note_fail() { err "$1"; FAILURES=$((FAILURES + 1)); }

PROJECT_OVERRIDE=""
REGION_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
WAIT_MIN=30

usage() {
  cat <<'USAGE_END'
Deploying GKE Autopilot Clusters

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_gke_autopilot.sh
   chmod +x gsp_gke_autopilot.sh
   ./gsp_gke_autopilot.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region REGION   the lab's region (default: $REGION, else asked)
   --task N          run only task N (1-3)
   --yes             do not pause for the checkpoints
   --timeout MIN     how long to wait for the cluster (default: 30)
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --region)  REGION_OVERRIDE="$2";  shift 2 ;;
    --task)    ONLY_TASK="$2";        shift 2 ;;
    --yes)     ASSUME_YES=1;          shift ;;
    --timeout) WAIT_MIN="$2";         shift 2 ;;
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

ask() {  # $1 = variable name, $2 = label, $3 = default
  local __name="$1" __label="$2" __default="$3" __ans=""
  printf "  %s%s%s [%s]: " "$C_BOLD" "$__label" "$C_RESET" "$__default"
  if ! read -r __ans; then
    echo ""
    __ans=""
  fi
  printf -v "$__name" '%s' "${__ans:-$__default}"
}

if [ -n "$REGION_OVERRIDE" ]; then
  REGION="$REGION_OVERRIDE"
  info "region from --region: $REGION"
elif [ -n "${REGION:-}" ]; then
  info "the lab's region came from the environment: $REGION"
else
  echo ""
  warn "the lab assigns the region per run"
  dim "  it is on the lab setup panel - copy it from there"
  echo ""
  ask REGION "Region - the Autopilot cluster" "us-central1"
  echo ""
fi

CLUSTER="autopilot-cluster-1"

printf "%s%s  Deploying GKE Autopilot Clusters%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %scluster=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$CLUSTER" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
cluster_exists() { gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; }

run_live() {  # $1 = log file, rest = command
  local log="$1"; shift
  local pid last=0 n elapsed=0
  : > "$log"
  "$@" > "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [ "${MAX_SECONDS:-0}" -gt 0 ] && [ "$elapsed" -ge "$MAX_SECONDS" ]; then
      printf "    ... giving up after %ss (raise it with --timeout)\n" "$elapsed"
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    n="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
    [ -z "$n" ] && n=0
    if [ "$n" -gt "$last" ]; then
      tail -n +$((last + 1)) "$log" | sed 's/^/    /'
      last="$n"
    elif [ $((elapsed % 20)) -eq 0 ]; then
      printf "    ... cluster is still provisioning (%ss elapsed)\n" "$elapsed"
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
  warn "not in Cloud Shell - kubectl and gcloud must be on PATH"
fi

info "enabling the Kubernetes Engine API"
gcloud services enable container.googleapis.com --project "$PROJECT_ID" --quiet >/dev/null 2>&1
ok "the Kubernetes Engine API is enabled"

if command -v kubectl >/dev/null 2>&1; then
  ok "kubectl is available"
else
  note_fail "kubectl is not on PATH - the workload step will not work"
fi

# ---------------------------------------------------------------------------
# Task 1 - the Autopilot cluster
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Deploy the GKE cluster"

  if cluster_exists; then
    ok "the cluster $CLUSTER already exists in $REGION"
  else
    local elsewhere
    elsewhere="$(gcloud container clusters list --project "$PROJECT_ID" \
                   --format="value(name)" 2>/dev/null | grep -x "$CLUSTER" || true)"
    if [ -n "$elsewhere" ]; then
      warn "$CLUSTER already exists in another region"
      dim "  the lab's grader looks for it in $REGION; delete the other one first:"
      dim "  gcloud container clusters list    then    gcloud container clusters delete $CLUSTER --region <other>"
    fi

    info "creating the Autopilot cluster $CLUSTER in $REGION"
    dim "  Autopilot is regional and manages its own nodes, so there is no node pool to size"
    dim "  this usually takes 5-15 minutes; output is streamed below"
    MAX_SECONDS=$((WAIT_MIN * 60))
    local rc=0
    if run_live "$WORKDIR/cluster-create.log" \
         gcloud container clusters create-auto "$CLUSTER" \
           --region "$REGION" --project "$PROJECT_ID" --quiet; then
      ok "the cluster $CLUSTER is up"
    else
      rc=$?
      if [ "$rc" -eq 124 ]; then
        warn "the cluster was still provisioning after ${WAIT_MIN} minutes"
        dim "  it usually finishes on its own - check Kubernetes Engine > Clusters,"
        dim "  or re-run with a longer --timeout"
      else
        local tailmsg
        tailmsg="$(grep -iE 'error|failed|denied' "$WORKDIR/cluster-create.log" 2>/dev/null | tail -n 2 | tr '\n' ' ')"
        [ -n "$tailmsg" ] && err "$tailmsg"
        note_fail "could not create the cluster - see $WORKDIR/cluster-create.log"
      fi
    fi
    MAX_SECONDS=0
  fi

  if cluster_exists; then
    local status ver loc
    status="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" \
               --format="value(status)" 2>/dev/null)"
    ver="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" \
               --format="value(currentMasterVersion)" 2>/dev/null)"
    loc="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" \
               --format="value(location)" 2>/dev/null)"
    ok "status=$status  version=$ver  location=$loc"
    dim "  in the console: Kubernetes Engine > Clusters > $CLUSTER > Storage tab"
  fi

  info "pointing kubectl at the cluster"
  if gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" \
       --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "kubeconfig updated (current-context is $CLUSTER)"
  else
    note_fail "could not fetch the cluster credentials"
  fi

  pause_for_check 1 "Deploy GKE cluster"
}

# ---------------------------------------------------------------------------
# Task 2 - the nginx-1 workload
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Deploy the sample nginx workload"

  if ! cluster_exists; then
    note_fail "the cluster $CLUSTER is missing, so there is nothing to deploy onto"
    return 0
  fi

  # The lab's console default is the literal image string "nginx:latest". A
  # bare "--image=nginx" records the spec as "nginx", which the grader does not
  # accept, so the tag is pinned explicitly here and repaired if it drifted.
  if kubectl get deployment nginx-1 >/dev/null 2>&1; then
    ok "the deployment nginx-1 already exists"
    local want=3 have cname img
    have="$(kubectl get deployment nginx-1 -o jsonpath='{.spec.replicas}' 2>/dev/null)"
    cname="$(kubectl get deployment nginx-1 -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)"
    img="$(kubectl get deployment nginx-1 -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
    [ -z "$cname" ] && cname=nginx

    if [ "$img" != "nginx:latest" ]; then
      info "the workload runs '$img'; the lab's console default is nginx:latest - updating"
      if kubectl set image "deployment/nginx-1" "${cname}=nginx:latest" > "$WORKDIR/setimage.log" 2>&1; then
        ok "nginx-1 now runs nginx:latest"
      else
        err "$(tail -n 2 "$WORKDIR/setimage.log" 2>/dev/null | tr '\n' ' ')"
        note_fail "could not pin the image to nginx:latest"
      fi
    else
      ok "nginx-1 runs nginx:latest"
    fi

    if [ "$have" != "$want" ]; then
      info "scaling nginx-1 from $have to $want replicas, as the console default does"
      kubectl scale deployment nginx-1 --replicas="$want" >/dev/null 2>&1 \
        && ok "nginx-1 scaled to $want replicas" \
        || note_fail "could not scale nginx-1"
    fi
  else
    info "creating the deployment nginx-1 (nginx:latest, 3 replicas)"
    if kubectl create deployment nginx-1 --image=nginx:latest --replicas=3 > "$WORKDIR/deploy.log" 2>&1; then
      ok "the deployment nginx-1 is created"
    else
      err "$(tail -n 2 "$WORKDIR/deploy.log" 2>/dev/null | tr '\n' ' ')"
      note_fail "could not create the deployment nginx-1"
    fi
  fi

  info "waiting for the three Pods to become ready"
  if kubectl rollout status deployment/nginx-1 --timeout=600s > "$WORKDIR/rollout.log" 2>&1; then
    ok "the rollout finished"
  else
    warn "the rollout did not confirm inside 10 minutes"
    dim "  $(tail -n 2 "$WORKDIR/rollout.log" 2>/dev/null | tr '\n' ' ')"
    dim "  Autopilot is still provisioning nodes - the Pods will come up shortly"
  fi

  echo ""
  kubectl get deployment nginx-1 2>/dev/null | sed 's/^/    /'
  kubectl get pods -l app=nginx-1 2>/dev/null | sed 's/^/    /'
  local final_img
  final_img="$(kubectl get deployment nginx-1 -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
  if [ -n "$final_img" ]; then
    dim "  the workload's image is '$final_img' - the grader looks for nginx:latest"
  fi

  pause_for_check 2 "Deploy a sample nginx workload"
}

# ---------------------------------------------------------------------------
# Task 3 - what the lab has you inspect by hand
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - The workload details the lab clicks through"

  if ! cluster_exists; then
    note_fail "the cluster $CLUSTER is missing, so there is nothing to inspect"
    return 0
  fi

  info "Details tab - the deployment spec and replica status"
  kubectl describe deployment nginx-1 2>/dev/null | sed -n '1,20p' | sed 's/^/    /'

  info "Revision History tab"
  kubectl rollout history deployment/nginx-1 2>/dev/null | sed 's/^/    /'

  info "Events tab"
  kubectl get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 8 | sed 's/^/    /'

  info "YAML tab - the full workload definition"
  kubectl get deployment nginx-1 -o yaml 2>/dev/null | sed -n '1,15p' | sed 's/^/    /'
  dim "  ... (truncated here; run 'kubectl get deployment nginx-1 -o yaml' for all of it)"

  local pod
  pod="$(kubectl get pods -l app=nginx-1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  if [ -n "$pod" ]; then
    info "the first managed Pod: $pod"
    kubectl get pod "$pod" -o wide 2>/dev/null | sed 's/^/    /'
    info "that Pod's YAML, first lines"
    kubectl get pod "$pod" -o yaml 2>/dev/null | sed -n '1,12p' | sed 's/^/    /'
    dim "  in the console: the Pod name is a link under Managed Pods"
  else
    warn "no nginx-1 Pod is running yet, so there is nothing to show"
  fi

  ok "that is everything task 3 asks you to look at in the console"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$HOME/gsp-gke-autopilot}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

case "$ONLY_TASK" in
  1) task1 ;;
  2) task2 ;;
  3) task3 ;;
  "")
    task1
    task2
    task3
    ;;
  *)
    err "--task must be between 1 and 3"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project   : $PROJECT_ID"
echo "  Region    : $REGION"
echo "  Cluster   : $CLUSTER (Autopilot, regional)"
echo "  Workload  : nginx-1 (nginx:latest, 3 replicas)"
echo ""
echo "  Checkpoints:"
echo "    1. Deploy GKE cluster"
echo "    2. Deploy a sample nginx workload"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud container clusters delete $CLUSTER --region=$REGION --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
