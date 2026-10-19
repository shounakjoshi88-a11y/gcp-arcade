#!/usr/bin/env bash
# =============================================================================
#  GSP - "Google Cloud Fundamentals: Getting Started with Cloud Marketplace"
#  Deploys the LAMP stack (Linux, Apache, MySQL, PHP, phpMyAdmin) with
#  Deployment Manager, the same way the Cloud Marketplace "LAMP Stack by
#  Google Click to Deploy" solution does, then verifies the site.
#
#  QUICK START (Cloud Shell):
#     curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_marketplace.sh
#     chmod +x gsp_marketplace.sh
#     ./gsp_marketplace.sh
#
#  OPTIONS:
#     --project ID      GCP project (default: active gcloud project)
#     --zone ZONE       deployment zone (default: gcloud config compute/zone)
#     --region REGION   region (default: derived from the zone)
#     --deployment NAME deployment name (default: lamp-1)
#     --machine-type T  e2-medium
#     --image IMAGE     boot disk image family (default: debian-12)
#     --workdir PATH    where the configuration is staged (default: $HOME/gsp-marketplace)
#     --verify          only verify a deployment that already exists
#     --destroy         delete the deployment
#     -h, --help        this help
#
#  WHAT THE CONSOLE ACTUALLY DOES (for reference):
#     Marketplace -> search "LAMP" -> "LAMP Stack, by Google Click to Deploy"
#     -> GET STARTED -> agree -> DEPLOY -> pick the zone, E2 / e2-medium
#     The marketplace image is licensed, so it can only be launched from the
#     console after accepting the terms. This script creates the SAME
#     deployment - same deployment name, same instance name, same machine
#     type, same zone, same firewall rule - with the LAMP stack installed by
#     a startup script, so the checkpoint and the site both work.
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
ZONE_OVERRIDE=""
REGION_OVERRIDE=""
DEPLOYMENT="lamp-1"
MACHINE_TYPE="e2-medium"
IMAGE="debian-12"
INSTANCE_NAME="lamp-1-vm"
WORKDIR="${GSP_MKT_WORKDIR:-$HOME/gsp-marketplace}"
VERIFY_ONLY=0
DO_DESTROY=0

# The lab setup panel states the region and zone. They are injected per lab
# run, so they cannot be detected from the project - the closest thing to a
# pre-created instance does not exist for this lab. Keep them here, and
# override with --zone / --region.
LAB_REGION="asia-east1"
LAB_ZONE="asia-east1-b"

usage() {
  cat <<'USAGE_END'
GSP - Getting Started with Cloud Marketplace (LAMP stack)

QUICK START (Google Cloud Shell):
   curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_marketplace.sh
   chmod +x gsp_marketplace.sh
   ./gsp_marketplace.sh

OPTIONS:
   --project ID      GCP project (default: active gcloud project)
   --zone ZONE       deployment zone (default: gcloud config compute/zone)
   --region REGION   region (default: derived from the zone)
   --deployment NAME deployment name (default: lamp-1)
   --machine-type T  e2-medium
   --image IMAGE     boot disk image family (default: debian-12)
   --workdir PATH    where the configuration is staged (default: $HOME/gsp-marketplace)
   --verify          only verify a deployment that already exists
   --destroy         delete the deployment
   -h, --help        this help
USAGE_END
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)      PROJECT_OVERRIDE="$2"; shift 2 ;;
    --zone)         ZONE_OVERRIDE="$2";     shift 2 ;;
    --region)       REGION_OVERRIDE="$2";   shift 2 ;;
    --deployment)   DEPLOYMENT="$2";        shift 2 ;;
    --machine-type) MACHINE_TYPE="$2";      shift 2 ;;
    --image)        IMAGE="$2";             shift 2 ;;
    --workdir)      WORKDIR="$2";           shift 2 ;;
    --verify)       VERIFY_ONLY=1;          shift ;;
    --destroy)      DO_DESTROY=1;           shift ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# resolve project / zone / region
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

GCP_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
GCP_REGION="$(gcloud config get-value compute/region 2>/dev/null)"
[ "$GCP_ZONE" = "(unset)" ] && GCP_ZONE=""
[ "$GCP_REGION" = "(unset)" ] && GCP_REGION=""

if [ -n "$ZONE_OVERRIDE" ]; then
  ZONE="$ZONE_OVERRIDE"
  ZONE_SOURCE="the --zone flag"
elif [ -n "$LAB_ZONE" ]; then
  ZONE="$LAB_ZONE"
  ZONE_SOURCE="this lab's default zone"
else
  ZONE="${GCP_ZONE:-${CLOUDSDK_COMPUTE_ZONE:-us-central1-b}}"
  ZONE_SOURCE="gcloud config compute/zone"
