# gcp-arcade

Automation for **Google Cloud Arcade** / Cloud Skills Boost challenge labs.

| Script | Lab | What it does | Score |
|---|---|---|---|
| [`gsp321.sh`](./gsp321.sh) | **GSP321** — Develop Your Google Cloud Network | Dev + prod VPCs, bastion, Cloud SQL, GKE, WordPress, uptime check, IAM | 20/20 |
| [`gsp156.sh`](./gsp156.sh) | **GSP156** — Terraform Fundamentals | Installs Terraform, writes `instance.tf`, provisions a VM with Terraform | 100/100 |
| [`gsp345.sh`](./gsp345.sh) | **GSP345** — Build Infrastructure with Terraform (Challenge Lab) | 7 tasks: modules, imports, remote GCS backend, registry module, firewall | 7/7 tasks |
| [`gsp_marketplace.sh`](./gsp_marketplace.sh) | **Deploy a LAMP Stack with Google Cloud Marketplace** (also *Getting Started with Cloud Marketplace*) | Deploys the LAMP stack (Apache + MySQL + PHP + phpMyAdmin) and verifies the site | 100/100 |
| [`gsp_vpc.sh`](./gsp_vpc.sh) | **Get Started with Virtual Private Cloud Networking and Compute Engine** | Auto-mode VPC, the four firewall rules, the subnets and the VMs | 100/100 |
| [`gsp_vpc_networks.sh`](./gsp_vpc_networks.sh) | **Create and Configure VPC Networks** | The auto-mode network and its VMs, plus `managementnet` and `privatenet` in custom mode | 100/100 |
| [`gsp_pga_nat.sh`](./gsp_pga_nat.sh) | **Implement Private Google Access and Cloud NAT** | A VM with no external IP, an IAP tunnel, Private Google Access and a Cloud NAT gateway | 100/100 |
| [`gsp_create_vms.sh`](./gsp_create_vms.sh) | **Create Virtual Machines** | The shared-core utility VM, the Windows Server VM and the custom-machine-type VM | 100/100 |
| [`gsp_minecraft.sh`](./gsp_minecraft.sh) | **Create and Configure Virtual Machines** | A Minecraft server VM: SSD data disk, static IP, the JRE, the server, firewall, backups and maintenance scripts | — |
| [`gsp_iam.sh`](./gsp_iam.sh) | **Exploring IAM** | The bucket and sample file, revoking and granting project roles, the service account and the VM that runs as it | — |
| [`gsp_storage_buckets.sh`](./gsp_storage_buckets.sh) | **Create and Manage Cloud Storage Buckets and Encryption** | The bucket, the public ACL, the customer-supplied key, the lifecycle rule and versioning | — |
| [`gsp_configure_sql.sh`](./gsp_configure_sql.sh) | **Configure Cloud SQL** | The `wordpress-db` instance with a Private IP, the `wordpress` database and the Cloud SQL Auth Proxy | 100/100 |
| [`gsp_bigquery_billing.sh`](./gsp_bigquery_billing.sh) | **Examine Billing data with BigQuery** | The dataset, the Avro load, and the lab's seven billing queries | 100/100 |
| [`gsp_observability.sh`](./gsp_observability.sh) | **Monitor Resources with Google Cloud Observability** | A custom dashboard, an alert policy, a resource group and an uptime check | — |
| [`gsp_storagesql.sh`](./gsp_storagesql.sh) | **Cloud Storage and Cloud SQL** — Getting Started | Web server VM, public bucket, Cloud SQL instance, and the PHP page wired to both | 100/100 |
| [`gsp_cloudrun.sh`](./gsp_cloudrun.sh) | **Hello Cloud Run** | Node.js app, Artifact Registry repo, container image, and the Cloud Run deployment | 100/100 |
| [`gsp_console_shell.sh`](./gsp_console_shell.sh) | **Explore the Google Cloud Console and Cloud Shell** | The console bucket, the Cloud Shell bucket, the file upload, and the persistent environment variables | — |
| [`gsp_access_console_shell.sh`](./gsp_access_console_shell.sh) | **Accessing the Google Cloud Console and Cloud Shell** | The `first-vm` instance with the `http-server` tag, the service account with the Editor role, the two buckets, the cat image and nginx | — |
| [`gsp_cloud_build.sh`](./gsp_cloud_build.sh) | **Working with Cloud Build** | `quickstart-docker-repo`, the `quickstart.sh` + `Dockerfile` image, `cloudbuild.yaml`, and the `cloudbuild2.yaml` build that fails its own test step on purpose | — |
| [`gsp_gke_autopilot.sh`](./gsp_gke_autopilot.sh) | **Deploying GKE Autopilot Clusters** | The regional `autopilot-cluster-1` cluster (scripted) and the `nginx-1` workload, which the grader only accepts when created from the console, plus the kubectl output behind every console tab in task 3 | 100/100 |
| [`gsp_ha_vpn.sh`](./gsp_ha_vpn.sh) | **Configure Google Cloud HA VPN** | The two VPCs, the HA VPN gateways, the Cloud Routers, the four tunnels, the BGP peering and global dynamic routing | — |
| [`gsp_alb_autoscaling.sh`](./gsp_alb_autoscaling.sh) | **Configure an Application Load Balancer with Autoscaling** | The health check rule, the Cloud NAT, the custom web server image, two instance groups and the IPv4/IPv6 load balancer | — |
| [`gsp_internal_lb.sh`](./gsp_internal_lb.sh) | **Configure an Internal Network Load Balancer** | The lb-access and health-check rules, the Cloud NAT, the two instance templates, the two instance groups and the internal load balancer at `10.10.30.5` | — |
| [`gsp_terraform.sh`](./gsp_terraform.sh) | **Automating the Deployment of Infrastructure Using Terraform** | The Terraform workspace, `provider.tf`, `instance/main.tf`, `mynetwork.tf`, and the `terraform init` / `plan` / `apply` that creates `mynetwork` and the two VMs | — |

*Score* is what the lab console reported after running the script.

Every script is **idempotent** — re-run them after any failure and they
skip whatever already exists. They exit `0` when every step succeeded and `1`
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
- **region / zone** — this is the value most likely to be wrong, because
  `gcloud config compute/zone` is a **per-user setting that survives Cloud
  Shell restarts**. The zone from a previous lab is often still sitting
  there, and the lab will then score your resources against a zone you never
  asked for. Both scripts therefore try, in order:

  1. the `--zone` flag
  2. the zone Cloud Skills Boost assigns to that lab
  3. the zone of an instance already in the project
  4. the project's startup-script metadata
  5. `$CLOUDSDK_COMPUTE_ZONE`
  6. `gcloud config compute/zone` — flagged as *possibly stale*

  Whichever source won is printed in the banner, along with a reminder to
  compare it with the lab page. For GSP156 the lab's zone (`europe-west1-d`)
  is baked in as a fallback; override it with `--zone` if your lab run
  differs.
- **roles** — the preflight lists the roles the active account actually holds,
  so a `roles/owner` account no longer gets a bogus "you need editor" warning

> If the zone in the banner does not match what the lab page says, stop and
> re-run with it: `./gsp156.sh --zone <lab-zone>` /
> `./gsp321.sh --zone <lab-zone> --region <lab-region>`.

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
| `zone` | the lab's zone (`europe-west1-d`), or `--zone` |
| `Debian image ID` | the project's common instance metadata (startup script), falling back to the `debian-12` image family the lab itself uses |

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

## GSP345 — Build Infrastructure with Terraform: Challenge Lab

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp345.sh
chmod +x gsp345.sh
./gsp345.sh
```

Seven tasks: create the configuration tree, import two pre-existing
instances, move the state into a GCS backend, modify and update the
instances, destroy one of them, pull the VPC module from the Terraform
Registry, and add a firewall rule.

### It pauses between tasks on purpose

The lab's checkpoints **contradict each other** — task 4 creates a third
instance and task 5 destroys it again. The lab therefore only scores a task
when you click *Check my progress* for it, so the script stops after every
task and waits for you to click that button:

```
  >>> Task 2 applied: Import infrastructure
      Click 'Check my progress' for 'Import infrastructure' in the lab console,
      then press Enter here to continue (Ctrl-C stops - just re-run
      ./gsp345.sh later and it picks up where you left off).
