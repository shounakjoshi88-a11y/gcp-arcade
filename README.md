# gcp-arcade

Automation for **Google Cloud Arcade** / Cloud Skills Boost challenge labs.

| Script | Lab | What it does |
|---|---|---|
| [`gsp321.sh`](./gsp321.sh) | **GSP321** — Develop Your Google Cloud Network | Dev + prod VPCs, bastion, Cloud SQL, GKE, WordPress, uptime check, IAM |
| [`gsp156.sh`](./gsp156.sh) | **GSP156** — Terraform Fundamentals | Installs Terraform, writes `instance.tf`, provisions a VM with Terraform |

Both scripts are **idempotent** — re-run them after any failure and they
skip whatever already exists. Both exit `0` when every step succeeded and `1`
if a step reported a failure (the rest of the lab still runs).

---

## Quick start

In **Google Cloud Shell** (the arrow icon in the GCP console top-right), in one
line, no download needed:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh)
```

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp156.sh)
```

Or download and run:

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh
chmod +x gsp321.sh
./gsp321.sh
```

---

## Auto-detection

Both scripts work out of the box because they read the lab's own settings:

- **project** — `gcloud config get-value project`, falling back to
  `$DEVSHELL_PROJECT_ID`
- **region / zone** — `gcloud config get-value compute/zone` and
  `compute/region`. Cloud Skills Boost points these at the lab's own values,
  which is more reliable than any environment variable. Both are printed in
  the banner so you can spot a mismatch instantly.
- **roles** — the preflight lists the roles the active account actually holds,
  so a `roles/owner` account no longer gets a bogus "you need editor" warning

> If the zone or region in the banner does not match what the lab page says,
> pass them explicitly: `./gsp321.sh --zone us-central1-a --region us-central1`

---

## GSP321 — Develop Your Google Cloud Network

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp321.sh)
```

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
| 9 | Access for engineer | promotes the other lab account to `roles/editor` |

### The Task 8 fix

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

The upstream one-shot script read the IP about two seconds after applying the
Service, when it was still empty, so the API rejected the check with
`INVALID_ARGUMENT: uptime_url check is missing a host`.

### The Task 9 fix

`gcloud projects add-iam-policy-binding` only **adds** a binding. The lab's own
instructions are "IAM → the second user → Edit → Role → Editor → **Save**",
and the console *replaces* the role. The script therefore grants editor **and**
removes the leftover `roles/viewer` binding, so the account ends up with the
same state the console would produce.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | `gcloud config compute/zone` | Zone for the bastion + GKE cluster |
| `--region REGION` | `gcloud config compute/region` | Region for VPC subnets + Cloud SQL |
| `--workdir PATH` | `$HOME/gsp321` | Where manifests are staged |
| `--timeout MINUTES` | `10` | How long to wait for the LoadBalancer IP |
| `--engineer EMAIL` | any other viewer account | The additional engineer account |
| `--skip-monitor` | off | Skip Task 8 |
| `--skip-iam` | off | Skip Task 9 |
| `-h, --help` | | Usage |

### Troubleshooting

**"no external IP on service/wordpress"** — the LoadBalancer never got an
address. The script prints diagnostics; run them by hand:

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

**`PERMISSION_DENIED` on Task 8 or 9** — check the roles the active account
actually holds:

```bash
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="value(bindings.role,bindings.members)" | grep "$ACCOUNT"
```

`roles/owner` is enough. If you really only have `roles/viewer`:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$(gcloud config get-value account)" --role=roles/editor
```

**`MYSQL_5_7` rejected** — some newer projects don't allow 5.7. The script
retries with `MYSQL_8_0` automatically, or force it:

```bash
SQL_VERSION=MYSQL_8_0 ./gsp321.sh
```

**Service account key creation blocked** — `gcloud iam service-accounts keys
create` fails under org policies that restrict key creation. The script reuses
`key.json` if it already exists, so don't delete it between runs.

---

## GSP156 — Terraform Fundamentals

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp156.sh)
```