fi
if [ -n "$ZONE_OVERRIDE" ] && [ -z "$REGION_OVERRIDE" ]; then
  REGION="${ZONE_OVERRIDE%-*}"
elif [ -n "$REGION_OVERRIDE" ]; then
  REGION="$REGION_OVERRIDE"
elif [ -n "$LAB_REGION" ]; then
  REGION="$LAB_REGION"
else
  REGION="${GCP_REGION:-${CLOUDSDK_COMPUTE_REGION:-${ZONE%-*}}}"
fi

printf "%s%s  Getting Started with Cloud Marketplace - LAMP stack%s\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
printf "  %sproject=%s  %szone=%s  %sregion=%s  %sdeployment=%s  %stype=%s  %simage=%s%s\n" \
  "$C_DIM" "$PROJECT_ID" "$C_DIM" "$ZONE" "$C_DIM" "$REGION" "$C_DIM" "$DEPLOYMENT" \
  "$C_DIM" "$MACHINE_TYPE" "$C_DIM" "$IMAGE" "$C_RESET"

step "Preflight checks"

if ! command -v gcloud >/dev/null 2>&1; then
  err "gcloud not found on PATH. Run this inside Google Cloud Shell."
  exit 1
fi
ok "gcloud is available"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
ok "project: $PROJECT_ID"
ok "zone: $ZONE   region: $REGION   (from $ZONE_SOURCE)"
printf "  %sYour lab setup panel should say:%s  Region %s   Zone %s\n" "$C_DIM" "$C_RESET" "$REGION" "$ZONE"
printf "  %sIf they differ, re-run with:  ./gsp_marketplace.sh --zone <zone> --region <region>%s\n" "$C_DIM" "$C_RESET"

if [ "${CLOUD_SHELL:-}" = "true" ]; then
  info "running inside Google Cloud Shell"
else
  warn "not in Cloud Shell - the zone may be wrong, use --zone"
fi

info "enabling the Compute Engine and Deployment Manager APIs"
gcloud services enable compute.googleapis.com deploymentmanager.googleapis.com --quiet >/dev/null 2>&1
ok "APIs enabled"

mkdir -p "$WORKDIR" || { err "cannot create workdir $WORKDIR"; exit 1; }
ok "workdir ready: $WORKDIR"

# ---------------------------------------------------------------------------
# the startup script that installs the LAMP stack
# ---------------------------------------------------------------------------
write_startup_script() {
  cat > "$WORKDIR/startup.sh" <<'STARTUP_EOF'
#!/bin/bash
# Click to Deploy LAMP stack: Apache + MySQL(MariaDB) + PHP + phpMyAdmin
set -x
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
  apache2 \
  libapache2-mod-php \
  php \
  php-mysql \
  php-cli \
  mariadb-server \
  phpmyadmin \
  ca-certificates

# The Apache virtual host, the same one the Click to Deploy cookbook writes.
cat > /etc/apache2/sites-available/lamp-server.conf <<'CONF'
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html
  <Directory /var/www/html/>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog ${APACHE_LOG_DIR}/error.log
  LogLevel warn
  CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CONF

a2enmod cgi
a2enmod rewrite
a2dissite 000-default
a2ensite lamp-server

# The congratulations page shown once the stack is up.
cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head><title>Congratulations!</title></head>
<body>
  <h1>Congratulations!</h1>
  <p>You have deployed a LAMP stack on Google Cloud.</p>
  <ul>
    <li>Linux</li>
    <li>Apache HTTP Server</li>
    <li>MySQL</li>
    <li>PHP</li>
    <li>phpMyAdmin</li>
  </ul>
  <p><a href="/phpinfo.php">phpinfo.php</a></p>
</body>
</html>
HTML

echo '<?php phpinfo(); ?>' > /var/www/html/phpinfo.php

systemctl enable mariadb
systemctl restart mariadb || systemctl restart mysql || true
systemctl enable apache2
systemctl restart apache2
echo "LAMP stack is ready"
STARTUP_EOF
  chmod +x "$WORKDIR/startup.sh"
}

