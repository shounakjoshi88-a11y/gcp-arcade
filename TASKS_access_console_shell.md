# Accessing the Google Cloud Console and Cloud Shell — task by task

Manual equivalent of `gsp_access_console_shell.sh`. Assumes Cloud Shell with
the lab project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The lab text fixes the location: **region `us-west1`, zone `us-west1-c`**.

---

## Task 1 — Explore the Google Cloud console

### The VM instance

Console path: **Compute Engine → VM instances → Create instance**.

| Field | Value |
|---|---|
| Name | `first-vm` |
| Region | `us-west1` |
| Zone | `us-west1-c` |
| Machine type | `e2-micro` (Shared-core) |
| Networking → Firewall | **Allow HTTP traffic** |

`Allow HTTP traffic` adds the `http-server` network tag and needs a firewall
rule that opens tcp:80 to it. That is what the console creates as
`default-allow-http`; the CLI equivalent is:

```bash
gcloud compute firewall-rules create default-allow-http \
    --network=default --direction=INGRESS --action=ALLOW \
    --rules=tcp:80 --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

gcloud compute instances create first-vm \
    --zone=us-west1-c --machine-type=e2-micro \
    --tags=http-server \
    --image-family=debian-12 --image-project=debian-cloud
```

### The service account

**IAM & Admin → Service Accounts → + Create service account**

- Service account name: `test-service-account`
- Role: **Basic → Editor**

```bash
gcloud iam service-accounts create test-service-account \
    --display-name="Test Service Account"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:test-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/editor"
```

Click **Check my progress** — *Create a VM instance with necessary firewall
rule, and an IAM service account*.

---

## Task 2 — Explore Cloud Shell

No resources, just verification that Cloud Shell is already authenticated:

```bash
gcloud auth list
gcloud config list project
echo $DEVSHELL_PROJECT_ID
pwd
gcloud storage buckets create --help   # CTRL+C to leave the pager
```

No checkpoint here.

---

## Task 3 — Create Cloud Storage Buckets

### bucket 1, in the console

**Cloud Storage → Buckets → Create bucket**

| Field | Value |
|---|---|
| Name | `<project-id>-bucket1` |
| Location type | Multi-region → `us` |
| Storage class | default |
| Enforce public access prevention | **deselected** |
| Access control | Uniform |

### bucket 2, in Cloud Shell

```bash
gcloud storage buckets create gs://${PROJECT_ID}-bucket2 --location=US
gcloud storage buckets list
```

### the cat picture

```bash
gcloud storage cp gs://cloud-training/ak8s/cat.jpg cat.jpg
gcloud storage cp cat.jpg gs://${PROJECT_ID}-bucket1
gcloud storage cp gs://${PROJECT_ID}-bucket1/cat.jpg gs://${PROJECT_ID}-bucket2/cat.jpg
```

### make bucket 1 public

Console: bucket → **Permissions** → **Grant access** → principal `allUsers`
→ role **Storage Object Viewer** → Save → **Allow Public Access**.

```bash
gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID}-bucket1 \
    --member=allUsers --role=roles/storage.objectViewer
```

The public link is `https://storage.googleapis.com/<project-id>-bucket1/cat.jpg`
— open it in an incognito tab to confirm.

Click **Check my progress** — *Create Cloud Storage Buckets*.

---

## Task 4 — Explore the Cloud Shell Editor

```bash
git clone https://github.com/googlecodelabs/orchestrate-with-kubernetes.git
mkdir test
echo "echo Finished cleanup!" >> orchestrate-with-kubernetes/cleanup.sh
cd orchestrate-with-kubernetes && cat cleanup.sh
```

New file `orchestrate-with-kubernetes/index.html`:

```html
<html><head><title>Cat</title></head>
<body>
<h1>Cat</h1>
<img src="https://storage.googleapis.com/PROJECT_ID-bucket1/cat.jpg">
</body></html>
```

Replace `PROJECT_ID` with the real project ID. Then install nginx on the VM
(SSH button on the VM instances page) and copy the page across:

```bash
# in the SSH window on first-vm
sudo apt-get remove -y --purge man-db
sudo touch /var/lib/man-db/auto-update
sudo apt-get update
sudo apt-get install -y nginx

# back in Cloud Shell
gcloud compute scp index.html first-vm:index.html --zone=us-west1-c

# in the SSH window again
sudo cp index.html /var/www/html
```

Finally open `http://<first-vm external IP>/` — the cat page appears.

Click **Check my progress** — *Install the nginx web server and customize the
welcome page*.

---

## Clean up

```bash
gcloud compute instances delete first-vm --zone=us-west1-c --quiet
gcloud storage rm -r gs://${PROJECT_ID}-bucket1 gs://${PROJECT_ID}-bucket2
gcloud iam service-accounts delete test-service-account@${PROJECT_ID}.iam.gserviceaccount.com --quiet
gcloud compute firewall-rules delete default-allow-http allow-ssh-all --quiet
```
