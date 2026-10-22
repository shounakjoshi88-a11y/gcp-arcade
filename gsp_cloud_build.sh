#!/usr/bin/env bash
# =============================================================================
#  "Working with Cloud Build"
#  Google Cloud Arcade / Cloud Skills Boost lab (focus 641631, CBL139).
#
#  Builds the whole lab:
#    1  enables the Cloud Build and Artifact Registry APIs
#    2  quickstart.sh + Dockerfile, the quickstart-docker-repo Artifact
#       Registry repository, and the first image build with --tag
#    3  cloudbuild.yaml (a custom build config) and the second image build
#    4  the modified quickstart.sh, cloudbuild2.yaml, and the build that
#       deliberately fails its test step
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloud_build.sh
#     chmod +x gsp_cloud_build.sh
#     ./gsp_cloud_build.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --region REGION   where quickstart-docker-repo lives (default: us-east4)
#     --task N          run only task N (1-4)
#     --yes             do not pause for the checkpoints
#     -h, --help        this help
#
#  CHECKPOINTS (the two graded objectives):
#     1. Build two container images in Cloud Build        (end of task 3)
#     2. Build and test containers with a build configuration file and
#        Cloud Build                                      (end of task 4)
#
#  NOTES:
#   * The lab text fixes the region at us-east4, and it appears twice: the
#     Artifact Registry location and the <region>-docker.pkg.dev image host.
#     --region wins, then $REGION, then us-east4.
#   * The image lives in Artifact Registry, not gcr.io:
#       <region>-docker.pkg.dev/<project>/quickstart-docker-repo/quickstart-image:tag1
#   * The last build is SUPPOSED to fail. The script treats a non-zero build
#     status there as success and says so.
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

usage() {
  cat <<'USAGE_END'
Working with Cloud Build

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloud_build.sh
   chmod +x gsp_cloud_build.sh
   ./gsp_cloud_build.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --region REGION   where quickstart-docker-repo lives (default: us-east4)
   --task N          run only task N (1-4)
   --yes             do not pause for the checkpoints
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_OVERRIDE="$2"; shift 2 ;;
    --region)  REGION_OVERRIDE="$2";  shift 2 ;;
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
# region
# ---------------------------------------------------------------------------

if [ -n "$REGION_OVERRIDE" ]; then
  REGION="$REGION_OVERRIDE"
  info "region from --region: $REGION"
elif [ -n "${REGION:-}" ]; then
  info "the lab's region came from the environment: $REGION"
else
  REGION="us-east4"
  info "the lab fixes the region: $REGION"
  dim "  the lab text spells us-east4 out in the repository and image paths"
fi

WORKDIR="${WORKDIR:-$HOME/gsp-cbl139}"
mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="."
cd "$WORKDIR" 2>/dev/null || true

printf "%s%s  Working with Cloud Build%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %sregion=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$REGION" "$C_RESET"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
REPO="quickstart-docker-repo"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/quickstart-image:tag1"

