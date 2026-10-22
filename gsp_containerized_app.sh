#!/usr/bin/env bash
# =============================================================================
#  "Running a Containerized App on Google Kubernetes Engine"   (GSP015)
#  Google Cloud Arcade / Cloud Skills Boost.
#
#  The whole lab is Cloud Shell commands, so all three graded objectives are
#  scriptable:
#    1  the hello-world cluster (3 nodes, in the lab's zone)
#    2  the hello-app image built from the sample Dockerfile and pushed to a
#       registry, then deployed as the hello-app Deployment
#    3  a LoadBalancer Service on port 80 -> 8080, with a reachable external IP
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_containerized_app.sh
#     chmod +x gsp_containerized_app.sh
#     ./gsp_containerized_app.sh
#
#  OPTIONS:
#     --project ID   GCP project (default: active gcloud project)
#     --zone ZONE    the lab's zone (default: $ZONE, else discovered)
#     --task N       run only task N (1-5)
#     --yes          do not pause at the checkpoints
#     --timeout MIN  cluster wait budget (default: 30)
#     -h, --help     this help
#
#  CHECKPOINTS:
#     1. Create a Kubernetes Cluster                          (end of task 1)
#     2. Build and Deploy Hello World App (hello-app)         (end of task 4)
#     3. Allow external traffic to hello-app deployment       (after expose)
#
#  NOTES:
#   * The zone changes per run: --zone, $ZONE, the project metadata, or the
#     region the project's org policy allows. The policy rejects any other zone
#     with "violates constraint constraints/gcp.resourceLocations".
#   * The lab pushes to Container Registry (gcr.io). Google has been retiring
#     gcr.io, so if that push fails the script falls back to Artifact Registry
#     in the same region and deploys the image from there. The Deployment is
#     always called hello-app either way.
#   * Both the cluster build and the docker build take minutes. Everything is
#     streamed with a heartbeat so nothing looks hung.
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
ZONE_OVERRIDE=""
ONLY_TASK=""
ASSUME_YES=0
WAIT_MIN=30

usage() {
  cat <<'USAGE_END'
Running a Containerized App on Google Kubernetes Engine  (GSP015)

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_containerized_app.sh
   chmod +x gsp_containerized_app.sh
   ./gsp_containerized_app.sh

OPTIONS:
   --project ID   GCP project (default: active gcloud project)
   --zone ZONE    the lab's zone (default: $ZONE, else discovered)
   --task N       run only task N (1-5)
   --yes          do not pause at the checkpoints
   --timeout MIN  cluster wait budget (default: 30)
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)    ZONE_OVERRIDE="$2";    shift 2 ;;
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

# The lab's zone changes per run, and an org policy
# (constraints/gcp.resourceLocations) rejects any zone outside it. Precedence:
# --zone, $ZONE, the project metadata, then the allowed region from that policy.
policy_region() {
  local vals
  vals="$(gcloud resource-manager org-policies describe constraints/gcp.resourceLocations \
            --project "$PROJECT_ID" --effective --format="value(listPolicy.allowedValues)" 2>/dev/null)"
  echo "$vals" | tr ',' '\n' | grep -o 'in:[a-z0-9-]*-locations' \
    | head -n1 | sed 's/^in://; s/-locations$//'
}

pick_zone_in() {  # $1 = region -> first available -c/-b/-a zone
  local r="$1" z
  for z in c b a; do
    if gcloud compute zones list --filter="name=$r-$z" --format="value(name)" 2>/dev/null | grep -qx "$r-$z"; then
      echo "$r-$z"; return 0
    fi
  done
  echo "$r-a"
}

suggest_zone() {  # a better zone than $ZONE, if one can be worked out
  if [ -n "${META_ZONE:-}" ] && [ "$META_ZONE" != "$ZONE" ]; then
    echo "$META_ZONE"; return 0
  fi
  local pr z
  pr="$(policy_region)"
  if [ -n "$pr" ]; then
    z="$(pick_zone_in "$pr")"
    if [ -n "$z" ] && [ "$z" != "$ZONE" ]; then echo "$z"; return 0; fi
  fi
  return 1
}

if [ -z "${META_ZONE:-}" ]; then
  META_ZONE="$(gcloud compute project-info describe \
    --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null | tr -d '\r')"
fi