```

Progress is saved in `$HOME/gsp345/.gsp345-progress`, so re-running resumes
at the first unfinished task. Use `--task N` to run a single task, or
`--yes` to run everything without pausing.

### Everything is read from the lab, not guessed

| Value | Where it comes from |
|---|---|
| project | `gcloud config get-value project` |
| zone / region | the zone of the pre-created `tf-instance-1` |
| machine type | `gcloud compute instances describe tf-instance-1` |
| boot disk image | the instance's own disk source |
| instance IDs (for `terraform import`) | the instance's numeric id |
| bucket name | an existing `tf-bucket-*` bucket in the project, else the project metadata, else `--bucket` |

The last three matter more than they look: `boot_disk.initialize_params.image`
is a **ForceNew** field, so if the configured image does not match the
existing disk, Terraform destroys and recreates the instance instead of
updating it in place — and the import checkpoint never scores.

The bucket name is injected by the lab (`For the bucket name, use
tf-bucket-<number>`), so it is read from the project when possible. If it
cannot be found, the script says so and tells you to pass it:

```bash
./gsp345.sh --bucket tf-bucket-178193
```

### It validates the configuration it generates

After writing each task's `.tf` files, the script runs `terraform fmt
-recursive`, which *parses* every file. A syntax error stops the run there
instead of half-way through a task with a broken `apply`.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | the pre-created instances' zone | Lab zone |
| `--region REGION` | derived from the zone | Lab region |
| `--workdir PATH` | `$HOME/gsp345` | Where the configuration lives |
| `--bucket NAME` | the project ID | Remote-backend bucket |
| `--vpc NAME` | `terraform-vpc` | VPC name |
| `--instance NAME` | `tf-instance-3` | Third instance name |
| `--task N` | all | Run only task N (1–7) |
| `--yes` | off | Do not pause between tasks |
| `--recreate-instances` | off | Recreate `tf-instance-1`/`tf-instance-2` if they are missing |
| `--skip-install` | off | Assume terraform is already on PATH |
| `-h, --help` | | Usage |

### Recovering from a deleted instance

If a run ever deletes the lab's instances (a mismatched `boot_disk` image
makes Terraform plan a replacement, and a replacement deletes before it
recreates), the script can bring them back:

```bash
./gsp345.sh --zone us-west4-b --recreate-instances
```

The zone is recorded in `~/gsp345/.gsp345-zone` on every run, so after the
first successful run you can usually just use:

```bash
./gsp345.sh --recreate-instances
```

The instances are recreated with the machine type and image read from the
lab, then imported as normal.

---

## Deploy a LAMP Stack with Google Cloud Marketplace

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_marketplace.sh
chmod +x gsp_marketplace.sh
./gsp_marketplace.sh
```

Deploys the LAMP stack - Linux, Apache HTTP Server, MySQL, PHP and phpMyAdmin
- and then verifies the site.

This one script covers both labs, because they are the same lab:

| Lab | Focus |
|---|---|
| Deploy a LAMP Stack with Google Cloud Marketplace | 19092 |
| Google Cloud Fundamentals: Getting Started with Cloud Marketplace | 19063 |

Both have the single checkpoint **Use Cloud Marketplace to deploy a LAMP
stack**, and the deployment has to be named `lamp-1` with an `e2-medium`
instance in the lab's zone.

### What the console does, and what this does

The lab's own path is: **Marketplace -> search "LAMP" -> "LAMP Stack, by Google
Click to Deploy" -> GET STARTED -> agree -> DEPLOY -> pick the zone, E2 /
e2-medium**. That solution is a Deployment Manager deployment named `lamp-1`
that creates an instance `lamp-1-vm` and an HTTP firewall rule.

The marketplace *image* is licensed, so it can only be launched from the
console after the terms are accepted. This script therefore creates the
**same deployment** with the same names, zone, machine type and firewall
rule, and installs the LAMP stack with a startup script instead. The
component list matches the real solution's Chef cookbook
(`apache2` + `mysql::version-8.0-embedded` + `php83` + `phpmyadmin`), and it
writes the same `lamp-server.conf` virtual host the Click to Deploy cookbook
uses.

If the checkpoint insists on the marketplace image itself, deploy it in the
console (six clicks, about a minute) and then run:

```bash
./gsp_marketplace.sh --verify
```

which finds the existing instance, copies `phpinfo.php` into the document root
and prints the site address.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | `gcloud config compute/zone` | Deployment zone |
| `--region REGION` | derived from the zone | Region |
| `--deployment NAME` | `lamp-1` | Deployment Manager deployment name |
| `--machine-type T` | `e2-medium` | Machine type |
| `--image IMAGE` | `debian-12` | Boot disk image family |
| `--workdir PATH` | `$HOME/gsp-marketplace` | Where the configuration is staged |
| `--verify` | off | Only verify a deployment that already exists |
| `--destroy` | off | Delete the deployment |
| `-h, --help` | | Usage |

The LAMP software installs during boot, so the site takes a few minutes to
start answering. The script polls it and tells you the URL either way.

### Getting the zone right

The zone is lab-assigned and it **is** graded, so the script asks for it and
shows you where its suggestion came from:

```
  suggested: europe-west4-b   (from the project metadata)
```

It reads the zone back out of the project's startup-script metadata, which
the lab fills in for you. That beats a hardcoded zone from a previous lab
run. If the suggestion does not match your setup panel, type the right one
in — the prompt takes it.

The script also prints what it settled on:

```
  zone: europe-west4-b   region: europe-west4   (from the default zone (the project metadata))
  Your lab setup panel should say:  Region europe-west4   Zone europe-west4-b
  If they differ, re-run with:  ./gsp_marketplace.sh --zone <zone> --region <region>
```

---

## VPC Networking and Compute Engine

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc.sh
chmod +x gsp_vpc.sh
./gsp_vpc.sh
```

Deletes the default network, creates an **auto mode** VPC with the four
standard firewall rules and its subnets, creates the two VMs, then removes
three of the firewall rules one at a time to show what each one was doing.

| Task | What the script does |
|---|---|
| 1 | deletes `default`, creates the auto-mode VPC `mynetwork` with `allow-ssh`, `allow-rdp`, `allow-http` and `allow-icmp` |
| 2 | creates `mynet-us-vm` and `mynet-r2-vm` in the two lab regions ⏸ |
| 3 | removes `allow-rdp`, `allow-http` and `allow-icmp`, leaving `allow-ssh` |

It pauses between task 2 and task 3, because the single checkpoint is scored
right after task 2 and task 3 **deletes** three of the firewall rules.

### The subnet name gotcha

In an **auto mode** network the subnet is named after the **network**, not
`default` — so the subnets of `mynetwork` are `mynetwork`, `mynetwork-r2`,
etc. Only the default network coincidentally uses `default`, which is why
copying a subnet name between labs breaks.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region1 R` | asked for | Region for `mynet-us-vm` |
| `--zone1 Z` | asked for | Zone for `mynet-us-vm` |
| `--region2 R` | asked for | Region for `mynet-r2-vm` |
| `--zone2 Z` | asked for | Zone for `mynet-r2-vm` |
| `--network NAME` | `mynetwork` | VPC network name |
| `--workdir PATH` | `$HOME/gsp-vpc` | Where the logs are written |
| `--task N` | all | Run only task N (1–3) |
| `--yes` | off | Do not pause for the checkpoint |
| `-h, --help` | | Usage |

---

## Create and Configure VPC Networks

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_vpc_networks.sh
chmod +x gsp_vpc_networks.sh
./gsp_vpc_networks.sh
```

A bigger sibling of `gsp_vpc.sh`. This one covers focus **19093**, which has
three checkpoints instead of one:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a VPC network and VM instances | 30 |
| 2 | Create custom mode VPC networks with firewall rules | 40 |
| 3 | Create VM instances | 30 |

| Task | What the script does |
|---|---|
| 1 | deletes the four `default-allow-*` firewall rules, then the `default` network |
| 2 | creates `mynetwork` in **auto** mode, the four standard firewall rules, `allow-iap-ssh`, and the two `e2-medium` VMs — then converts the network to **custom** mode ⏸ |
| 3 | creates `managementnet` and `privatenet` in custom mode, their three subnets and their two firewall rules ⏸, then the two `e2-micro` VMs ⏸ |
| 4 | prints the instance table and what the connectivity tests should show |

### The two zones

The lab assigns **two** zones per run and they cannot be read from the
project, so the script asks for both:

```
  Zone 1  [us-central1-a]:
  Zone 2  [us-west1-b]:
```

The regions are derived from the zones, because the lab's `default_region` is
the region of `default_zone`. Override them with `--region1` / `--region2`
if your run differs.

### The firewall rules the CLI does not create

Ticking *all available rules* in the console creates four rules. The CLI
creates **none** of them, so the script makes them explicitly:

| Rule | Priority | Allows | Source |
|---|---|---|---|
| `mynetwork-allow-custom` | 65534 | all | `10.128.0.0/9` |
| `mynetwork-allow-icmp` | 65534 | icmp | `0.0.0.0/0` |
| `mynetwork-allow-rdp` | 65534 | tcp:3389 | `0.0.0.0/0` |
| `mynetwork-allow-ssh` | 65534 | tcp:22 | `0.0.0.0/0` |
| `allow-iap-ssh` | 1000 | tcp:22 | `35.235.240.0/20` (target tag `iap-gce`) |

Plus `managementnet-allow-icmp-ssh-rdp` and
`privatenet-allow-icmp-ssh-rdp` at priority 1000.

### The subnet named after the network

In an **auto mode** network the subnet takes the name of the **network**, and
one is created in every region — so both VMs use `subnet=mynetwork`. Only the
default network coincidentally uses `default`, which is why copying a subnet
name between labs breaks.

### The machine types differ between the tasks

| VM | Type | Network |
|---|---|---|
| `mynet-us-vm`, `mynet-notus-vm` | `e2-medium` | `mynetwork` |
| `managementnet-us-vm`, `privatenet-us-vm` | `e2-micro` | `managementnet` / `privatenet` |

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone1 ZONE` | asked for | The lab's first zone |
| `--zone2 ZONE` | asked for | The lab's second zone |
| `--region1 REGION` | from zone1 | Region for the `-us` subnets |
| `--region2 REGION` | from zone2 | Region for the `-notus` subnet |
| `--image IMAGE` | from the project metadata | Boot disk image family |
| `--network NAME` | `mynetwork` | The auto mode network |
| `--task N` | all | Run only task N (1–4) |
| `--yes` | off | Do not pause for the checkpoints |
| `--keep-default` | off | Do not delete the default network |
| `-h, --help` | | Usage |

