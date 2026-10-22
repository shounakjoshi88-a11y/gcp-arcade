#!/usr/bin/env bash
# =============================================================================
#  "Deploying GKE Autopilot Clusters from Cloud Shell"
#  Google Cloud Arcade / Cloud Skills Boost (GKE course, CLI variant).
#
#  This lab is entirely Cloud Shell, so all three graded objectives can be
#  automated:
#    1  the regional Autopilot cluster autopilot-cluster-1
#    2  deployment nginx-1, a test.html copied into its Pod, and a
#       LoadBalancer service exposing that Pod
#    3  the new-nginx Pod applied from new-nginx-pod.yaml
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_gke_autopilot_shell.sh
#     chmod +x gsp_gke_autopilot_shell.sh
#     ./gsp_gke_autopilot_shell.sh
#
#  OPTIONS:
#     --project ID    GCP project (default: active gcloud project)
#     --region REGION the lab's region (default: $my_region, $REGION, project
#                     metadata, the org policy's region, else us-west1)
#     --task N        run only task N (1-5)
#     --yes           do not pause at the checkpoints
#     --timeout MIN   cluster wait budget (default: 30)
#     -h, --help      this help
#
#  CHECKPOINTS:
#     1. Deploy GKE clusters                    (end of task 1)
#     2. Deploy Pods to GKE clusters            (end of task 4)
#     3. Deploy a new pod using a Yaml file     (task 5, after the apply)
#
#  NOTES:
#   * Autopilot is regional and provisions its own nodes. A new Pod can sit
#     Pending for a few minutes while the first node is created - that is
#     expected, and the script waits for it.
#   * The region is assigned per run. The project carries an org policy
#     (constraints/gcp.resourceLocations) that rejects other regions, so the
#     script tries to discover the right one instead of trusting the text.
#   * The lab's Task 5 shell/port-forward/log steps are interactive. They are
#     printed for you, not automated.
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
Deploying GKE Autopilot Clusters from Cloud Shell

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_gke_autopilot_shell.sh
   chmod +x gsp_gke_autopilot_shell.sh
   ./gsp_gke_autopilot_shell.sh

OPTIONS:
   --project ID    GCP project (default: active gcloud project)
   --region REGION the lab's region (default: $my_region, $REGION, metadata, else us-west1)
   --task N        run only task N (1-5)
   --yes           do not pause at the checkpoints
   --timeout MIN   cluster wait budget (default: 30)
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

policy_region() {
  local vals
  vals="$(gcloud resource-manager org-policies describe constraints/gcp.resourceLocations \
            --project "$PROJECT_ID" --effective --format="value(listPolicy.allowedValues)" 2>/dev/null)"
  echo "$vals" | tr ',' '\n' | grep -o 'in:[a-z0-9-]*-locations' \
    | head -n1 | sed 's/^in://; s/-locations$//'
}

META_REGION="$(gcloud compute project-info describe \
  --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null | tr -d '\r')"

if [ -n "$REGION_OVERRIDE" ]; then
  REGION="$REGION_OVERRIDE"
  info "region from --region: $REGION"
elif [ -n "${my_region:-}" ]; then
  REGION="$my_region"
  info "region from my_region: $REGION"
elif [ -n "${REGION:-}" ]; then
  info "region from the environment: $REGION"
elif [ -n "${META_REGION:-}" ]; then
  REGION="$META_REGION"
  info "the lab's region, from the project metadata: $REGION"
else
  POLICY_REGION="$(policy_region)"
  if [ -n "$POLICY_REGION" ]; then
    REGION="$POLICY_REGION"
    info "the org policy only allows $REGION"
  else
    REGION="us-west1"
    warn "no region hint found - using the lab text's us-west1 (override with --region)"
  fi
fi

CLUSTER="autopilot-cluster-1"
DEPLOY="nginx-1"
POD_YAML="$HOME/new-nginx-pod.yaml"
TEST_HTML="$HOME/test.html"
MAX_SECONDS=0

printf "%s%s  Deploying GKE Autopilot Clusters from Cloud Shell%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %scluster=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$CLUSTER" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
cluster_exists() { gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; }

run_live() {  # $1 = log file, rest = command
  local log="$1"; shift
  local pid last=0 n elapsed=0 rc=0
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
      printf "    ... still working (%ss elapsed)\n" "$elapsed"
    fi
  done
  wait "$pid"
  rc=$?
  n="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
  [ -z "$n" ] && n=0
  if [ "$n" -gt "$last" ]; then
    tail -n +$((last + 1)) "$log" | sed 's/^/    /'
  fi
  return $rc
}