if [ -n "$ZONE_OVERRIDE" ]; then
  ZONE="$ZONE_OVERRIDE"
  info "zone from --zone: $ZONE"
elif [ -n "${ZONE:-}" ]; then
  info "zone from the environment: $ZONE"
elif [ -n "${META_ZONE:-}" ]; then
  ZONE="$META_ZONE"
  info "the lab's zone, from the project metadata: $ZONE"
else
  POLICY_REGION="$(policy_region)"
  if [ -n "$POLICY_REGION" ]; then
    ZONE="$(pick_zone_in "$POLICY_REGION")"
    info "the org policy only allows $POLICY_REGION, so the zone is $ZONE"
  else
    ZONE="us-west1-c"
    warn "no zone in the project metadata and no org-policy hint"
    dim "  using the zone this lab text showed (us-west1-c) - override with --zone"
  fi
fi

REGION="${ZONE%-*}"
CLUSTER="hello-world"
DEPLOY="hello-app"
IMAGE="gcr.io/$PROJECT_ID/hello-app:1.0"
AR_IMAGE="${REGION}-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:1.0"

printf "%s%s  Running a Containerized App on GKE%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %scluster=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$CLUSTER" "$C_RESET"

MAX_SECONDS=0

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
cluster_exists() { gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; }

run_live() {  # $1 = log file, rest = command  (streams, heartbeats every 20s)
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

tail_error() {  # $1 = log file
  [ -f "$1" ] || return 0
  grep -iE 'error|denied|failed|not found|forbidden|unauthorized|unknown' "$1" 2>/dev/null \
    | tail -n 3 | tr '\n' ' '
}

pause_for_check() {  # $1 = task number, $2 = checkpoint name
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  echo ""
  printf "  %s>>> Task %s applied: %s%s\n" "$C_BOLD" "$1" "$2" "$C_RESET"
  printf "  %s    Click 'Check my progress' for '%s',%s\n" "$C_DIM" "$2" "$C_RESET"
  printf "  %s    then press Enter here to continue.%s\n" "$C_DIM" "$C_RESET"
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

  gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
  ok "compute zone: $ZONE"

  if [ "${CLOUD_SHELL:-}" = "true" ]; then
    info "running inside Google Cloud Shell"
  else
    warn "not in Cloud Shell - gcloud, kubectl, docker and git all need to be on PATH"
  fi

  info "enabling the GKE, Compute and Artifact Registry APIs"
  gcloud services enable container.googleapis.com compute.googleapis.com \
    artifactregistry.googleapis.com --project "$PROJECT_ID" --quiet >/dev/null 2>&1
  ok "APIs enabled"

  local miss=0
  for t in kubectl docker git curl; do
    if command -v "$t" >/dev/null 2>&1; then
      ok "$t is available"
    else
      note_fail "$t is not on PATH"
      miss=1
    fi
  done
  [ "$miss" = "0" ] || warn "the tasks that need a missing tool are skipped, the rest still run"
}

# ---------------------------------------------------------------------------
# Task 1 - the cluster
# ---------------------------------------------------------------------------
try_create_cluster() {
  run_live "$WORKDIR/cluster-create.log" \
    gcloud container clusters create "$CLUSTER" --zone "$ZONE" \
      --project "$PROJECT_ID" --num-nodes=3 --quiet
}

task1() {
  step "Task 1 - Create the Kubernetes cluster"

  if cluster_exists; then
    ok "the cluster $CLUSTER already exists in $ZONE"
  else
    info "creating the cluster $CLUSTER in $ZONE (3 nodes, as the lab's default)"
    dim "  this usually takes 3-6 minutes; gcloud's output is streamed below"
    MAX_SECONDS=$((WAIT_MIN * 60))
    local rc=0
    try_create_cluster
    rc=$?

    # An org policy can forbid the zone outright. The lab's own zone is in the
    # project metadata (or the policy itself), so try that once before giving up.
    if [ "$rc" != "0" ] && [ "$rc" != "124" ] \
       && grep -qi "violates constraint" "$WORKDIR/cluster-create.log" 2>/dev/null; then
      local alt
      alt="$(suggest_zone || true)"
      if [ -n "$alt" ]; then
        warn "the project's org policy does not allow $ZONE"
        info "retrying in $alt"
        ZONE="$alt"
        REGION="${ZONE%-*}"
        AR_IMAGE="${REGION}-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:1.0"
        gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
        try_create_cluster
        rc=$?
      fi
    fi
    MAX_SECONDS=0

    if [ "$rc" = "0" ]; then
      ok "the cluster $CLUSTER is up in $ZONE"
    elif [ "$rc" = "124" ]; then
      warn "the cluster was still being created after ${WAIT_MIN} minutes"
      dim "  re-run with a longer --timeout, or check Kubernetes Engine > Clusters"
    else
      local e; e="$(tail_error "$WORKDIR/cluster-create.log")"
      [ -n "$e" ] && err "$e"
      if grep -qi "violates constraint" "$WORKDIR/cluster-create.log" 2>/dev/null; then
        dim "  this project's org policy restricts zones. The lab's zone is on the"
        dim "  setup panel - pass it with --zone. Metadata says: ${META_ZONE:-nothing}"
      fi
      note_fail "could not create the cluster - full log: $WORKDIR/cluster-create.log"
    fi
  fi

  if cluster_exists; then
    local status ver nodes
    status="$(gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" --format="value(status)" 2>/dev/null)"
    ver="$(gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" --format="value(currentMasterVersion)" 2>/dev/null)"
    nodes="$(gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" --format="value(currentNodeCount)" 2>/dev/null)"
    ok "status=$status  version=$ver  nodes=${nodes:-3}"
  fi

  info "pointing kubectl at the cluster"
  if gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "kubeconfig updated"
    if kubectl get nodes > "$WORKDIR/nodes.log" 2>&1; then
      dim "  $(grep -c ' Ready ' "$WORKDIR/nodes.log" 2>/dev/null || echo 0) node(s) Ready"
    fi
  else
    note_fail "could not fetch the cluster credentials"
  fi

  pause_for_check 1 "Create a Kubernetes Cluster"
}