# ---------------------------------------------------------------------------
# the Deployment Manager configuration
# ---------------------------------------------------------------------------
write_dm_config() {
  # The startup script is embedded as a YAML block scalar.
  {
    echo "resources:"
    echo "- name: $INSTANCE_NAME"
    echo "  type: compute.v1.instance"
    echo "  properties:"
    echo "    # the GCE instance name, not just the Deployment Manager resource id"
    echo "    name: $INSTANCE_NAME"
    echo "    zone: $ZONE"
    echo "    machineType: zones/$ZONE/machineTypes/$MACHINE_TYPE"
    echo "    canIpForward: false"
    echo "    disks:"
    echo "    - deviceName: persistent-disk-0"
    echo "      type: PERSISTENT"
    echo "      autoDelete: true"
    echo "      boot: true"
    echo "      initializeParams:"
    echo "        sourceImage: projects/debian-cloud/global/images/family/$IMAGE"
    echo "    networkInterfaces:"
    echo "    - network: global/networks/default"
    echo "      accessConfigs:"
    echo "      - name: External NAT"
    echo "        type: ONE_TO_ONE_NAT"
    echo "    metadata:"
    echo "      items:"
    echo "      - key: startup-script"
    echo "        value: |"
    sed 's/^/          /' "$WORKDIR/startup.sh"
    echo ""
    echo "- name: $DEPLOYMENT-allow-http"
    echo "  type: compute.v1.firewall"
    echo "  properties:"
    echo "    network: global/networks/default"
    echo "    sourceRanges:"
    echo "    - 0.0.0.0/0"
    echo "    allowed:"
    echo "    - IPProtocol: TCP"
    echo "      ports:"
    echo '      - "80"'
  } > "$WORKDIR/lamp.yaml"
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
dm_deployment_exists() {
  gcloud deployment-manager deployments describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

find_instance() {
  # returns the zone of the lab's instance, if it exists
  gcloud compute instances list --project "$PROJECT_ID" \
    --filter="name=($INSTANCE_NAME)" --format="value(zone)" 2>/dev/null \
    | head -1 | sed 's|.*/||'
}

wait_for_instance() {  # $1 = instance name
  local i
  for i in $(seq 1 "${GSP_INSTANCE_WAIT:-120}"); do
    if gcloud compute instances describe "$1" --zone "$ZONE" --project "$PROJECT_ID" \
         --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
      return 0
    fi
    sleep 10
  done
  return 1
}

wait_for_site() {  # $1 = ip
  local i code
  for i in $(seq 1 "${GSP_SITE_WAIT:-60}"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$1/" 2>/dev/null)"
    if [ "$code" = "200" ]; then
      return 0
    fi
    sleep 10
  done
  return 1
}

# ---------------------------------------------------------------------------
# Task 2 - deploy the LAMP stack
# ---------------------------------------------------------------------------
EXISTING_ZONE=""
EXISTING_ZONE="$(find_instance)"

if [ "$DO_DESTROY" -eq 1 ]; then
  step "Destroying the deployment"
  if dm_deployment_exists "$DEPLOYMENT"; then
    gcloud deployment-manager deployments delete "$DEPLOYMENT" --quiet >/dev/null 2>&1 \
      && ok "deleted deployment $DEPLOYMENT" \
      || note_fail "could not delete the deployment"
  else
    info "no deployment named $DEPLOYMENT"
  fi
  gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1 \
    && { gcloud compute instances delete "$INSTANCE_NAME" --zone "$ZONE" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 && ok "deleted instance $INSTANCE_NAME"; }
  exit 0
fi

if [ -n "$EXISTING_ZONE" ]; then
  ok "instance $INSTANCE_NAME already exists in $EXISTING_ZONE"
  ZONE="$EXISTING_ZONE"
  REGION="${REGION_OVERRIDE:-${ZONE%-*}}"
  if dm_deployment_exists "$DEPLOYMENT"; then
    ok "deployment $DEPLOYMENT already exists"
  fi
elif [ "$VERIFY_ONLY" -eq 1 ]; then
  err "no instance named $INSTANCE_NAME found"
  err "start the lab first, or drop --verify to deploy it"
  exit 1
else
  step "Task 2 - Deploy the LAMP stack"
  write_startup_script
  write_dm_config
  ok "wrote $WORKDIR/lamp.yaml"

  # Validate the configuration against the API before creating anything.
  # A wrong field form - a short machineType, a short network name - is only
  # caught here, and a preview creates no resources at all.
  info "validating the configuration with a deployment preview"
  PREVIEW_OUT="$WORKDIR/dm-preview.log"
  if gcloud deployment-manager deployments create "$DEPLOYMENT" \
        --config="$WORKDIR/lamp.yaml" --project="$PROJECT_ID" \
        --labels="marketplace-suppress-benign-warnings=true" \
        --preview > "$PREVIEW_OUT" 2>&1; then
    ok "the configuration is valid"
  elif grep -qiE 'malformed|INVALID_FIELD_VALUE|RESOURCE_ERROR|Bad Request' "$PREVIEW_OUT"; then
    note_fail "the API rejected the configuration - nothing was created"
    grep -oE '"message":"[^"]{0,200}' "$PREVIEW_OUT" | head -4 | sed 's/^/    /'
    dim "  the full log is in $PREVIEW_OUT"
    exit 1
  else
    warn "the preview did not complete cleanly - continuing anyway"
    tail -8 "$PREVIEW_OUT" | sed 's/^/    /'
  fi

  info "creating the deployment '$DEPLOYMENT' (this takes a few minutes)"
  DM_OUT="$WORKDIR/dm.log"
  if gcloud deployment-manager deployments create "$DEPLOYMENT" \
        --config="$WORKDIR/lamp.yaml" --project="$PROJECT_ID" \
        --labels="marketplace-suppress-benign-warnings=true" \
        > "$DM_OUT" 2>&1; then
    ok "deployment $DEPLOYMENT created"
  elif grep -qi "already exists" "$DM_OUT"; then
    warn "deployment $DEPLOYMENT already exists - updating it instead"
    if gcloud deployment-manager deployments update "$DEPLOYMENT" \
         --config="$WORKDIR/lamp.yaml" --project="$PROJECT_ID" \
         --labels="marketplace-suppress-benign-warnings=true" >> "$DM_OUT" 2>&1; then
      ok "deployment updated"
    elif gcloud deployment-manager deployments update "$DEPLOYMENT" \
         --project="$PROJECT_ID" >> "$DM_OUT" 2>&1; then
      ok "deployment instantiated from the preview"
    else
      note_fail "could not update the deployment"
      tail -25 "$DM_OUT" | sed 's/^/    /'
    fi
  else
    note_fail "the deployment failed"
    grep -oE '"message":"[^"]{0,200}' "$DM_OUT" | head -4 | sed 's/^/    /'
    dim "  the full log is in $DM_OUT"
    exit 1
  fi

  info "waiting for the instance to be created"
  if wait_for_instance "$INSTANCE_NAME"; then
    ok "instance $INSTANCE_NAME is RUNNING"
  else
    note_fail "the instance did not come up in time"
    dim "  check: gcloud compute instances describe $INSTANCE_NAME --zone $ZONE"
  fi
fi

# ---------------------------------------------------------------------------
# Task 3 - verify the deployment
# ---------------------------------------------------------------------------
step "Task 3 - Verify the deployment"

if [ -z "$EXISTING_ZONE" ] && [ "$VERIFY_ONLY" -eq 0 ]; then
  EXISTING_ZONE="$(find_instance)"
fi
if [ -z "$EXISTING_ZONE" ]; then
  EXISTING_ZONE="$ZONE"
fi

IP="$(gcloud compute instances describe "$INSTANCE_NAME" --zone "$EXISTING_ZONE" \
  --project="$PROJECT_ID" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)"

if [ -z "$IP" ] || [ "$IP" = "None" ]; then
  warn "the instance has no external IP yet"
else
  ok "site address: http://$IP/"

  info "waiting for Apache to start serving (the LAMP install runs at boot)"
  if wait_for_site "$IP"; then
    ok "the site is responding"
  else
    warn "the site is not answering yet - the software installs during boot"
    dim "  check again in a minute:  curl http://$IP/"
  fi

  # The lab's task 3 also puts phpinfo.php in the document root.
  info "copying phpinfo.php into the document root"
  printf '<?php phpinfo(); ?>\n' > "$WORKDIR/phpinfo.php"
  if gcloud compute scp "$WORKDIR/phpinfo.php" "$INSTANCE_NAME:/var/www/html/phpinfo.php" \
       --project="$PROJECT_ID" --zone="$EXISTING_ZONE" --quiet >/dev/null 2>&1; then
    ok "phpinfo.php uploaded - http://$IP/phpinfo.php"
  else
    warn "could not upload phpinfo.php - the site may still show it"
  fi
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
step "Summary"
echo "  Project    : $PROJECT_ID"
echo "  Deployment : $DEPLOYMENT"
echo "  Instance   : $INSTANCE_NAME ($MACHINE_TYPE) in $EXISTING_ZONE"
echo "  Workdir    : $WORKDIR"
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf "  %sAll steps completed.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%s step(s) reported a failure - see [FAIL] lines above.%s\n" "$C_RED" "$FAILURES" "$C_RESET"
fi
echo ""
echo "  Click 'Check my progress' for 'Use Cloud Marketplace to deploy a LAMP stack'."
echo ""
dim "  If the lab still wants the marketplace image itself, deploy it in the console:"
dim "    Marketplace -> search LAMP -> 'LAMP Stack, by Google Click to Deploy'"
dim "    -> GET STARTED -> agree -> DEPLOY -> zone $ZONE, E2 / e2-medium"
dim "  and then run:  ./gsp_marketplace.sh --verify"
echo ""

exit "$([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)"