tail_error() {
  [ -f "$1" ] || return 0
  grep -iE 'error|denied|failed|forbidden|unauthorized|violates' "$1" 2>/dev/null \
    | tail -n 3 | tr '\n' ' '
}

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s', then press Enter.%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    >%s" "$C_YELLOW" "$C_RESET"
  read -r _ || true
}

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
preflight() {
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
    warn "not in Cloud Shell - gcloud and kubectl must be on PATH"
  fi

  info "enabling the Kubernetes Engine API"
  gcloud services enable container.googleapis.com --project "$PROJECT_ID" --quiet >/dev/null 2>&1
  ok "the Kubernetes Engine API is enabled"

  if command -v kubectl >/dev/null 2>&1; then
    ok "kubectl is available"
  else
    note_fail "kubectl is not on PATH - nothing after task 1 will work"
  fi
  command -v curl >/dev/null 2>&1 && ok "curl is available" || note_fail "curl is not on PATH"
}

# ---------------------------------------------------------------------------
# Task 1 - the cluster
# ---------------------------------------------------------------------------
try_create_cluster() {
  run_live "$WORKDIR/cluster-create.log" \
    gcloud container clusters create-auto "$CLUSTER" --region "$REGION" \
      --project "$PROJECT_ID" --quiet
}

task1() {
  step "Task 1 - Deploy the GKE cluster"

  if cluster_exists; then
    ok "the cluster $CLUSTER already exists in $REGION"
  else
    info "creating the Autopilot cluster $CLUSTER in $REGION"
    dim "  this usually takes 5-15 minutes; gcloud's output is streamed below"
    MAX_SECONDS=$((WAIT_MIN * 60))
    local rc=0
    try_create_cluster
    rc=$?

    if [ "$rc" != "0" ] && [ "$rc" != "124" ] \
       && grep -qi "violates constraint" "$WORKDIR/cluster-create.log" 2>/dev/null; then
      local alt="${POLICY_REGION:-}"
      [ -z "$alt" ] && alt="$(policy_region)"
      if [ -n "$alt" ] && [ "$alt" != "$REGION" ]; then
        warn "the project's org policy does not allow $REGION"
        info "retrying in $alt"
        REGION="$alt"
        try_create_cluster
        rc=$?
      fi
    fi
    MAX_SECONDS=0

    if [ "$rc" = "0" ]; then
      ok "the cluster $CLUSTER is up in $REGION"
    elif [ "$rc" = "124" ]; then
      warn "the cluster was still provisioning after ${WAIT_MIN} minutes"
      note_fail "gave up waiting - re-run later, or with a longer --timeout"
      dim "  check Kubernetes Engine > Clusters to watch it finish"
    else
      local e; e="$(tail_error "$WORKDIR/cluster-create.log")"
      [ -n "$e" ] && err "$e"
      note_fail "could not create the cluster - full log: $WORKDIR/cluster-create.log"
    fi
  fi

  if cluster_exists; then
    local status ver loc
    status="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" --format="value(status)" 2>/dev/null)"
    ver="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" --format="value(currentMasterVersion)" 2>/dev/null)"
    loc="$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" --format="value(location)" 2>/dev/null)"
    ok "status=$status  version=$ver  location=$loc"
  fi

  info "writing the kubeconfig (gcloud container clusters get-credentials)"
  if gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" \
       --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "kubeconfig updated"
  else
    note_fail "could not fetch the cluster credentials"
  fi

  pause_for_check 1 "Deploy GKE clusters"
}