---

---

## Implement Private Google Access and Cloud NAT

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_pga_nat.sh
chmod +x gsp_pga_nat.sh
./gsp_pga_nat.sh
```

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create the VM instance | 30 |
| 2 | Create a Cloud Storage bucket and Enable Private Google Access | 40 |
| 3 | Configure a Cloud NAT gateway | 30 |

| Task | What the script does |
|---|---|
| 1 | `privatenet` (custom mode), `privatenet-us` (`10.130.0.0/20`), the `privatenet-allow-ssh` rule limited to the IAP range `35.235.240.0/20`, and `vm-internal` with **no external IP** ⏸ |
| 2 | the bucket, `access.svg` copied in, and `--enable-private-ip-google-access` on the subnet ⏸ |
| 3 | the `nat-router` Cloud Router and the `nat-config` Cloud NAT gateway ⏸ |
| 4 | turns on Cloud NAT logging and prints the Logs Explorer filter |

### The three things that make this lab work

**No external IP.** The CLI spelling of the console's *External IPv4 address:
None* is `no-address` in the network interface:

```bash
--network-interface=network=privatenet,subnet=privatenet-us,no-address
```

**The SSH rule only needs the IAP range.** IAP tunnels always arrive from
`35.235.240.0/20`, so the rule does not have to open port 22 to the world:

```bash
gcloud compute firewall-rules create privatenet-allow-ssh \
    --network=privatenet --rules=tcp:22 --source-ranges=35.235.240.0/20
```

**Private Google Access is a subnet setting**, not a network setting:

```bash
gcloud compute networks subnets update privatenet-us \
    --region=REGION --enable-private-ip-google-access
```

It only covers Google's own APIs and services. Reaching the wider internet
is what the **Cloud NAT gateway** is for, and the router and the gateway are
separate resources with separate names — `nat-router` and `nat-config`.

### The script also verifies the connectivity

After each step it hops into the VM over the IAP tunnel and checks the thing
the lab asks you to check:

- after Private Google Access: can the VM read the object out of the bucket?
- after Cloud NAT: does `sudo apt-get update` complete?

Those checks are **informational only** — they never fail the run, because
they need an IAP tunnel and your account's permissions. Pass `--no-verify` to
skip them.

> The NAT config takes up to 3 minutes to propagate. If `apt-get update` still
> fails straight after the script finishes, wait a minute and run it again.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | asked for | The lab's zone |
| `--region REGION` | from the zone | The region |
| `--network NAME` | `privatenet` | The VPC network |
| `--subnet NAME` | `privatenet-us` | The subnet |
| `--vm NAME` | `vm-internal` | The instance |
| `--bucket NAME` | the project ID | The Cloud Storage bucket |
| `--machine-type T` | `e2-standard-2` | Machine type |
| `--image IMAGE` | from the project metadata | Boot disk image family |
| `--task N` | all | Run only task N (1–4) |
| `--yes` | off | Do not pause for the checkpoints |
| `--no-verify` | off | Skip the connectivity tests |
| `-h, --help` | | Usage |

---

---

## Create Virtual Machines

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_create_vms.sh
chmod +x gsp_create_vms.sh
./gsp_create_vms.sh
```

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a utility virtual machine | 30 |
| 2 | Create a Windows virtual machine | 30 |
| 3 | Create a custom virtual machine | 40 |

| Task | What the script does |
|---|---|
| 1 | `utility-vm` — shared-core `e2-medium` with **no external IP** — then prints the CPU platform and the availability policies ⏸ |
| 2 | the two `default-allow-*` firewall rules and their network tags, then `utility-wm` — `e2-standard-2`, Windows Server 2025, 64 GB SSD ⏸ |
| 3 | `utility-cm` — a **custom** machine type with 2 vCPU and 4 GB — then checks it over SSH ⏸ |

### What "Allow HTTP traffic" actually does

Ticking that box in the console does **two** things, and both are needed:

```bash
# 1. it creates the rule
gcloud compute firewall-rules create default-allow-http \
    --network=default --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

# 2. it tags the instance
gcloud compute instances create ... --tags=http-server,https-server
```

The rule without the tag does nothing, and the tag without the rule opens
nothing. There is a matching `default-allow-https` on tcp:443.

### The Windows image family is looked up, not hardcoded

Google renames the Windows image families between releases, so the script
resolves the family at run time:

```bash
gcloud compute images describe-from-family windows-2025 \
    --project windows-cloud --zone ZONE
```

and falls back to `windows-2022` and `windows-2019`, then to listing the
families. Override it with `--windows-family` if you need to.

### The custom machine type has to name the E2 series

This is the one that bites. The console's *Series E2* + *Custom* + 2 cores +
4 GB is `e2-custom-2-4096`. The gcloud flags for it are **not** equivalent:

```bash
# WRONG - the default machine type is n1-standard-1, so this makes an N1 VM
gcloud compute instances create utility-cm --custom-cpu=2 --custom-memory=4GB
# -> n1-custom-2-4096

# RIGHT
gcloud compute instances create utility-cm --machine-type=e2-custom-2-4096
# -> e2-custom-2-4096
```

From the gcloud reference:

> `--machine-type` — *If unspecified, the default type is `n1-standard-1`.*
> `--custom-cpu` / `--custom-memory` — *Specifies a custom machine type. The
> default is `n1`.*

The checkpoint scores the **E2** one. The script therefore builds the name
itself (`e2-custom-<cores>-<memory>`) and, if it finds an instance with the
wrong machine type, deletes it and creates it again — a running instance's
machine type cannot be changed.

### Two things the CLI cannot do

**Setting the Windows password.** There is no gcloud command — the lab's
*Set Windows password* button calls a Windows-specific API. The script
prints the console path for it.

**Picking a custom machine type in the console.** It becomes
`--custom-cpu=2 --custom-memory=4GB`, which shows up as the machine type
`e2-custom-2-4096`.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | asked for | The lab's zone |
| `--region REGION` | from the zone | The region |
| `--image IMAGE` | from the project metadata | The Linux boot disk image family |
| `--cores N` | `2` | Cores for the custom machine type |
| `--memory MB` | `4096` | Memory for the custom machine type |
| `--windows-family F` | resolved at run time | The Windows image family |
| `--task N` | all | Run only task N (1–3) |
| `--yes` | off | Do not pause for the checkpoints |
| `--no-verify` | off | Skip the SSH check |
| `-h, --help` | | Usage |

---

---

## Create and Configure Virtual Machines

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_minecraft.sh
chmod +x gsp_minecraft.sh
./gsp_minecraft.sh
```

The Minecraft server lab. Five checkpoints, 20 points each.

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Create the VM and prepare the data disk | `mc-server` (e2-medium), the `minecraft-disk` 50 GB pd-ssd, the `mc-server-ip` static IP, then `mkfs.ext4` + `mount` on the VM ⏸ |
| 2 | Install the JRE and the Minecraft server | `default-jre-headless`, `server.jar` 1.11.2, the EULA, and the server in a detached `screen` session ⏸ |
| 3 | Allow client traffic | the `minecraft-rule` firewall rule on tcp:25565 ⏸ |
| 4 | Schedule regular backups | the `<project>-minecraft-backup` bucket, `backup.sh`, one real run, and the `0 */4 * * *` cron job ⏸ |
| 5 | Server maintenance | the `startup-script-url` and `shutdown-script-url` metadata items ⏸ |

### The three details that decide this lab

**The disk name gives you the mount path.** The lab mounts
`/dev/disk/by-id/google-minecraft-disk`, and that path is derived from the
**disk name** — so the disk has to be called `minecraft-disk`, not something
else.

**The storage scope is not optional.** The backup script runs
`gcloud storage cp` *on the VM*, so the instance needs
`devstorage.read_write` in its access scopes. With the default read-only
scope the backup is denied and the bucket stays empty.

**cron does not read `~/.profile`.** The lab's cron line is

```
0 */4 * * * /home/minecraft/backup.sh
```

but `YOUR_BUCKET_NAME` would be empty under cron, and the backup would go to
a bucket called `-minecraft-backup`. The script therefore writes the
crontab as:

```
YOUR_BUCKET_NAME=your-project-id
0 */4 * * * /home/minecraft/backup.sh
```

`YOUR_BUCKET_NAME=...` is valid crontab syntax and cron applies it to the
job below it, so the scheduled backup actually works.

### The steps that run inside the VM

They are uploaded with `gcloud compute scp` and run over **one** SSH
session, so the environment variables survive from one step to the next:

```bash
gcloud compute scp prepare_disk.sh mc-server:/tmp
gcloud compute ssh mc-server --command="bash /tmp/prepare_disk.sh"
```

The scripts are written to `~/gsp-minecraft/` so you can read exactly what
ran on the VM. If the copy fails for any reason, the script sends the script
over the SSH command line instead:

```bash
gcloud compute ssh mc-server --command="echo '<base64>' | base64 -d | bash"
```

### Do not switch on OS Login

Some reference scripts create the VM with `--metadata=enable-oslogin=true`.
With OS Login enabled, `gcloud compute ssh` and `gcloud compute scp` use the
OS Login flow, which needs the **`roles/iam.osLogin`** permission — and a lab
student account usually does not have it. Both commands then fail with a
permissions error, even though the console's **SSH** button works (it uses the
classic metadata-based key).

The script creates the VM **without** that metadata item, and if it finds an
instance that has it, it turns it off and restarts the VM:

```
  [WARN] the VM has OS Login switched on, which blocks gcloud SSH for this account
  [INFO] turning it off and restarting the VM
  [OK]   SSH into mc-server works now