Installs Terraform, writes `instance.tf`, then runs `init` → `plan` → `apply`
to create a VM named `terraform` (`e2-medium`) in the lab's zone. The scored
checkpoint is *"Create a VM instance in <zone> with Terraform"*.

### What it resolves for you

The lab template injects three placeholders that the script discovers at
runtime:

| Placeholder | How it's found |
|---|---|
| `Project ID` | `gcloud config get-value project` |
| `zone` | `gcloud config get-value compute/zone` |
| `Debian image ID` | the project's common instance metadata (startup script), falling back to the newest Debian image in `debian-cloud` |

### Terraform installation

The lab wants Terraform installed *and persisted* across Cloud Shell sessions.
The script downloads the official release binary to `~/bin` and appends this to
`~/.customize_environment` (backing up any existing file first):

```bash
export PATH="$HOME/bin:$PATH"
```

The version is resolved from the HashiCorp releases API at run time, with a
pinned fallback.

Want the lab's verbatim HashiCorp apt-repository method instead?

```bash
./gsp156.sh --install-method apt
```

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | `gcloud config compute/zone` | Zone for the instance |
| `--region REGION` | `gcloud config compute/region` | Region (informational) |
| `--image IMAGE` | auto-detected Debian image | Boot disk image |
| `--machine-type T` | `e2-medium` | Machine type |
| `--name NAME` | `terraform` | Instance name |
| `--workdir PATH` | `$HOME/gsp156` | Where `instance.tf` lives |
| `--install-method M` | `binary` | `binary` or `apt` |
| `--destroy` | off | Destroy the infrastructure and exit |
| `--skip-install` | off | Assume terraform is already on PATH |
| `-h, --help` | | Usage |

### The generated `instance.tf`

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_compute_instance" "default" {
  project      = "PROJECT_ID"
  zone         = "ZONE"
  name         = "terraform"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "DEBIAN_IMAGE"
    }
  }
  network_interface {
    network = "default"
    access_config {
    }
  }
}
```

### Troubleshooting

**"could not find default credentials"** — Cloud Shell is normally
pre-authenticated for Terraform. If you hit this:

```bash
gcloud auth application-default login
```

**`terraform init` fails to download the provider** — a proxy or network
restriction blocks `releases.hashicorp.com` / `registry.terraform.io`. Retry,
or set `TF_PLUGIN_CACHE_DIR` to a writable directory.

**The instance exists but Terraform doesn't know about it** — the script
imports it into state automatically on the next run. By hand:

```bash
cd ~/gsp156
terraform import google_compute_instance.default terraform
```

**Clean up**

```bash
./gsp156.sh --destroy
```

### Task 3 — the two multiple-choice questions

1. *Terraform enables you to safely and predictably create, change, and improve infrastructure.* → **True**
2. *With Terraform, you can create your own custom provider plugins.* → **False**

---

## Layout

```
gsp321.sh     # GSP321 - Develop Your Google Cloud Network
gsp156.sh     # GSP156 - Terraform Fundamentals
TASKS.md      # GSP321, task by task, for manual runs
TASKS156.md   # GSP156, task by task, for manual runs
README.md     # this file
```

## Credits

Lab content and manifests come from the public `gs://spls/gsp321/` bucket
(current) and `gs://cloud-training/gsp321/` (older). The original one-shot
script for GSP321 was published by PerkVerse for Google Cloud Arcade; this
repo is a corrected, idempotent rewrite that fixes the uptime-check race
condition and the IAM role replacement.

> **Reminder:** these provision real billable GCP resources — a GKE cluster, a
> Cloud SQL instance, a load balancer, a VM. Tear them down when you're done:
> `./gsp321.sh` resources can be removed with the `gcloud` commands in
> `TASKS.md`, and `./gsp156.sh --destroy` removes the Terraform-managed VM.
