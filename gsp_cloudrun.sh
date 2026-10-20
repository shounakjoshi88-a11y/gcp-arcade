#!/usr/bin/env bash
# =============================================================================
#  "Hello Cloud Run"
#  Google Cloud Arcade / Cloud Skills Boost lab.
#
#  Builds a small Node.js/Express app, containerises it, pushes the image to
#  Artifact Registry and deploys it to Cloud Run.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloudrun.sh
#     chmod +x gsp_cloudrun.sh
#     ./gsp_cloudrun.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region R        region for Artifact Registry and Cloud Run (asked for)
#     --node-image IMG  base image for the Dockerfile (default: node:20)
#     --repo NAME       Artifact Registry repository (default: my-repository)
#     --service NAME    Cloud Run service (default: helloworld)
#     --workdir PATH    where the app is built (default: $HOME/gcp-cloudrun)
#     --task N          run only task N (3-5)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  NOTES:
#   * The three checkpoints are the repository, the uploaded image and the
#     deployed service, so the script pauses after each one.
#   * The region is assigned per lab run and cannot be read from the project,
#     so the script asks for it.
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
NODE_IMAGE="node:20"
REPO="my-repository"
SERVICE="helloworld"
IMAGE_NAME="helloworld"
ONLY_TASK=""
ASSUME_YES=0

WORKDIR="${GSP_RUN_WORKDIR:-$HOME/gcp-cloudrun}"

usage() {
  cat <<'USAGE_END'
Hello Cloud Run

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloudrun.sh
   chmod +x gsp_cloudrun.sh
   ./gsp_cloudrun.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region R        region for Artifact Registry and Cloud Run (asked for)
   --node-image IMG  base image for the Dockerfile (default: node:20)
   --repo NAME       Artifact Registry repository (default: my-repository)
   --service NAME    Cloud Run service (default: helloworld)
   --workdir PATH    where the app is built (default: $HOME/gcp-cloudrun)
   --task N          run only task N (3-5)
   --yes             do not pause for the checkpoints
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)    PROJECT_OVERRIDE="$2"; shift 2 ;;
    --region)     REGION_OVERRIDE="$2";   shift 2 ;;
    --node-image) NODE_IMAGE="$2";       shift 2 ;;
    --repo)       REPO="$2";             shift 2 ;;
    --service)    SERVICE="$2";          shift 2 ;;
    --workdir)    WORKDIR="$2";           shift 2 ;;
    --task)       ONLY_TASK="$2";        shift 2 ;;
    --yes)        ASSUME_YES=1;          shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

APPDIR="$WORKDIR/helloworld"

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

# the region is assigned per lab run - ask for it
ask_lab_region() {
  if [ -n "$REGION_OVERRIDE" ]; then REGION="$REGION_OVERRIDE"; return 0; fi
  if [ "$ASSUME_YES" = "1" ]; then REGION="${GCP_REGION:-us-central1}"; return 0; fi

  local def ans
  def="$(gcloud config get-value compute/region 2>/dev/null)"
  [ "$def" = "(unset)" ] && def=""
  [ -z "$def" ] && def="us-central1"

  echo ""
  warn "the lab assigns the region per lab run - it cannot be read from the project"
  dim "  it is on your lab setup panel (Region)."
  printf "  %sRegion%s  [%s]: " "$C_BOLD" "$C_RESET" "$def"
  read -r ans
  REGION="${ans:-$def}"
  echo ""
}

ask_lab_region
LOCATION="$REGION"
IMAGE="$LOCATION-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME"

printf "%s%s  Hello Cloud Run%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s  %srepo=%s  %sservice=%s  %simage=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_DIM" "$REPO" "$C_DIM" "$SERVICE" \
  "$C_DIM" "$IMAGE" "$C_RESET"

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
  warn "not in Cloud Shell - the region may be wrong, use --region"
fi

info "enabling the Cloud Run and Artifact Registry APIs"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

gcloud config set compute/region "$REGION" >/dev/null 2>&1
ok "compute/region set to $REGION"

mkdir -p "$APPDIR" || { err "cannot create $APPDIR"; exit 1; }
ok "workdir ready: $APPDIR"

# Run a command and show its output as it arrives. A first Cloud Run deploy
# can take several minutes while it pulls the image and creates the revision,
# and a silent wait looks exactly like a hang.
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
    elif [ $((elapsed % 30)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
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

# ---------------------------------------------------------------------------
# Task 2 - the sample application
# ---------------------------------------------------------------------------
write_app() {
  cat > "$APPDIR/package.json" <<'EOF'
{
  "name": "helloworld",
  "description": "Simple hello world sample in Node",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "Google LLC",
  "license": "Apache-2.0",
  "dependencies": {
    "express": "^4.17.1"
  }
}
EOF

  cat > "$APPDIR/index.js" <<'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  const name = process.env.NAME || 'World';
  res.send(`Hello ${name}!`);
});

app.listen(port, () => {
  console.log(`helloworld: listening on port ${port}`);
});
EOF

  cat > "$APPDIR/Dockerfile" <<EOF
# Use the official lightweight Node.js image.
# https://hub.docker.com/_/node
FROM $NODE_IMAGE

# Create and change to the app directory.
WORKDIR /usr/src/app

# Copy application dependency manifests to the container image.
# A wildcard is used to ensure copying both package.json AND package-lock.json (when available).
# Copying this first prevents re-running npm install on every code change.
COPY package*.json ./

# Install production dependencies.
# If you add a package-lock.json, speed your build by switching to 'npm ci'.
# RUN npm ci --only=production
RUN npm install --only=production

# Copy local code to the container image.
COPY . ./

# Run the web service on container startup.
CMD [ "npm", "start" ]
EOF
}