```

### About the last task

The lab also stops the VM for maintenance. The script **leaves it running**
so the earlier checkpoints stay valid, and prints the command to stop it:

```bash
./gsp_minecraft.sh --stop-vm
```

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | asked for | The lab's zone |
| `--region REGION` | from the zone | The region |
| `--image IMAGE` | from the project metadata | The boot disk image family |
| `--task N` | all | Run only task N (1–6) |
| `--yes` | off | Do not pause for the checkpoints |
| `--stop-vm` | off | Also stop the VM at the end, the way the lab does |
| `-h, --help` | | Usage |

---

---

## Exploring IAM

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_iam.sh
chmod +x gsp_iam.sh
./gsp_iam.sh
```

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Create a bucket and upload a sample file | the bucket `gs://<project-id>` and a `sample.txt` object in it ⏸ |
| 2 | Remove project access | revokes `roles/viewer` from Username 2 ⏸ |
| 3 | Add storage permissions | grants `roles/storage.objectViewer` to Username 2 ⏸ |
| 4 | Set up the Service Account User and create a VM | the `read-bucket-objects` service account, `roles/iam.serviceAccountUser` for `domain:altostrat.com`, `roles/compute.instanceAdmin.v1` for the same domain, and the `demoiam` VM ⏸ |

### It finds Username 2 on its own

This lab uses **two** Google accounts, and Username 2 is in the lab's
Connection Details panel — not something a script can read. But it can be
*derived*: Username 2 is the user that holds `roles/viewer` and is not you.

```bash
gcloud projects get-iam-policy $PROJECT_ID --format="json" | jq -r \
  --arg me "user:$MY_ACCOUNT" \
  '.bindings[] | select(.role == "roles/viewer") | .members[]?
   | select(startswith("user:")) | select(. != $me) | sub("user:"; "")'
```

The script does that, shows you what it found, and then **asks you to
confirm** — you can just press Enter. It also remembers the answer in
`~/gsp-iam/.user2`, because after task 2 the user no longer holds
`roles/viewer` and the policy alone would no longer name them.

### What still needs the second browser tab

The IAM changes are all made from your account, so the script does them. The
*verification* needs a tab signed in as Username 2, so the script prints what
to look for after each step:

- **Task 3** — Username 2 can see the bucket in Cloud Storage → Buckets
- **Task 4** — Username 2 gets an error in Cloud Storage → Buckets
- **Task 5** — in Username 2's Cloud Shell, `gcloud storage ls gs://<bucket>` works

### Task 7 and the service account's role

The lab's last task changes the service account from Storage Object **Viewer**
to Storage Object **Creator**, and the copy back then succeeds. The script
**grants Creator without removing Viewer**, so the download from task 7 still
works and the earlier checkpoint stays valid.

Pass `--skip-role-change` to leave the service account exactly as task 6
leaves it.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--user2 EMAIL` | detected, then asked for | The lab's second user |
| `--zone ZONE` | asked for | The lab's zone |
| `--region REGION` | from the zone | The region |
| `--bucket NAME` | the project ID | The bucket |
| `--domain DOMAIN` | `altostrat.com` | The fake company domain |
| `--sa NAME` | `read-bucket-objects` | The service account |
| `--vm NAME` | `demoiam` | The VM |
| `--task N` | all | Run only task N (3–7) |
| `--yes` | off | Do not pause for the checkpoints |
| `--skip-role-change` | off | Leave the service account as Storage Object Viewer |
| `-h, --help` | | Usage |

---

---

## Create and Manage Cloud Storage Buckets and Encryption

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storage_buckets.sh
chmod +x gsp_storage_buckets.sh
./gsp_storage_buckets.sh
```

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Create a Cloud Storage bucket | the bucket, with fine-grained access and public access prevention off, plus the three sample files ⏸ |
| 2 | Make file publicly readable | uploads `setup.html`, sets the ACL to private, then binds `allUsers` to `roles/storage.legacyObjectReader` ⏸ |
| 3 | Customer-supplied encryption keys (CSEK) | generates a 32 byte key, writes it into `~/.boto`, and uploads `setup2.html` and `setup3.html` encrypted ⏸ |
| 4 | Enable lifecycle management | the delete-after-31-days policy ⏸ |
| 5 | Enable versioning | turns versioning on, then makes versions and recovers the original ⏸ |

### The bucket needs two specific settings

The lab asks for **fine-grained** access and for **public access prevention to
be unchecked**. Both are needed, or step 2 cannot make an object public:

```bash
gcloud storage buckets update gs://$BUCKET --no-uniform-bucket-level-access
gcloud storage buckets update gs://$BUCKET --public-access-prevention=inherited
```

### The customer-supplied key, two ways

The lab puts the key in `~/.boto` and lets gsutil pick it up. The script does
that **and** passes the key explicitly on every call, so the commands work
whatever the boto file looks like:

```bash
gsutil -o "GS:encryption_key=$KEY" cp setup2.html gs://$BUCKET/
```

The boto file is edited by **option name**, not by line number — the lab's
`nano` instructions have you find the `#encryption_key=` line, and the line
number moves between gsutil versions.

### The rotation, and the point of it

Task 4 rewrites `setup2.html` with a **new** key and leaves `setup3.html` with
the old one:

```bash
gsutil -o "GS:encryption_key=$NEW" -o "GS:decryption_key1=$OLD" rewrite -k gs://$BUCKET/setup2.html
```

So `setup2.html` reads back with the new key and `setup3.html` only reads
back with the old one. If you lose the old key, that object is unreadable —
which is the whole lesson. The script keeps both keys in the work directory
(`~/gsp-storage-buckets/csek1` and `csek2`).

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region REGION` | asked for | The bucket's region |
| `--bucket NAME` | the project ID | The bucket |
| `--task N` | all | Run only task N (1–7) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

---

## Configure Cloud SQL

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_configure_sql.sh
chmod +x gsp_configure_sql.sh
./gsp_configure_sql.sh
```

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Create a Cloud SQL instance | the Private Services Access range and peering, then `wordpress-db` (MySQL 8.0, 1 vCPU / 3840 MB, 10 GB) ⏸ |
| 2 | Create a database and configure a proxy on a Virtual Machine | the `wordpress` database, the Cloud SQL Auth Proxy downloaded and started on `wordpress-proxy` ⏸ |

### It reads the zone from the VMs the lab gives you

The lab pre-creates `wordpress-proxy` and `wordpress-private-ip`, so there is
nothing to ask for:

```bash
ZONE=$(gcloud compute instances list --filter="name=wordpress-proxy" --format "get(zone)" | awk -F/ '{print $NF}')
REGION=${ZONE%-*}
```

The script finds the VMs by name pattern, so it works whether the lab calls
them `wordpress-proxy` or `wordpress-europe-proxy`.

### Private Services Access is two commands

The console's **Confirm network setup** button does this:

```bash
gcloud compute addresses create default-ip-range \
    --global --purpose=VPC_PEERING --prefix-length=24 --network=default

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=default-ip-range --network=default
```

and the instance then points at the range:

```bash
gcloud beta sql instances create wordpress-db \
    --database-version=MYSQL_8_0 --cpu=1 --memory=3840MB \
    --region=$REGION --zone=$ZONE --storage-size=10 \
    --root-password='...' \
    --network=projects/$PROJECT_ID/global/networks/default \
    --allocated-ip-range-name=default-ip-range
```

### The patch restarts the instance, and it shows you why

`gcloud sql instances patch` also waits for a long-running operation, because
changing the SSL setting **restarts** the instance. The script streams that
too, and — importantly — it **only patches when something actually needs
changing**. A second run leaves the instance alone instead of restarting it
for nothing.

