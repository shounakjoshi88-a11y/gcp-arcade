# Accessing the Google Cloud Console and Cloud Shell — task by task

Manual equivalent of `gsp_access_console_shell.sh`. Assumes Cloud Shell with
the lab project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud config get-value compute/zone)
```

The zone is lab-assigned per run — take it from the setup panel.

---

## Task 1 — Create a VM instance with necessary firewall rule, and an IAM service account

### The firewall rules

```bash
gcloud compute firewall-rules create default-allow-http \
    --network=default --direction=INGRESS --action=ALLOW \
    --rules=tcp:80 --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

gcloud compute firewall-rules create allow-ssh-all \
    --network=default --direction=INGRESS --action=ALLOW \
    --rules=tcp:22 --source-ranges=0.0.0.0/0
```

### The VM instance

```bash
gcloud compute instances create first-vm \
    --zone="$ZONE" --machine-type=e2-micro \
    --tags=http-server \
    --image-family=debian-12 --image-project=debian-cloud \
    --metadata=startup-script='...'
```

### The service account

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

## Task 2 — Verify Cloud Shell

```bash
gcloud auth list
gcloud config list project
```

---

## Task 3 — Create Cloud Storage Buckets

```bash
gcloud storage buckets create gs://${PROJECT_ID}-bucket1 --location=US --uniform-bucket-level-access
gcloud storage buckets create gs://${PROJECT_ID}-bucket2 --location=US

gcloud storage buckets update gs://${PROJECT_ID}-bucket1 --uniform-bucket-level-access
gcloud storage buckets update gs://${PROJECT_ID}-bucket1 --no-public-access-prevention

gcloud storage cp gs://cloud-training/ak8s/cat.jpg gs://${PROJECT_ID}-bucket1/
gcloud storage cp gs://${PROJECT_ID}-bucket1/cat.jpg gs://${PROJECT_ID}-bucket2/cat.jpg

gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID}-bucket1 \
    --member=allUsers --role=roles/storage.objectViewer
```

Click **Check my progress** — *Create Cloud Storage Buckets*.

---

## Task 4 — Cloud Shell Editor & Nginx on VM

```bash
git clone https://github.com/googlecodelabs/orchestrate-with-kubernetes.git
mkdir -p test
echo "echo Finished cleanup!" >> orchestrate-with-kubernetes/cleanup.sh

cat > index.html <<'EOF'
<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src="https://${PROJECT_ID}-bucket1/cat.jpg"> </body></html>
EOF
cp index.html orchestrate-with-kubernetes/index.html
cp index.html "$HOME/index.html"

gcloud compute scp --zone="$ZONE" index.html first-vm:index.html

gcloud compute ssh first-vm --zone="$ZONE" --command="
  sudo apt-get remove -y --purge man-db 2>/dev/null || true
  sudo touch /var/lib/man-db/auto-update
  sudo apt-get update -y && sudo apt-get install -y nginx
  sudo cp -f ~/index.html /var/www/html/index.html
  sudo systemctl restart nginx
"

curl http://$(gcloud compute instances describe first-vm --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
```

Click **Check my progress** — *Install the nginx web server and customize
the welcome page*.

---

## Clean up

```bash
gcloud compute instances delete first-vm --zone="$ZONE" --quiet
gcloud storage rm -r gs://${PROJECT_ID}-bucket1 gs://${PROJECT_ID}-bucket2
gcloud iam service-accounts delete test-service-account@${PROJECT_ID}.iam.gserviceaccount.com --quiet
gcloud compute firewall-rules delete default-allow-http allow-ssh-all --quiet
```