task2() {
  step "Task 2 - Write the sample application"
  write_app
  ok "wrote package.json, index.js and the Dockerfile"
  dim "    base image: $NODE_IMAGE"
}

# ---------------------------------------------------------------------------
# Task 3 - the Artifact Registry repository
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Create an Artifact Registry repository"

  if gcloud artifacts repositories describe "$REPO" --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "the repository $REPO already exists"
  else
    if gcloud artifacts repositories create "$REPO" \
         --repository-format=docker \
         --location="$LOCATION" \
         --description="Docker repository" \
         --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "created the repository $REPO in $LOCATION"
    else
      note_fail "could not create the repository"
      return 1
    fi
  fi

  info "configuring Docker to authenticate to $LOCATION-docker.pkg.dev"
  gcloud auth configure-docker "$LOCATION-docker.pkg.dev" >/dev/null 2>&1
  ok "docker is configured for Artifact Registry"
}

# ---------------------------------------------------------------------------
# Task 4 - containerise and upload
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Containerize your app and upload it to Artifact Registry"

  [ -f "$APPDIR/Dockerfile" ] || write_app

  if gcloud artifacts docker images describe "$IMAGE" --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "the image $IMAGE already exists"
  else
    info "building the image with Cloud Build (a couple of minutes)"
    if run_live "$WORKDIR/build.log" \
         gcloud builds submit --tag "$IMAGE" "$APPDIR" --project="$PROJECT_ID"; then
      ok "built and pushed $IMAGE"
    else
      note_fail "the Cloud Build failed"
      dim "  the build log is in $WORKDIR/build.log"
      return 1
    fi
  fi

  if gcloud artifacts docker images list "$IMAGE" --project="$PROJECT_ID" 2>/dev/null | grep -q "$IMAGE"; then
    ok "the image is in Artifact Registry"
  else
    warn "could not list the image back - check it in the console"
  fi

  # run it locally and check it answers, the way the lab previews it
  if command -v docker >/dev/null 2>&1; then
    info "running the image locally to check it answers"
    CONTAINER_ID="$(docker run -d -p 8080:8080 "$IMAGE" 2>/dev/null)"
    if [ -n "$CONTAINER_ID" ]; then
      sleep 5
      if curl -s --max-time 10 http://localhost:8080/ 2>/dev/null | grep -q "Hello"; then
        ok "the container answers with 'Hello World!'"
      else
        warn "the container did not answer yet"
      fi
      docker rm -f "$CONTAINER_ID" >/dev/null 2>&1
      ok "removed the local test container"
    else
      warn "could not run the container locally (this does not affect the checkpoints)"
    fi
  else
    warn "docker is not available - skipping the local test"
  fi
}

# ---------------------------------------------------------------------------
# Task 5 - deploy to Cloud Run
# ---------------------------------------------------------------------------
task5() {
  step "Task 5 - Deploy to Cloud Run"

  if gcloud run services describe "$SERVICE" --region="$LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "the service $SERVICE already exists"
  else
    info "deploying - the first revision pulls the image and can take 3-5 minutes"
    dim "  you will see gcloud's output below as it happens"
    if run_live "$WORKDIR/deploy.log" \
         gcloud run deploy "$SERVICE" \
         --image "$IMAGE" \
         --allow-unauthenticated \
         --region="$LOCATION" \
         --project="$PROJECT_ID"; then
      ok "deployed $SERVICE"
    else
      note_fail "the deployment failed"
      dim "  the deploy log is in $WORKDIR/deploy.log"
      dim "  to retry just this step:  ./gsp_cloudrun.sh --task 5"
      return 1
    fi
  fi

  local URL
  URL="$(gcloud run services describe "$SERVICE" --region="$LOCATION" --project="$PROJECT_ID" \
         --format="value(status.url)" 2>/dev/null)"
  if [ -n "$URL" ]; then
    ok "service URL: $URL"
    info "checking that it answers"
    if curl -s --max-time 20 "$URL" 2>/dev/null | grep -q "Hello"; then
      ok "the service answers with 'Hello World!'"
    else
      warn "the service did not answer yet - it may still be starting"
    fi
  else
    warn "could not read the service URL"
  fi
}

# ---------------------------------------------------------------------------
# checkpoint pause
# ---------------------------------------------------------------------------
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
# run
# ---------------------------------------------------------------------------
case "$ONLY_TASK" in
  2) task2 ;;
  3) task3 ;;
  4) task4 ;;
  5) task5 ;;
  "")
    task2
    task3
    pause_for_check 3 "Create an Artifact Registry repository"
    task4
    pause_for_check 4 "Containerize your app and upload it to Artifact Registry"
    task5
    pause_for_check 5 "Deploy a containerized application on Cloud Run"
    ;;
  *)
    err "--task must be between 2 and 5"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project  : $PROJECT_ID"
echo "  Region   : $REGION"
echo "  Repo     : $LOCATION-docker.pkg.dev/$PROJECT_ID/$REPO"
echo "  Image    : $IMAGE"
echo "  Service  : $SERVICE"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