### The create takes minutes, and it shows you why

`gcloud sql instances create` blocks for the whole long-running operation, and
an instance with a private IP commonly takes 3–8 minutes to come up. The
script prints gcloud's output as it arrives and then heartbeats while it
waits for the instance to report `RUNNABLE`:

```
  attempt 1: gcloud beta sql instances create wordpress-db ...
    Waiting for operation
    ... still working (20s elapsed)
  [OK]   created wordpress-db (attempt 1)
    state: RUNNABLE
```

A silent wait is indistinguishable from a hang, so there isn't one.

### The create command is tried a few ways

The private IP flags (`--network`, `--allocated-ip-range-name`) only exist on
the `gcloud **beta** sql instances create` command, and not every gcloud build
accepts every one of `--zone` and `--storage-size` either. A mismatch shows up
as a bare `unrecognized arguments:` with the flag names on the next lines.

So the script tries four known combinations in turn — the one that a working
community solution uses first — and each attempt gets its own log. If they
all fail it falls back to the **Cloud SQL Admin API**, which has no flags to
guess at:

```
  attempt 1 did not work:
  ERROR: (gcloud.beta.sql.instances.create) unrecognized arguments:
  ...
  [INFO] trying the Cloud SQL Admin API instead
```

and if that fails too, every log is printed with the exact command to run by
hand.

### The root password has to be 8 characters or more

Cloud SQL puts a password policy on new instances — at least 8 characters,
and usually a mix of upper case, lower case, digits and symbols. A short
password is rejected by the API with `INVALID_ARGUMENT: The root password
does not conform to the password policy`, which is easy to miss because the
create command prints nothing useful.

The script checks the length **before** it calls the API and asks again if
the password is too short:

```
  Root password  [Passw0rd1!]: abc1234
  [FAIL] that password is 7 characters - Cloud SQL needs at least 8
```

and if the create still fails, it prints the API's own error and the log path.

### The proxy gets `nohup`, not a bare `&`

The lab starts it with `./cloud_sql_proxy ... &` from an SSH session, and
that **dies with the session** — the checkpoint wants it running. The script
uses `nohup` and then checks the process is actually there:

```bash
nohup ./cloud_sql_proxy -instances=$CONNECTION_NAME=tcp:3306 > proxy.log 2>&1 &
```

### Two things the script also does for you

- **Allowlists the proxy VM** and turns off `requireSsl` — the lab ticks
  *Allow unencrypted network traffic*, and the proxy connects over the public
  IP, so the VM's address has to be on the instance's authorized networks.
  (`--authorized-networks` wants a bare `IP/32`, not `name=IP/32`.)
- **Prints the browser steps** for both WordPress front ends, with the right
  database host filled in — `127.0.0.1` for the proxy one and the Cloud SQL
  private IP for the other. The WordPress setup is a web form, so that part
  cannot be scripted.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--password PASS` | asked for | The Cloud SQL root password |
| `--instance NAME` | `wordpress-db` | The Cloud SQL instance |
| `--database NAME` | `wordpress` | The database |
| `--db-version VER` | `MYSQL_8_0` | The database version |
| `--proxy-vm NAME` | detected | The proxy VM |
| `--private-vm NAME` | detected | The private IP VM |
| `--task N` | all | Run only task N (1–2) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

---

## Examine Billing data with BigQuery

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_bigquery_billing.sh
chmod +x gsp_bigquery_billing.sh
./gsp_bigquery_billing.sh
```

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Use BigQuery to import data | the `billing_dataset` dataset in `US` with a 1-day table expiration, then loads the Avro file into `sampleinfotable` ⏸ |
| 2 | Compose a simple query | `SELECT * FROM billing_dataset.sampleinfotable WHERE cost > 0` ⏸ |
| 3 | Analyze a large billing dataset with SQL | all seven of the lab's queries, including the 415,602-row one ⏸ |

### The table expiration is verified, not assumed

The console asks for **1 day**, and the API stores that in milliseconds —
but the `bq` flag for it is spelled differently between versions, and the
unit is easy to get wrong. A 1-day expiry read as *seconds* would delete the
table out from under you.

So the script creates the dataset, reads the value back through the API, and
corrects it if it is not right:

```bash
curl -X PATCH "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT_ID/datasets/billing_dataset" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"defaultTableExpirationMs":"86400000"}'
```

### The checkpoints are scored from the query job history

So the queries have to actually **run** — pasting them into the BigQuery
console and running them with `bq query` land in the same history, and the
script runs the lab's SQL text verbatim.

### The load takes a minute or two

The sample file is a 160 MB Avro export, and `bq load` blocks until the job
finishes. The script streams its output and heartbeats while it waits, so
the run never looks like it has hung.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--dataset NAME` | `billing_dataset` | The dataset |
| `--table NAME` | `sampleinfotable` | The table |
| `--source URI` | the lab's Avro file | The file to load |
| `--task N` | all | Run only task N (1–4) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

---

## Monitor Resources with Google Cloud Observability

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_observability.sh
chmod +x gsp_observability.sh
./gsp_observability.sh
```

| # | Checkpoint | What the script does |
|---|---|---|
| 1 | Create custom dashboard | `My Dashboard` with a `mosaicLayout` and a line chart of CPU utilization ⏸ |
| 2 | Create alerting policies | an email notification channel and `My Alert Policy` with two conditions ANDed ⏸ |
| 3 | Create Resource Group | `VM instances`, with the filter checked against the real member list ⏸ |
| 4 | Create uptime check | `My Uptime check` on the group, plus an alert policy for it ⏸ |

Then it disables the alert policy, which is what the lab's last task asks for.

### The group needs the console's own filter

The lab's criterion is *Value: nginx* — in the console's **Contains**
operator — and the console turns that into exactly:

```
resource.metadata.name = has_substring("nginx")
```

The lab grades the group's **configuration** — a group with any other filter
scores **0**, even though the API accepts it and it appears in the console.
Note what is *not* in it: no `resource.type = "gce_instance" AND` prefix,
and `has_substring`, not `starts_with`.

The member list is a red herring: it is filled in by a background evaluation
and can be empty for a minute or two after the group is created. The
checkpoint looks at the configuration, not the members.

### The dashboard has to be a classic one

The console creates a **classic** dashboard, which means a `mosaicLayout` with
`tiles`. A `gridLayout` dashboard — the newer shape — is accepted by the API,
shows up in the console, and still scores **0**, because the lab looks for the
chart in the classic shape.

The script deletes any dashboard with that name and creates it again in the
shape the console itself produces, every time.

### One shell trap worth knowing

The filter contains double quotes of its own, so it has to be **json
escaped** before it goes into a request body, and the body has to be built
with `printf` rather than a heredoc — a heredoc would eat the backslashes:

```bash
printf '{
  "displayName": "%s",
  "filter": "%s"
}
' \
  "$GROUP_NAME" "$(json_escape "$F")" > group.json
```

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--email EMAIL` | your account | The address for the notification channel |
| `--zone ZONE` | detected from the VMs | The lab's zone |
| `--group-filter F` | auto | The exact filter for the resource group |
| `--task N` | all | Run only task N (1–6) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

---

## Cloud Storage and Cloud SQL — Getting Started

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_storagesql.sh
chmod +x gsp_storagesql.sh
./gsp_storagesql.sh
```

Deploys the `bloghost` web server, a Cloud Storage bucket holding a public
banner image, and a Cloud SQL MySQL instance — then wires the PHP page on the
VM to the database and to the image, and checks the page really says
`Connected successfully`.

| Task | What the script does |
|---|---|
| 2 — web server VM | `bloghost`, `e2-standard-2`, Debian 12, HTTP firewall, the lab's startup script |
| 3 — Storage bucket | bucket named after the project, in the multi-region closest to the lab region, the banner image uploaded and made public |
| 4 — Cloud SQL | `blog-db`, MySQL, Enterprise edition, the `blogdbuser` account, the VM's external IP authorised with `/32`, unencrypted traffic allowed |
| 5 — PHP to Cloud SQL | writes `index.php` with the database IP and credentials, restarts Apache, checks the page |
| 6 — image on the page | adds the `<img>` tag pointing at the public object and checks it renders |

It pauses after tasks 2, 3 and 4 so the three checkpoints can be claimed.

The bucket's multi-region is derived from the lab's region (`us-*` → US,
`europe-*` → EU, `asia-*` → ASIA), and the zone is asked for, since the lab
assigns it per run.

---

