# gcp-arcade

Automation for **Google Cloud Arcade** / Cloud Skills Boost challenge labs.

Currently: **GSP321 — Develop Your Google Cloud Network**

The original `chlenge.sh` floating around (PerkVerse / Google Cloud Arcade) is a
straight-line script that breaks on two counts:

1. It creates the uptime check ~2 seconds after the Kubernetes `Service` is
   applied. A GKE `LoadBalancer` takes 2–5 minutes to get an external IP, so the
   IP comes back **empty** and the API rejects the check with
   `INVALID_ARGUMENT: uptime_url check is missing a host; uptime_url check has malformed host`.
2. It omits the `project_id` label, which the `uptime_url` monitored resource
   descriptor requires.

This version fixes both, and is idempotent so you can re-run it after a
partial failure.

---

## Quick start

In **Google Cloud Shell** (the arrow icon in the GCP console top-right):

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh
chmod +x gsp321.sh
./gsp321.sh
```

Or in one line, no file needed:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh)
```

Hit **Check my progress** on each task in the lab console as it turns green.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | `$ZONE` or `us-central1-a` | Zone for the bastion + GKE cluster |
| `--region REGION` | derived from zone | Region for VPC subnets + Cloud SQL |
| `--workdir PATH` | `$HOME/gsp321` | Where manifests are staged |
| `--timeout MINUTES` | `10` | How long to wait for the LoadBalancer IP |
| `--skip-monitor` | off | Skip Task 8 |
| `--skip-iam` | off | Skip Task 9 |
| `-h, --help` | | Usage |

---

## What it provisions

| # | Task | Resources |
|---|---|---|
| 1 | Development VPC (manual) | `griffin-dev-vpc` + `griffin-dev-wp` `192.168.16.0/20` + `griffin-dev-mgmt` `192.168.32.0/20` |
| 2 | Production VPC (Deployment Manager) | `prod-network` deployment → `griffin-prod-vpc` + `griffin-prod-wp` `192.168.48.0/20` + `griffin-prod-mgmt` `192.168.64.0/20` |
| 3 | Bastion host | dual-homed `bastion` VM, `fw-ssh-dev` / `fw-ssh-prod` |
| 4 | Cloud SQL | `griffin-dev-db` (MySQL 5.7, falls back to 8.0), db `wordpress`, user `wp_user` |
| 5 | Kubernetes | `griffin-dev` GKE, `e2-standard-4` ×2 nodes |
| 6 | Prepare cluster | 200Gi PVC, `database` secret, `cloud-sql-proxy` SA + key, `cloudsql-instance-credentials` secret |
| 7 | WordPress | `wordpress` Deployment + `wordpress` LoadBalancer Service |
| 8 | Monitoring | `wordpress-uptime-check` uptime check against the LB IP |
| 9 | Access for engineer | promotes every `roles/viewer` user to `roles/editor` |

---

## The Task 8 fix

```bash
# wait for the LoadBalancer to actually have an IP
WP_IP=""
until [ -n "$WP_IP" ]; do
  WP_IP=$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$WP_IP" ] || sleep 15
done

# uptime_url needs BOTH project_id and host
gcloud monitoring uptime create wordpress-uptime-check \
  --resource-type=uptime-url \
  --resource-labels="host=${WP_IP},project_id=${PROJECT_ID}"
```

`uptime_url` monitored resource labels, per
[Google's monitored resource descriptors](https://cloud.google.com/monitoring/api/resources):

```
uptime_url
  project_id  The identifier of the GCP project
  host        The hostname or IP address of the check
```

---

## Troubleshooting

### "no external IP on service/wordpress"

The LoadBalancer never got an address. The script prints diagnostics; run them
by hand:

```bash
kubectl get svc wordpress -o wide
kubectl describe svc wordpress | tail -25
kubectl get pods -o wide
kubectl get pvc
```

| Symptom | Cause | Fix |
|---|---|---|
| `Creating LoadBalancer` | normal | wait 3–5 min, re-run the script |
| pod `CrashLoopBackOff` | cloudsql-proxy sidecar can't reach the DB | check `INSTANCE_ID` in `wp-deployment.yaml` and that the `cloudsql-instance-credentials` secret exists |
| PVC `Pending` | volume not bound | `kubectl apply -f ~/gsp321/wp-k8s/wp-env.yaml` |
| `service not found` | `wp-service.yaml` never applied | `kubectl apply -f ~/gsp321/wp-k8s/wp-service.yaml` |
| `context deadline exceeded` | stale cluster creds | `gcloud container clusters get-credentials griffin-dev --zone $ZONE` |

### `PERMISSION_DENIED` on Task 8 or 9

You're signed in as the **second lab account**, which only has Viewer. Task 8
and Task 9 both need Editor. Either switch to the primary account, or:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$(gcloud config get-value account)" --role=roles/editor
```

### `MYSQL_5_7` rejected

Some newer projects don't allow 5.7. The script retries with `MYSQL_8_0`
automatically — or force it:

```bash
SQL_VERSION=MYSQL_8_0 ./gsp321.sh
```

### Service account key creation blocked

`gcloud iam service-accounts keys create` fails under org policies that restrict
key creation. The script reuses `key.json` if it already exists, so don't
delete it between runs.

---

## Manual commands

If you'd rather run each task by hand, the exact commands are in
[`TASKS.md`](./TASKS.md).

---

## Layout

```
gsp321.sh   # the script
TASKS.md    # the same thing, task by task, for manual runs
README.md   # this file
```

## Credits

Lab content and manifests come from the public
`gs://cloud-training/gsp321/` bucket. The original one-shot script was
published by PerkVerse for Google Cloud Arcade; this repo is a corrected,
idempotent rewrite that fixes the uptime-check race condition.

> **Reminder:** this provisions real billable GCP resources — a GKE cluster, a
> Cloud SQL instance, and a load balancer. Tear them down when you're done:
> `gcloud container clusters delete griffin-dev --zone $ZONE` and
> `gcloud sql instances delete griffin-dev-db`.