# ---------------------------------------------------------------------------
# Tasks 2 + 3 - get the sample, build the image, push it
# ---------------------------------------------------------------------------
APP_DIR=""

fetch_sample() {
  local base="$WORKDIR/kubernetes-engine-samples"
  if [ -f "$base/quickstarts/hello-app/Dockerfile" ]; then
    ok "the sample code is already at $base/quickstarts/hello-app"
    APP_DIR="$base/quickstarts/hello-app"
    return 0
  fi

  rm -rf "$base" 2>/dev/null || true
  info "cloning kubernetes-engine-samples (shallow, this is the lab's source repo)"
  if run_live "$WORKDIR/clone.log" git clone --depth 1 \
       https://github.com/GoogleCloudPlatform/kubernetes-engine-samples "$base"; then
    :
  else
    err "$(tail_error "$WORKDIR/clone.log")"
    note_fail "could not clone the samples repo"
    return 0
  fi

  if [ -f "$base/quickstarts/hello-app/Dockerfile" ]; then
    ok "the sample code is at $base/quickstarts/hello-app"
    APP_DIR="$base/quickstarts/hello-app"
  else
    note_fail "the repo cloned but quickstarts/hello-app/Dockerfile is missing"
  fi
}

build_image() {  # sets PUSHED_IMAGE
  PUSHED_IMAGE=""
  if [ -z "$APP_DIR" ]; then
    note_fail "no sample code, so there is nothing to build"
    return 0
  fi

  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    ok "the image $IMAGE is already built in this Cloud Shell"
  else
    info "building $IMAGE from the sample Dockerfile"
    dim "  docker build pulls golang and distroless; expect 2-4 minutes"
    MAX_SECONDS=$((WAIT_MIN * 60))
    local rc=0
    if ( cd "$APP_DIR" && run_live "$WORKDIR/docker-build.log" docker build -t "$IMAGE" . ); then
      ok "the image is built"
    else
      rc=$?
      [ "$rc" = "124" ] && warn "the docker build was still running after ${WAIT_MIN} minutes" \
                        || err "$(tail_error "$WORKDIR/docker-build.log")"
      note_fail "could not build the image - see $WORKDIR/docker-build.log"
    fi
    MAX_SECONDS=0
  fi

  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    return 0
  fi

  info "authenticating docker to the registry"
  gcloud auth configure-docker gcr.io --quiet >/dev/null 2>&1 \
    || gcloud auth configure-docker --quiet >/dev/null 2>&1 || true

  info "pushing $IMAGE to Container Registry (gcr.io), as the lab does"
  if run_live "$WORKDIR/push.log" docker push "$IMAGE"; then
    ok "pushed to gcr.io"
    PUSHED_IMAGE="$IMAGE"
    return 0
  fi

  warn "$(tail_error "$WORKDIR/push.log")"
  warn "the gcr.io push failed - Container Registry is being retired by Google"
  info "falling back to Artifact Registry in $REGION"

  if gcloud artifacts repositories create hello-repo --repository-format=docker \
       --location="$REGION" --project "$PROJECT_ID" \
       --description="hello-app images" --quiet > "$WORKDIR/ar-create.log" 2>&1 \
     || gcloud artifacts repositories describe hello-repo --location="$REGION" \
          --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "the hello-repo Artifact Registry repository exists in $REGION"
  else
    note_fail "could not create the Artifact Registry repository - see $WORKDIR/ar-create.log"
    return 0
  fi

  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet >/dev/null 2>&1 || true
  docker tag "$IMAGE" "$AR_IMAGE" >/dev/null 2>&1
  if run_live "$WORKDIR/push-ar.log" docker push "$AR_IMAGE"; then
    ok "pushed to Artifact Registry instead"
    PUSHED_IMAGE="$AR_IMAGE"
  else
    err "$(tail_error "$WORKDIR/push-ar.log")"
    note_fail "could not push to Artifact Registry either - the deployment will use the gcr.io tag"
  fi
}