## Hello Cloud Run

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloudrun.sh
chmod +x gsp_cloudrun.sh
./gsp_cloudrun.sh
```

Builds a small Node.js/Express app, containerises it, pushes the image to
Artifact Registry, and deploys it to Cloud Run.

| Task | What the script does |
|---|---|
| 2 | writes `package.json`, `index.js` and the `Dockerfile` |
| 3 | creates the `my-repository` Artifact Registry repo and points Docker at it |
| 4 | builds the image with Cloud Build, pushes it, and runs it locally to check it answers |
| 5 | deploys the `helloworld` service with `--allow-unauthenticated` and checks the URL responds |

It pauses after each task so the three checkpoints — *Create an Artifact
Registry repository*, *Containerize your app and upload it to Artifact
Registry*, *Deploy a containerized application on Cloud Run* — can be claimed.

The region is assigned per lab run, so the script asks for it. The base image
for the `Dockerfile` defaults to `node:20`; pass `--node-image` if your lab
page names a different one.

### If the deploy looks like it has hung

It hasn't. The **first** revision has to pull the container image out of
Artifact Registry before it can become ready, and that usually takes 3–5
minutes. The script streams gcloud's output as it arrives, with a
`... still working (30s elapsed)` heartbeat, so you can see it moving.

Watch it from a second tab:

```bash
gcloud run services describe helloworld --region=$LOCATION \
    --format="value(status.latestReadyRevisionName,status.url)"
```

Re-running `gcloud run deploy` after an interrupt is safe — it creates a new
revision. Or use the script's own retry:

```bash
./gsp_cloudrun.sh --task 5
```

---

## Explore the Google Cloud Console and Cloud Shell

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_console_shell.sh
chmod +x gsp_console_shell.sh
./gsp_console_shell.sh
```

| Task | What the script does |
|---|---|
| 1 | prints the bucket name and a pre-filled console link, waits for you to create the bucket in the **console**, then verifies it ⏸ |
| 2 | shows that Cloud Shell is authenticated (no checkpoint, so nothing to click) |
| 3 | creates the second bucket with `gcloud storage buckets create` ⏸ |
| 4 | writes a local file and copies it into **both** buckets, then lists the objects ⏸ |
| 5 | writes `~/infraclass/config`, exports `INFRACLASS_REGION` and `INFRACLASS_PROJECT_ID`, and adds `source "$HOME/infraclass/config"` to `~/.profile` |

It pauses after tasks 1, 3 and 4 so the three checkpoints — *Create a bucket
using the GCP Console*, *Create a bucket using Cloud Shell*, *Upload a file to
Storage bucket* — can be claimed.

### Task 1 has to be done in the console

That checkpoint is graded as a **console** creation, so no script can do it
for you. The script gets as close as it can: it prints the exact name to type
and a link that opens the create-bucket page already pointed at your project.

```
  1. Open this link (it is pre-filled with your project):
       https://console.cloud.google.com/storage/create-bucket?project=PROJECT_ID
  2. For Name, type exactly:
       PROJECT_ID
  3. Leave every other value as it is and click Create.
  4. If it says Public access will be prevented, click Confirm.
  5. Come back here and press Enter.
```

The bucket name has to be globally unique, so if the console says the name is
taken, pick another one:

```bash
./gsp_console_shell.sh --console-bucket <name> --cli-bucket <name>-2
```

### Do not close Cloud Shell while the script is running

The lab's task 2 asks you to close and reopen Cloud Shell. Closing it resets
the VM and **kills the script**. Task 2 has no checkpoint, so close Cloud
Shell after the script finishes instead.

### Task 5, verified

The script rewrites `~/infraclass/config` from scratch on every run (so a
re-run never duplicates a line) and only appends to `~/.profile` if it is not
already there. It then proves the persistence works:

```bash
bash -lc 'echo $INFRACLASS_PROJECT_ID'
```

A **login** shell reads `~/.profile`, so the variable is still set in a fresh
session. A plain `bash -c` shell does not read `~/.profile` — that is normal,
not a bug.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--console-bucket N` | the project ID | The bucket you create in the console |
| `--cli-bucket N` | `<console-bucket>-2` | The bucket created from the shell |
| `--region R` | first region from `gcloud compute regions list` | Stored in `INFRACLASS_REGION` |
| `--file PATH` | a new `~/my-file.txt` | The file that is uploaded |
| `--task N` | all | Run only task N (1–5) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

## Configure Google Cloud HA VPN

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_ha_vpn.sh
chmod +x gsp_ha_vpn.sh
./gsp_ha_vpn.sh
```

| Task | What the script does |
|---|---|
| 1 | `vpc-demo` in custom mode, `vpc-demo-subnet1` (`10.1.1.0/24`) and `vpc-demo-subnet2` (`10.2.1.0/24`) in the two regions, the two firewall rules and the two VMs ⏸ |
| 2 | `on-prem`, `on-prem-subnet1` (`192.168.1.0/24`), its two firewall rules and `on-prem-instance1` ⏸ |
| 3 | the two HA VPN gateways `vpc-demo-vpn-gw1` and `on-prem-vpn-gw1`, and the two Cloud Routers `vpc-demo-router1` (asn 65001) and `on-prem-router1` (asn 65002) ⏸ |
| 4 | the four tunnels, interface 0 to 0 and interface 1 to 1 ⏸ |
| 5 | the four router interfaces and the four BGP peers ⏸ |
| 6 | the two cross-VPC firewall rules, the tunnel status, global dynamic routing on `vpc-demo`, and the pings to `10.1.1.2` and `10.2.1.2` from `on-prem-instance1` ⏸ |
| 7 | the HA test: deletes `vpc-demo-tunnel0`, shows `on-prem-tunnel0` with a broken handshake, and pings again to prove the traffic moved to tunnel 1 ⏸ |

The five lab checkpoints line up with those tasks: *Create two VPC networks
and instances* (end of task 2), *Configure HA VPN gateways* (end of task 3),
*Configure dynamic routing with VPN tunnels* (end of task 5), *Configure
global dynamic routing mode* (end of task 6) and *Verify and test HA VPN
gateway configuration* (end of task 7).

### The two regions and the three zones are lab-assigned

They change on every lab run and cannot be read from the project. The script
takes them from the shell the lab starts — Arcade exports `ZONE`, `ZONE_1`
and `ZONE_2` (or `Z1`, `Z2`, `Z3`) — and asks for whatever is missing. The
regions are derived from the zones.

### Every zone is checked against the API before it is used

A lab project does not necessarily allow every zone, and a zone that cannot
be fetched comes back as:

```
ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - Permission denied on 'locations/europe-west1-a' (or it may not exist).
```

The instance create fails with that message, and it says nothing about the
zone being the problem. So the script checks the zone first with
`gcloud compute zones describe`, and the prompt lists the zones the project
*does* accept in that region:

```
  [WARN] this project cannot use the zone us-central1-b
    the zones of europe-west1: europe-west1-b
  Zone 3 - on-prem-instance1 (in REGION 1 = europe-west1, not zone 1) [europe-west1-b]:
```

Press Enter and it takes the default; the create is still the real test, and
if it fails the script tries the other zones of the region before giving up.

The same check catches a zone from the wrong region, and the "not zone 1"
rule for `on-prem-instance1` — the lab wants it in a different zone from
`vpc-demo-instance1`, and the API does not enforce that.

### The regions have to match what is already there

The lab's regions are per run, and the script cannot invent them. If a
subnet or an instance already exists in a *different* region or zone than
the one being used now, the script says so instead of quietly creating a
second copy with the same name — the grader looks at one of them, and it
will not know which:

```
  [WARN] the subnet vpc-demo-subnet1 already exists in europe-west1, not in us-central1
  [WARN] the lab's regions are REGION 1 = us-central1 and REGION 2 = us-central1
  [WARN] pass --region1/--region2 to match the lab, or delete the old vpc-demo-subnet1 first
```

### Everything HA VPN lives in one region

A tunnel can only connect two gateways **in the same region**, so both
gateways, both routers and all four tunnels go in REGION 1 — the region of
the `on-prem` network. Putting the `on-prem` gateway in the other region is
the classic way to lose this lab: the tunnel create call is rejected with a
message that does not mention the region.

### The interfaces have to match

`vpc-demo-tunnel0` uses interface `0` and points at `on-prem-vpn-gw1`; on the
other side `on-prem-tunnel0` also uses interface `0`. A crossed pair still
creates fine and still reports `ESTABLISHED` — it just is not the topology
the lab asks for, and the 99.99% SLA does not hold.

### The shared secret is generated once and kept

All four tunnels need the same IKE shared secret, and it has to be the same
on both ends of each tunnel. The script generates one, writes it to
`~/gsp-ha-vpn/shared_secret` and reuses it, so a re-run does not break the
pair. `--secret` overrides it.

### Global dynamic routing is what makes the second region reachable

`vpc-demo` has a subnet in REGION 2. With the default regional routing, the
Cloud Router in REGION 1 only advertises the subnets in its own region, so
`vpc-demo-instance2` never answers a ping from `on-prem`:

```bash
gcloud compute networks update vpc-demo --bgp-routing-mode=GLOBAL
```

The `on-prem` network keeps its regional routing — its subnet and its
router are both in REGION 1, so it does not need it.

### Task 7 deletes a tunnel on purpose

The lab's task 7 brings `vpc-demo-tunnel0` down to prove the high
availability: the peer tunnel reports a broken handshake and the traffic
moves to the second tunnel. The script does exactly that, and the ping at
the end proves the traffic still flows.

If the lab's progress panel turns out to want all four tunnels, re-run with
`--keep-tunnel0` and the script will leave `vpc-demo-tunnel0` alone.