# ---------------------------------------------------------------------------
# Tasks 2-3 - inspect the kubeconfig and the cluster (read-only)
# ---------------------------------------------------------------------------
tasks23() {
  step "Tasks 2-3 - Connect to the cluster and inspect it"

  info "kubectl config current-context"
  kubectl config current-context 2>/dev/null | sed 's/^/    /'

  info "the expected context name for this cluster"
  dim "    gke_${PROJECT_ID}_${REGION}_${CLUSTER}"
  kubectl config use-context "gke_${PROJECT_ID}_${REGION}_${CLUSTER}" > "$WORKDIR/context.log" 2>&1 \
    && ok "the active context is that cluster" \
    || dim "  $(head -n 1 "$WORKDIR/context.log" 2>/dev/null)"

  info "kubectl cluster-info"
  kubectl cluster-info 2>/dev/null | sed 's/^/    /'

  info "kubectl config get-contexts"
  kubectl config get-contexts 2>/dev/null | sed 's/^/    /'

  info "kubectl config view (certificate data is redacted by kubectl)"
  kubectl config view 2>/dev/null | grep -E '^(apiVersion|kind|current-context|clusters:|contexts:|users:|- name:|  name:|    server:|    certificate)' \
    | head -n 20 | sed 's/^/    /'

  dim "  nano ~/.kube/config is the lab's manual look at the same file"
  dim "  no checkpoint here - the lab only asks you to read it"
}