tasks23() {
  step "Tasks 2-3 - Build and publish the hello-app image"
  fetch_sample
  build_image
  if [ -n "${PUSHED_IMAGE:-}" ]; then
    printf '%s\n' "$PUSHED_IMAGE" > "$IMAGE_FILE" 2>/dev/null || true
    dim "  image for the deployment: $PUSHED_IMAGE"
  fi
  dim "  (no checkpoint here - the lab checks tasks 2-3 together with the deployment)"
}

# ---------------------------------------------------------------------------
# Task 4 - deploy, then expose
# ---------------------------------------------------------------------------
deploy_app() {
  local want="${PUSHED_IMAGE:-}"
  if [ -z "$want" ] && [ -s "$IMAGE_FILE" ]; then
    want="$(cat "$IMAGE_FILE" 2>/dev/null)"
  fi
  [ -z "$want" ] && want="$IMAGE"

  if kubectl get deployment "$DEPLOY" >/dev/null 2>&1; then
    ok "the deployment $DEPLOY already exists"
    local cname cur
    cname="$(kubectl get deployment "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)"
    cur="$(kubectl get deployment "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
    [ -z "$cname" ] && cname="$DEPLOY"
    if [ -n "$cur" ] && [ "$cur" != "$want" ]; then
      info "the deployment runs $cur; switching it to $want"
      kubectl set image "deployment/$DEPLOY" "${cname}=${want}" > "$WORKDIR/setimage.log" 2>&1 \
        && ok "image updated" \
        || note_fail "could not update the image - see $WORKDIR/setimage.log"
    else
      ok "it already runs $cur"
    fi
  else
    info "creating the deployment $DEPLOY from $want"
    if kubectl create deployment "$DEPLOY" --image="$want" > "$WORKDIR/deploy.log" 2>&1; then
      ok "the deployment $DEPLOY is created"
    else
      err "$(tail_error "$WORKDIR/deploy.log")"
      note_fail "could not create the deployment - see $WORKDIR/deploy.log"
      return 0
    fi
  fi

  info "waiting for the Pod to be ready"
  if kubectl rollout status "deployment/$DEPLOY" --timeout=300s > "$WORKDIR/rollout.log" 2>&1; then
    ok "the rollout finished"
  else
    warn "the rollout did not confirm in 5 minutes"
    dim "  $(tail -n 2 "$WORKDIR/rollout.log" 2>/dev/null | tr '\n' ' ')"
    dim "  if the image pull fails, check the registry path above"
  fi

  echo ""
  kubectl get deployment "$DEPLOY" 2>/dev/null | sed 's/^/    /'
  kubectl get pods -l app="$DEPLOY" 2>/dev/null | sed 's/^/    /'
}