### The creates block for about a minute

A gateway, a router, a tunnel and a VM all take roughly a minute, and a
silent wait looks exactly like a hang. Those calls stream their output with
a heartbeat, so the script never looks stuck.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region1 REGION` | from zone 1 | REGION 1 of the lab |
| `--region2 REGION` | from zone 2 | REGION 2 of the lab |
| `--zone1 ZONE` | `$ZONE` / `$Z1` | Zone of `vpc-demo-instance1` |
| `--zone2 ZONE` | `$ZONE_1` / `$Z2` | Zone of `vpc-demo-instance2` |
| `--zone3 ZONE` | `$ZONE_2` / `$Z3` | Zone of `on-prem-instance1` |
| `--secret S` | generated once | The IKE shared secret |
| `--machine-type T` | `e2-medium` | The VM machine type |
| `--task N` | all | Run only task N (1–7) |
| `--yes` | off | Do not pause for the checkpoints |
| `--no-verify` | off | Do not wait for the tunnels and skip the ping tests |
| `--keep-tunnel0` | off | Skip the task 7 HA test, keep `vpc-demo-tunnel0` |
| `-h, --help` | | Usage |

---

## Configure an Application Load Balancer with Autoscaling

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_alb_autoscaling.sh
chmod +x gsp_alb_autoscaling.sh
./gsp_alb_autoscaling.sh
```

| Task | What the script does |
|---|---|
| 1 | `fw-allow-health-checks` — tcp:80 from `130.211.0.0/22` and `35.191.0.0/16` to the instances tagged `allow-health-checks` ⏸ |
| 2 | the Cloud Router `nat-router-us1` and the Cloud NAT `nat-config` in `us-east4`, and waits for it to be `RUNNING` ⏸ |
| 3 | the `webserver` VM with no external IP, Apache installed by a startup script, the image `mywebserver` from its boot disk, and the VM deleted ⏸ |
| 4 | the health check `http-health-check` (HTTP), the template `mywebserver-template`, and the two groups `us-1-mig` and `notus-1-mig` with autoscaling and autohealing ⏸ |
| 5 | the backend service `http-backend` with both backends, the URL map, the proxy, and the IPv4 and IPv6 forwarding rules ⏸ |
| 6 | the `stress-test` VM, ApacheBench against the load balancer, and a wait for the autoscaler to add an instance ⏸ |

The lab's regions and zones **change with every run** — the same lab was
`us-east4` / `us-east4-c` one day and `us-central1` / `us-central1-a` the
next. So the script never assumes them: it takes what the lab exports
(`ZONE`, `ZONE_1`, `REGION`, `REGION_1`), offers the project default as a
suggestion, and asks for the rest:

```
  Region 1 - the NAT and the us-1-mig group [us-central1]:
  Region 2 - the notus-1-mig group (a different region) [asia-south1]:
  Zone 1 - the webserver VM (in REGION 1 = us-central1) [us-central1-a]:
  Region for the stress test VM (a US region, not us-central1) [us-east1]:
  Zone for the stress test VM (in us-east1) [us-east1-b]:
```

Every zone is checked against the API before it is used, and the zone
candidates of the region are listed, so the answer is never a guess.

The second region has been `asia-south1` both times, and the stress test VM
is the one value the lab genuinely leaves to you: it has to go in a **US**
region other than the first one, so the load balancer forwards the traffic
to the closer backend.

### The health check is HTTP, and it is the legacy kind

```bash
gcloud compute health-checks create http http-health-check --port=80
```

The lab asks for HTTP on port 80, and the health check has to be the
**legacy** one — the kind without a region, which is what the autohealing
of a regional instance group accepts. Creating it with `--global` gives you
the newer kind, and the autohealing then fails with *"the health check must
be a legacy health check"*.

Because that is easy to get wrong, the script detects it: if the autohealing
refuses the health check, it replaces it with a legacy one and tries again.
And a failed sub-step never stops the lab — it is reported, counted in the
summary, and everything after it still runs.

### The template must not pin a subnet

An instance template is a **global** resource and both instance groups use
it — one in each of the lab's two regions. So the template's network
interface names the network but no subnet, and every VM picks up the default
subnet of its own region:

```bash
--network-interface=network=default,no-address
```

Pinning a subnet there breaks the second group: the VMs land in the first
region's subnet and the group never becomes healthy.

### The web server VM has no external IP — on purpose

The lab wants the backends to be reachable only through the load balancer,
so the `webserver` VM is created with `no-address`. That means it cannot
reach the internet on its own, which is exactly why task 2 puts a **Cloud
NAT** in place first. Apache is installed by a startup script that goes out
through that NAT, and the script waits for the serial console to report
`STARTUP-SCRIPT-DONE` before it images the disk.

### The two backends get different balancing modes

`us-1-mig` is **rate** based (50 RPS per instance) and `notus-1-mig` is
**utilization** based (80% CPU), which is what the lab asks for and what
makes the two backends behave differently under the stress test.

The backend service refers to the port by the name `http`, so both groups
need that named port:

```bash
gcloud compute instance-groups managed set-named-ports us-1-mig \
    --region=REGION --named-ports=http:80
```

### Two forwarding rules, one proxy

The lab asks for IPv4 **and** IPv6. Both forwarding rules point at the same
target HTTP proxy, and each gets its own address:

```bash
gcloud compute forwarding-rules create http-lb-ipv4 --global \
    --target-http-proxy=http-lb-proxy --ports=80 --ip-version=IPV4
gcloud compute forwarding-rules create http-lb-ipv6 --global \
    --target-http-proxy=http-lb-proxy --ports=80 --ip-version=IPV6
```

### The stress test runs in the background

`ab -n 500000 -c 1000` takes a long time, so the script starts it with
`nohup` on the VM and then watches the instance groups scale up. The log is
at `/tmp/ab.log` on the VM:

```bash
gcloud compute ssh stress-test --zone=STRESS_ZONE --command="cat /tmp/ab.log"
```

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region1 REGION` | the project default | The NAT and `us-1-mig` |
| `--region2 REGION` | `asia-south1` | `notus-1-mig` |
| `--zone1 ZONE` | the project default | The `webserver` VM |
| `--stress-region R` | `us-east1` | The region of the stress test VM |
| `--stress-zone Z` | a zone of that region | The zone of the stress test VM |
| `--task N` | all | Run only task N (1–6) |
| `--yes` | off | Do not pause for the checkpoints |
| `--no-verify` | off | Do not wait for the load balancer and skip the stress test |
| `-h, --help` | | Usage |

---

## Automating the Deployment of Infrastructure Using Terraform

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_terraform.sh
chmod +x gsp_terraform.sh
./gsp_terraform.sh
```

| Task | What the script does |
|---|---|
| 1 | Installs the real Terraform (Cloud Shell ships a placeholder wrapper), then stages `~/tfinfra/` with `provider.tf`, `instance/variables.tf`, `instance/main.tf` and `mynetwork.tf` ⏸ |
| 2 | `terraform init`, `terraform plan`, then `terraform apply` with the retry the lab needs, because the subnets of an auto mode network are still provisioning in the background ⏸ |
| 3 | Lists `mynet-vm-1` and `mynet-vm-2` and pings one from the other over the IAP tunnel ⏸ |

### The lab stages everything in `~/tfinfra`

The lab is about the Terraform *workflow*, not about the resources. So the
script writes the four files the lab asks for and runs `init`, `plan` and
`apply` — it does not shortcut them. The `mynetwork.tf` is written with the
lab's two zones already substituted, so the plan is reviewable before it
runs.

### The apply has to be retried

An auto mode network creates its subnets in the background. `terraform
apply` can start before they exist, fail with a subnet error, and succeed
on the next try. The script retries up to four times with a 15 second
pause.

### The two zones are lab-assigned

The lab asks for two zones. The script takes `ZONE_1` and `ZONE_2` from the
environment and asks for whatever is missing, with the project default as the
suggestion.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone1 ZONE` | `$ZONE_1` | The zone of `mynet-vm-1` |
| `--zone2 ZONE` | `$ZONE_2` | The zone of `mynet-vm-2` |
| `--workspace PATH` | `~/tfinfra` | Where to stage the Terraform files |
| `--task N` | all | Run only task N (1–3) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

## Accessing the Google Cloud Console and Cloud Shell

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_access_console_shell.sh
chmod +x gsp_access_console_shell.sh
./gsp_access_console_shell.sh
```

| Task | What the script does |
|---|---|
| 1 | The `default-allow-http` and `allow-ssh-all` rules, the `first-vm` instance tagged `http-server`, and the `test-service-account` with the Editor role ⏸ |
| 2 | `gcloud auth list` and `gcloud config list project`, so the Cloud Shell panel in the lab matches |
| 3 | `gs://<project>-bucket1` and `-bucket2`, the `cat.jpg` upload, and the public Object Viewer grant on bucket 1 ⏸ |
| 4 | Clones `orchestrate-with-kubernetes`, adds the `Finished cleanup!` line, writes the cat `index.html`, copies it to `first-vm` and installs nginx ⏸ |