# ---------------------------------------------------------------------------
# Task 4 - deployment, test.html in the Pod, LoadBalancer service
# ---------------------------------------------------------------------------
nginx_pod() {
  kubectl get pods -l app="$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

task4() {
  step "Task 4 - Deploy Pods to the cluster"

  if ! cluster_exists; then
    note_fail "the cluster $CLUSTER is missing, so there is nothing to deploy onto"
    return 0
  fi

  if kubectl get deployment "$DEPLOY" >/dev/null 2>&1; then
    ok "the deployment $DEPLOY already exists"
  else
    info "kubectl create deployment --image nginx $DEPLOY"
    if kubectl create deployment --image nginx "$DEPLOY" > "$WORKDIR/deploy.log" 2>&1; then
      ok "the deployment $DEPLOY is created"
    else
      err "$(tail_error "$WORKDIR/deploy.log")"
      note_fail "could not create the deployment - see $WORKDIR/deploy.log"
      return 0
    fi
  fi

  info "waiting for the Pod (Autopilot may need to add a node first)"
  MAX_SECONDS=$((WAIT_MIN * 60))
  if run_live "$WORKDIR/rollout.log" kubectl rollout status "deployment/$DEPLOY" --timeout=600s; then
    ok "the rollout finished"
  else
    warn "the rollout did not confirm in time"
    dim "  $(tail -n 2 "$WORKDIR/rollout.log" 2>/dev/null | tr '\n' ' ')"
  fi
  MAX_SECONDS=0

  local pod
  pod="$(nginx_pod)"
  if [ -z "$pod" ]; then
    warn "no $DEPLOY Pod yet - Autopilot is still adding a node"
    note_fail "skipped the test.html copy and the LoadBalancer service"
    dim "  re-run this task in a minute: ./gsp_gke_autopilot_shell.sh --task 4"
    return 0
  fi
  ok "the Pod is $pod"
  kubectl get pods 2>/dev/null | sed 's/^/    /'
  [ "$ASSUME_YES" = "1" ] || dim "  (kubectl top nodes needs a minute before it reports anything)"

  info "creating the file the lab copies into the container"
  cat > "$TEST_HTML" <<'HTML_END'
<html>
  <head>
    <title>This is title</title>
  </head>
  <body>
    <h1>Hello world</h1>
  </body>
</html>
HTML_END
  ok "$TEST_HTML written"

  info "kubectl cp $TEST_HTML $pod:/usr/share/nginx/html/test.html"
  if kubectl cp "$TEST_HTML" "$pod:/usr/share/nginx/html/test.html" > "$WORKDIR/cp.log" 2>&1; then
    ok "the file is inside the container"
  else
    err "$(tail_error "$WORKDIR/cp.log")"
    note_fail "could not copy test.html into the Pod - see $WORKDIR/cp.log"
  fi

  # The lab exposes the Pod itself, so the service is named after the Pod.
  local svc
  svc="$(kubectl get svc -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1)"
  if [ -n "$svc" ]; then
    ok "a LoadBalancer service already exists: $svc"
  else
    info "kubectl expose pod $pod --port 80 --type LoadBalancer"
    if kubectl expose pod "$pod" --port 80 --type LoadBalancer > "$WORKDIR/expose.log" 2>&1; then
      svc="$pod"
      ok "the service $svc is created"
    else
      err "$(tail_error "$WORKDIR/expose.log")"
      note_fail "could not expose the Pod - see $WORKDIR/expose.log"
    fi
  fi

  echo ""
  kubectl get services 2>/dev/null | sed 's/^/    /'

  if [ -n "${svc:-}" ]; then
    info "waiting for the external IP (1-3 minutes)"
    local ip="" i=0
    while [ "$i" -lt 180 ]; do
      ip="$(kubectl get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
      [ -n "$ip" ] && break
      sleep 2
      i=$((i + 2))
      [ $((i % 20)) -eq 0 ] && printf "    ... still <pending> (%ss)\n" "$i"
    done
    if [ -n "$ip" ]; then
      ok "external IP: $ip"
      dim "  curl http://$ip/test.html"
      local body
      body="$(curl -s --max-time 15 "http://$ip/test.html" 2>/dev/null)"
      if echo "$body" | grep -qi "hello world"; then
        ok "the nginx Pod is serving test.html"
      else
        warn "curl did not return the page yet - the load balancer may still be health-checking"
        dim "  try: curl http://$ip/test.html"
      fi
    else
      warn "the external IP is still <pending> after 3 minutes"
      dim "  it usually populates; check with: kubectl get services"
    fi
  fi

  pause_for_check 4 "Deploy Pods to GKE clusters"
}

# ---------------------------------------------------------------------------
# Task 5 - the Pod from a manifest
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Deploy a new Pod from a YAML manifest"

  if ! cluster_exists; then
    note_fail "the cluster $CLUSTER is missing, so there is nowhere to apply the manifest"
    return 0
  fi

  if [ -f "$POD_YAML" ] && grep -q 'name: new-nginx' "$POD_YAML" 2>/dev/null; then
    ok "$POD_YAML already exists"
  else
    info "writing $POD_YAML (the lab's new-nginx-pod.yaml)"
    cat > "$POD_YAML" <<'YAML_END'
apiVersion: v1
kind: Pod
metadata:
  name: new-nginx
  labels:
    name: new-nginx
spec:
  containers:
  - name: new-nginx
    image: nginx
    ports:
    - containerPort: 80
YAML_END
    ok "manifest written"
  fi

  info "kubectl apply -f $POD_YAML"
  if kubectl apply -f "$POD_YAML" > "$WORKDIR/apply.log" 2>&1; then
    ok "the new-nginx Pod is applied"
  else
    err "$(tail_error "$WORKDIR/apply.log")"
    note_fail "could not apply the manifest - see $WORKDIR/apply.log"
    return 0
  fi

  info "waiting for new-nginx to be Running"
  MAX_SECONDS=$((WAIT_MIN * 60))
  run_live "$WORKDIR/newpod.log" kubectl wait --for=condition=Ready pod/new-nginx --timeout=600s >/dev/null 2>&1
  MAX_SECONDS=0
  echo ""
  kubectl get pods 2>/dev/null | sed 's/^/    /'

  pause_for_check 5 "Deploy a new pod using a Yaml file"

  step "Task 5 continued - the interactive parts (by hand)"
  cat <<INTERACTIVE
    The lab's remaining steps are interactive; run them yourself:

      kubectl exec -it new-nginx -- /bin/bash
        apt-get update && apt-get install -y nano
        cd /usr/share/nginx/html && nano test.html     # add the two lines
        exit

      kubectl port-forward new-nginx 10081:80          # then, in a 2nd tab:
      curl http://127.0.0.1:10081/test.html

      kubectl logs new-nginx -f --timestamps           # in a 3rd tab
INTERACTIVE
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$HOME/gsp-autopilot-shell}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."

case "$ONLY_TASK" in
  1) preflight; task1 ;;
  2|3) preflight; tasks23 ;;
  4) preflight; task4 ;;
  5) preflight; task5 ;;
  "")
    preflight
    task1
    tasks23
    task4
    task5
    ;;
  *) err "--task must be between 1 and 5"; exit 2 ;;
esac

step "Summary"
echo "  Project   : $PROJECT_ID"
echo "  Region    : $REGION"
echo "  Cluster   : $CLUSTER (Autopilot, regional)"
echo "  Workload  : deployment/$DEPLOY + the $DEPLOY Pod's LoadBalancer"
echo "  Manifest  : $POD_YAML (Pod new-nginx)"
echo ""
echo "  Checkpoints:"
echo "    1. Deploy GKE clusters"
echo "    2. Deploy Pods to GKE clusters"
echo "    3. Deploy a new pod using a Yaml file"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    kubectl delete pod new-nginx --ignore-not-found"
echo "    kubectl delete deployment $DEPLOY --ignore-not-found"
echo "    gcloud container clusters delete $CLUSTER --region=$REGION --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