repo_exists()   { gcloud artifacts repositories describe "$REPO" --location="$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; }
api_enabled()   { gcloud services list --enabled --project "$PROJECT_ID" --format="value(config.name)" 2>/dev/null | grep -qx "$1"; }

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
      printf "    ... still building (%ss elapsed)\n" "$elapsed"
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

write_quickstart_plain() {
  cat > "$WORKDIR/quickstart.sh" <<'EOF'
#!/bin/sh
echo "Hello, world! The time is $(date)."
EOF
  chmod +x "$WORKDIR/quickstart.sh"
}

write_quickstart_with_test() {
  cat > "$WORKDIR/quickstart.sh" <<'EOF'
#!/bin/sh
if [ -z "$1" ]
then
	echo "Hello, world! The time is $(date)."
	exit 0
else
	exit 1
fi
EOF
  chmod +x "$WORKDIR/quickstart.sh"
}

write_dockerfile() {
  cat > "$WORKDIR/Dockerfile" <<'EOF'
FROM alpine
COPY quickstart.sh /
CMD ["/quickstart.sh"]
EOF
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
  warn "not in Cloud Shell - Cloud Build uploads the working directory from here"
fi

info "working directory: $WORKDIR"
dim "  Dockerfile, quickstart.sh, cloudbuild.yaml and cloudbuild2.yaml live here"

# ---------------------------------------------------------------------------
# Task 1 - the APIs
# ---------------------------------------------------------------------------
task1() {
  step "Task 1 - Confirm that needed APIs are enabled"

  local api
  for api in cloudbuild.googleapis.com artifactregistry.googleapis.com; do
    if api_enabled "$api"; then
      ok "$api is enabled"
    else
      info "enabling $api"
      if gcloud services enable "$api" --project "$PROJECT_ID" --quiet >/dev/null 2>&1; then
        ok "enabled $api"
      else
        note_fail "could not enable $api"
      fi
    fi
  done

  dim "  Cloud Build's own service account also needs to write to Artifact Registry"
  local number
  number="$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null)"
  if [ -n "$number" ]; then
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${number}@cloudbuild.gserviceaccount.com" \
      --role="roles/artifactregistry.writer" \
      --condition=None --quiet >/dev/null 2>&1 && ok "the Cloud Build service account can push images" \
      || dim "  (the binding was already there or is not needed)"
  fi
}

# ---------------------------------------------------------------------------
# Task 2 - Dockerfile + the first build
# ---------------------------------------------------------------------------
task2() {
  step "Task 2 - Building containers with DockerFile and Cloud Build"

  write_quickstart_plain
  ok "quickstart.sh written and made executable"

  write_dockerfile
  ok "Dockerfile written (alpine + /quickstart.sh)"

  if repo_exists; then
    ok "the Artifact Registry repository $REPO already exists in $REGION"
  else
    info "creating the Artifact Registry repository $REPO in $REGION"
    local created=0 i
    for i in 1 2 3; do
      if gcloud artifacts repositories create "$REPO" \
           --repository-format=docker --location="$REGION" \
           --description="Docker repository" \
           --project "$PROJECT_ID" --quiet > "$WORKDIR/repo-create.log" 2>&1; then
        created=1
        break
      fi
      # the Artifact Registry API can still be propagating for a minute
      sleep 10
    done
    if [ "$created" -eq 1 ]; then
      ok "created $REPO"
    else
      err "gcloud said: $(grep -viE '^(WARNING|Note)' "$WORKDIR/repo-create.log" 2>/dev/null | tail -n 2 | tr '\n' ' ')"
      note_fail "could not create the Artifact Registry repository $REPO in $REGION"
    fi
  fi

  info "build 1/3 - gcloud builds submit --tag (uses the Dockerfile)"
  dim "  $IMAGE"
  if ! repo_exists; then
    warn "the repository is still missing, so this push is expected to fail"
    dim "  gcloud's complaint: $(tail -n 2 "$WORKDIR/repo-create.log" 2>/dev/null | tr '\n' ' ')"
  fi
  if run_live "$WORKDIR/build1.log" \
       gcloud builds submit --project "$PROJECT_ID" --tag "$IMAGE" .; then
    ok "the first image is built and pushed to Artifact Registry"
  else
    err "$(grep -iE 'error|failed' "$WORKDIR/build1.log" 2>/dev/null | tail -n 3 | tr '\n' ' ')"
    note_fail "the first Cloud Build failed - see $WORKDIR/build1.log"
  fi
}

# ---------------------------------------------------------------------------
# Task 3 - cloudbuild.yaml + the second build (checkpoint 1)
# ---------------------------------------------------------------------------
task3() {
  step "Task 3 - Building containers with a build configuration file and Cloud Build"

  cat > "$WORKDIR/cloudbuild.yaml" <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '$IMAGE', '.' ]
images:
- '$IMAGE'
EOF
  ok "cloudbuild.yaml written with $REGION substituted"
  dim "  the \$PROJECT_ID substitution is left to Cloud Build, as the lab does"

  info "build 2/3 - gcloud builds submit --config cloudbuild.yaml"
  if run_live "$WORKDIR/build2.log" \
       gcloud builds submit --project "$PROJECT_ID" --config cloudbuild.yaml .; then
    ok "the second image is built and pushed - two versions of quickstart-image now exist"
  else
    err "$(grep -iE 'error|failed' "$WORKDIR/build2.log" 2>/dev/null | tail -n 3 | tr '\n' ' ')"
    note_fail "the second Cloud Build failed - see $WORKDIR/build2.log"
  fi

  dim "  Cloud Build > History in the console now lists both builds"

  pause_for_check 3 "Build two container images in Cloud Build"
}

# ---------------------------------------------------------------------------
# Task 4 - the failing test build (checkpoint 2)
# ---------------------------------------------------------------------------
task4() {
  step "Task 4 - Building and testing containers with a build configuration file and Cloud Build"

  write_quickstart_with_test
  ok "quickstart.sh now exits 1 when it is passed an argument"
  dim "  that is the test the next build runs"

  cat > "$WORKDIR/cloudbuild2.yaml" <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '$IMAGE', '.' ]
- name: '$IMAGE'
  args: ['fail']
images:
- '$IMAGE'
EOF
  ok "cloudbuild2.yaml written"
  dim "  step 2 runs the image it just built, with ['fail'], so the build fails"

  info "build 3/3 - this one is supposed to fail"
  if run_live "$WORKDIR/build3.log" \
       gcloud builds submit --project "$PROJECT_ID" --config cloudbuild2.yaml .; then
    warn "the third build passed - the lab expects it to fail its test step"
    dim "  the lab's grader wants the FAILURE, so check that cloudbuild2.yaml"
    dim "  runs the image with ['fail'] and that quickstart.sh exits 1 on an argument"
    note_fail "the test build did not fail as the lab expects"
  else
    ok "the build failed on its test step, exactly as the lab expects"
    grep -iE 'BUILD FAILURE|completed with status' "$WORKDIR/build3.log" 2>/dev/null | tail -n 2 | sed 's/^/    /'
    echo "    echo \$? in the lab answers non-zero for this build"
  fi

  pause_for_check 4 "Build and test containers with a build configuration file and Cloud Build"
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
    task1
    task2
    task3
    task4
    ;;
  *)
    err "--task must be between 1 and 4"
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project          : $PROJECT_ID"
echo "  Region           : $REGION"
echo "  Repository       : $REPO (Artifact Registry, docker)"
echo "  Image            : $IMAGE"
echo "  Files            : $WORKDIR/{quickstart.sh,Dockerfile,cloudbuild.yaml,cloudbuild2.yaml}"
echo ""
echo "  Checkpoints:"
echo "    1. Build two container images in Cloud Build"
echo "    2. Build and test containers with a build configuration file and Cloud Build"
echo ""
info "the three builds in Cloud Build history"
gcloud builds list --limit=3 --project "$PROJECT_ID" \
  --format="table(status,createTime,id)" 2>/dev/null | sed 's/^/    /'
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Clean up when you are done:"
echo "    gcloud artifacts repositories delete $REPO --location=$REGION --quiet"
echo "    gcloud builds list --limit=10   # for reference"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