### Not the same lab as `gsp_console_shell.sh`

The repo has two similarly named labs:

- **Explore the Google Cloud Console and Cloud Shell** — `gsp_console_shell.sh`, all
  console-clicking, no compute.
- **Accessing the Google Cloud Console and Cloud Shell** (this one, CBL138) — the
  VM, the service account, the buckets and the nginx page.

### The zone is fixed by the lab text

The lab pins the location at **region `us-west1`, zone `us-west1-c`**, so the
script defaults to `us-west1-c`. `--zone` wins if a run hands out something
else, and Cloud Shell's own `$ZONE` is used when it is set.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--zone ZONE` | `us-west1-c` | The zone of `first-vm` |
| `--task N` | all | Run only task N (1–4) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

## Working with Cloud Build

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_cloud_build.sh
chmod +x gsp_cloud_build.sh
./gsp_cloud_build.sh
```

| Task | What the script does |
|---|---|
| 1 | Enables Cloud Build and Artifact Registry, and lets the Cloud Build service account push to the repository |
| 2 | Writes `quickstart.sh` and the `Dockerfile`, creates `quickstart-docker-repo`, then build 1/3 with `--tag` |
| 3 | Writes `cloudbuild.yaml` with the region substituted and runs build 2/3 with `--config` ⏸ |
| 4 | Rewrites `quickstart.sh` to fail on an argument, writes `cloudbuild2.yaml`, runs build 3/3 and confirms it fails ⏸ |

### The third build is supposed to fail

`cloudbuild2.yaml` adds a step that runs the image it just built with the
argument `fail`, and `quickstart.sh` exits 1 when it gets an argument. Cloud
Build reports `BUILD FAILURE` — that failure is the objective. The script
prints the failure lines and counts it as success; it only warns if the build
somehow passes.

### The region is fixed by the lab text

Every command in the lab spells out **`us-east4`**, and the region appears in
two places: the Artifact Registry location and the
`<region>-docker.pkg.dev` image host. A mismatch pushes the image to a
repository the grader never reads, so the script defaults to `us-east4`
(`--region` and `$REGION` still win).

If the repository cannot be created, the script now prints gcloud's actual
error instead of a bare failure line, retries for the API propagation window,
and warns that the coming push will fail.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region REGION` | `us-east4` | Artifact Registry location and image host |
| `--task N` | all | Run only task N (1–4) |
| `--yes` | off | Do not pause for the checkpoints |
| `-h, --help` | | Usage |

---

## Deploying GKE Autopilot Clusters

```bash
curl -fsSL -O https://raw.githubusercontent.com/shounakjoshi88-a11y/gcp-arcade/main/gsp_gke_autopilot.sh
chmod +x gsp_gke_autopilot.sh
./gsp_gke_autopilot.sh
```

| Task | What the script does |
|---|---|
| 1 | Enables the Kubernetes Engine API, creates the regional `autopilot-cluster-1`, waits for it, then pulls the kubeconfig ⏸ |
| 2 | **Console only.** Prints the exact clicks (*Workloads → Create deployment → `nginx-1` → Deploy*), warns you if a kubectl-created `nginx-1` is in the way, then reads the Deployment back and confirms 3/3 Pods |
| 3 | Prints the kubectl equivalent of every tab the lab has you click: details, revision history, events, YAML, the managed Pod |

### Checkpoint 2 only accepts a console-created workload

Task 1 is resource-based — `gcloud container clusters create-auto` scores it. Task 2 is **not**. Tested on a live lab:

| How `nginx-1` was created | Checkpoint 2 |
|---|---|
| `kubectl create deployment nginx-1 --image=nginx:latest --replicas=3` | 0 points |
| `kubectl create deployment` + `kubectl set image … nginx:latest` | 0 points |
| Applied YAML: container name `nginx-1`, `app=nginx-1` labels, 3 replicas, port 80, ClusterIP Service, revision 1 | 0 points |
| Same names in the console: **Workloads → Create deployment → `nginx-1` → Deploy** | **50/50** |

The last two were the same cluster minutes apart, so the object contents are not the discriminator — the grader wants the console's own action. That is why the script stops and hands you the clicks instead of deploying it for you: a kubectl-created `nginx-1` also blocks the console from using the name, so task 2 tells you to delete it first.

### This is the console variant

The repo also covers *Deploying GKE Autopilot Clusters **from Cloud Shell***,
which is a different lab with different checkpoints (*Deploy GKE clusters*,
*Deploy Pods to GKE clusters*, *Deploy a new pod using a Yaml file*). This
script is for the console lab: **Deploy GKE Autopilot cluster** and **Deploy a
sample nginx workload**.

### Autopilot is regional

There are no node pools, machine types or node counts to choose — Google
provisions and scales the nodes. The script only sets the name and the region,
which is exactly what the console dialog asks for.

### The region is assigned per run

The console makes you pick it from a dropdown, so the script reads `--region`,
then `$REGION`, and asks for anything left with `us-central1` as the
suggestion.

### Options

| Flag | Default | What it does |
|---|---|---|
| `--project ID` | active gcloud project | Target project |
| `--region REGION` | `$REGION`, else asked | The cluster's region |
| `--task N` | all | Run only task N (1–3) |
| `--yes` | off | Do not pause for the checkpoints |
| `--timeout MIN` | 30 | Reserved for the cluster wait |
| `-h, --help` | | Usage |

---

## Layout



```
gsp321.sh             # GSP321 - Develop Your Google Cloud Network
gsp156.sh             # GSP156 - Terraform Fundamentals
gsp345.sh             # GSP345 - Build Infrastructure with Terraform: Challenge Lab
gsp_marketplace.sh    # Deploy a LAMP Stack with Google Cloud Marketplace
gsp_vpc.sh            # Get Started with VPC Networking and Compute Engine
gsp_vpc_networks.sh    # Create and Configure VPC Networks
gsp_pga_nat.sh         # Implement Private Google Access and Cloud NAT
gsp_create_vms.sh      # Create Virtual Machines
gsp_minecraft.sh        # Create and Configure Virtual Machines - Minecraft server
gsp_iam.sh              # Exploring IAM
gsp_storage_buckets.sh   # Cloud Storage buckets and encryption
gsp_configure_sql.sh      # Configure Cloud SQL
gsp_bigquery_billing.sh   # Examine Billing data with BigQuery
gsp_observability.sh      # Monitor resources with Cloud Observability
gsp_storagesql.sh     # Getting Started with Cloud Storage and Cloud SQL
gsp_cloudrun.sh       # Hello Cloud Run
gsp_console_shell.sh  # Explore the Google Cloud Console and Cloud Shell
gsp_access_console_shell.sh # Accessing the Google Cloud Console and Cloud Shell
gsp_cloud_build.sh     # Working with Cloud Build
gsp_gke_autopilot.sh   # Deploying GKE Autopilot Clusters
gsp_ha_vpn.sh          # Configure Google Cloud HA VPN
gsp_alb_autoscaling.sh # Configure an Application Load Balancer with Autoscaling
gsp_internal_lb.sh     # Configure an Internal Network Load Balancer
gsp_terraform.sh       # Automating the Deployment of Infrastructure Using Terraform
TASKS.md              # GSP321, task by task, for manual runs
TASKS156.md           # GSP156, task by task, for manual runs
TASKS345.md           # GSP345, task by task, for manual runs
TASKS_marketplace.md  # Deploy a LAMP Stack with Cloud Marketplace, by hand
TASKS_vpc_networks.md  # Create and Configure VPC Networks, by hand
TASKS_pga_nat.md       # Private Google Access and Cloud NAT, by hand
TASKS_create_vms.md    # Create Virtual Machines, by hand
TASKS_minecraft.md      # Create and Configure Virtual Machines, by hand
TASKS_iam.md            # Exploring IAM, by hand
TASKS_storage_buckets.md # Cloud Storage buckets and encryption, by hand
TASKS_configure_sql.md   # Configure Cloud SQL, by hand
TASKS_bigquery_billing.md # Examine Billing data with BigQuery, by hand
TASKS_observability.md    # Cloud Observability, by hand
TASKS_storagesql.md   # Cloud Storage and Cloud SQL, task by task, for manual runs
TASKS_cloudrun.md     # Hello Cloud Run, task by task, for manual runs
TASKS_console_shell.md # Explore the Google Cloud Console and Cloud Shell, by hand
TASKS_ha_vpn.md       # Configure Google Cloud HA VPN, by hand
TASKS_alb_autoscaling.md # Configure an Application Load Balancer with Autoscaling, by hand
TASKS_internal_lb.md     # Configure an Internal Network Load Balancer, by hand
TASKS_terraform.md       # Automating the Deployment of Infrastructure with Terraform, by hand
TASKS_access_console_shell.md # Accessing the Google Cloud Console and Cloud Shell, by hand
TASKS_cloud_build.md     # Working with Cloud Build, by hand
TASKS_gke_autopilot.md   # Deploying GKE Autopilot Clusters, by hand
README.md             # this file
LICENSE               # MIT
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