expose_app() {
  local svc_type port target
  if kubectl get svc "$DEPLOY" >/dev/null 2>&1; then
    svc_type="$(kubectl get svc "$DEPLOY" -o jsonpath='{.spec.type}' 2>/dev/null)"
    port="$(kubectl get svc "$DEPLOY" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
    target="$(kubectl get svc "$DEPLOY" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)"
    if [ "$svc_type" = "LoadBalancer" ] && [ "$port" = "80" ] && [ "$target" = "8080" ]; then
      ok "the LoadBalancer service $DEPLOY already exists (80 -> 8080)"
      return 0
    fi
    warn "the service $DEPLOY exists but is ${svc_type}:${port}->${target}, recreating it"
    kubectl delete svc "$DEPLOY" --ignore-not-found >/dev/null 2>&1
  fi

  info "exposing the deployment: LoadBalancer, port 80 -> 8080"
  if kubectl expose deployment "$DEPLOY" --name="$DEPLOY" --type=LoadBalancer \
       --port=80 --target-port=8080 > "$WORKDIR/expose.log" 2>&1; then
    ok "the service $DEPLOY is created"
  else
    err "$(tail_error "$WORKDIR/expose.log")"
    note_fail "could not expose the deployment - see $WORKDIR/expose.log"
  fi
}

wait_for_ip() {  # echoes the external IP, empty on timeout
  local ip="" i=0
  while [ "$i" -lt 150 ]; do
    ip="$(kubectl get svc "$DEPLOY" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    if [ -n "$ip" ]; then
      echo "$ip"; return 0
    fi
    sleep 2
    i=$((i + 2))
    if [ $((i % 20)) -eq 0 ]; then
      printf "    ... waiting for the external IP (%ss)\n" "$i" >&2
    fi
  done
  return 1
}

task4() {
  step "Task 4 - Deploy the app and allow external traffic"
  deploy_app

  if ! kubectl get deployment "$DEPLOY" >/dev/null 2>&1; then
    note_fail "no deployment, so there is nothing to expose"
    return 0
  fi

  pause_for_check 4 "Build and Deploy Hello World App (hello-app)"

  expose_app
  echo ""
  kubectl get svc "$DEPLOY" 2>/dev/null | sed 's/^/    /'

  info "waiting for the external IP (usually 1-3 minutes)"
  local ip
  if ip="$(wait_for_ip)"; then
    ok "external IP: $ip"
    dim "  http://$ip/"
    local body
    body="$(curl -s --max-time 15 "http://$ip/" 2>/dev/null | head -c 200)"
    if [ -n "$body" ]; then
      ok "the app answered over HTTP"
      dim "  $body"
    else
      warn "the app did not answer yet - the load balancer may still be provisioning"
      dim "  open http://$ip/ in a browser in a minute"
    fi
  else
    warn "the external IP is still <pending> after 5 minutes"
    dim "  it usually populates; check with: kubectl get svc $DEPLOY"
  fi

  pause_for_check 4 "Allow external traffic to hello-app deployment"
}

# ---------------------------------------------------------------------------
# Task 5 - the knowledge check
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Test your understanding (answers)"
  cat <<'ANSWERS'
    1. docker push publishes the container image in Google Cloud to ...
       -> Artifact Registry
          (this lab's text calls it Artifact Registry; the older copy said
          Container Registry, and the commands still push to gcr.io)

    2. Kubernetes is an open-source container-orchestration system for
       automating deployment, scaling and management of containerized
       applications.
       -> True

    3. In Kubernetes, kubectl expose creates a ..., the forwarding rules for
       the load balancer, and the firewall rules that allow external traffic.
       -> Service
ANSWERS
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$HOME/gsp-containerized-app}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."
IMAGE_FILE="$WORKDIR/image.txt"

case "$ONLY_TASK" in
  1) preflight; task1 ;;
  2|3) preflight; tasks23 ;;
  4) preflight; task4 ;;
  5) task5 ;;
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
echo "  Zone      : $ZONE"
echo "  Cluster   : $CLUSTER"
echo "  Image     : ${PUSHED_IMAGE:-$IMAGE}"
echo "  Workload  : deployment/$DEPLOY"
echo "  Service   : $DEPLOY (LoadBalancer, 80 -> 8080)"
echo ""
echo "  Checkpoints:"
echo "    1. Create a Kubernetes Cluster"
echo "    2. Build and Deploy Hello World App (hello-app)"
echo "    3. Allow external traffic to hello-app deployment"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    kubectl delete svc $DEPLOY --ignore-not-found"
echo "    gcloud container clusters delete $CLUSTER --zone=$ZONE --quiet"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
