# GSP321 — task by task

Manual equivalent of `gsp321.sh`, in case you'd rather run the commands
yourself. Every step assumes Cloud Shell with the lab project active.

```bash
export REGION=us-central1
export ZONE=us-central1-a
export PROJECT_ID=$(gcloud config get-value project)
```

---

## Task 1 — Development VPC (manual)

```bash
gcloud compute networks create griffin-dev-vpc --subnet-mode custom

gcloud compute networks subnets create griffin-dev-wp \
    --network=griffin-dev-vpc --region $REGION --range=192.168.16.0/20

gcloud compute networks subnets create griffin-dev-mgmt \
    --network=griffin-dev-vpc --region $REGION --range=192.168.32.0/20
```

## Task 2 — Production VPC (Deployment Manager)

```bash
gsutil cp -r gs://cloud-training/gsp321/dm .
cd dm
sed -i s/SET_REGION/$REGION/g prod-network.yaml
gcloud deployment-manager deployments create prod-network \
    --config=prod-network.yaml
cd ..
```

The `dm/prod-network.jinja` template creates `griffin-prod-vpc` with
`griffin-prod-wp` (192.168.48.0/20) and `griffin-prod-mgmt` (192.168.64.0/20).

## Task 3 — Bastion host

```bash
gcloud compute instances create bastion \
    --network-interface=network=griffin-dev-vpc,subnet=griffin-dev-mgmt \
    --network-interface=network=griffin-prod-vpc,subnet=griffin-prod-mgmt \
    --tags=ssh --zone=$ZONE

gcloud compute firewall-rules create fw-ssh-dev \
    --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 \
    --network=griffin-dev-vpc

gcloud compute firewall-rules create fw-ssh-prod \
    --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 \
    --network=griffin-prod-vpc
```

## Task 4 — Cloud SQL

```bash
gcloud sql instances create griffin-dev-db \
    --database-version=MYSQL_5_7 \
    --region=$REGION \
    --root-password='awesome'

gcloud sql databases create wordpress --instance=griffin-dev-db

gcloud sql users create wp_user --instance=griffin-dev-db \
    --password=stormwind_rules
```

Or use the built-in client:

```bash
gcloud sql connect griffin-dev-db
```

```sql
CREATE DATABASE wordpress;
CREATE USER "wp_user"@"%" IDENTIFIED BY "stormwind_rules";
GRANT ALL PRIVILEGES ON wordpress.* TO "wp_user"@"%";
FLUSH PRIVILEGES;
exit
```

## Task 5 — Kubernetes cluster

```bash
gcloud container clusters create griffin-dev \
    --network griffin-dev-vpc \
    --subnetwork griffin-dev-wp \
    --machine-type e2-standard-4 \
    --num-nodes 2 \
    --zone $ZONE

gcloud container clusters get-credentials griffin-dev --zone $ZONE
```

## Task 6 — Prepare the cluster

```bash
gsutil cp -r gs://cloud-training/gsp321/wp-k8s .
cd wp-k8s
```

`wp-env.yaml` — replace the placeholder credentials:

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: wordpress-volumeclaim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: database
type: Opaque
stringData:
  username: wp_user
  password: stormwind_rules
```

```bash
kubectl create -f wp-env.yaml

gcloud iam service-accounts keys create key.json \
    --iam-account=cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com

kubectl create secret generic cloudsql-instance-credentials \
    --from-file key.json
```

## Task 7 — WordPress deployment

In `wp-deployment.yaml`, replace `YOUR_SQL_INSTANCE` with the connection name:

```bash
gcloud sql instances describe griffin-dev-db --format='value(connectionName)'
# project:region:instance
```

```bash
kubectl create -f wp-deployment.yaml
kubectl create -f wp-service.yaml

kubectl get deployments
kubectl get services
```

`wp-service.yaml` is `type: LoadBalancer`, so an external IP appears in a few
minutes. **Wait for it** — Task 8 depends on it.

## Task 8 — Monitoring (uptime check)

```bash
# 1. wait for the external IP
until [ -n "$WP_IP" ]; do
  WP_IP=$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$WP_IP" ] || sleep 15
done
echo "$WP_IP"

# 2. create the check - BOTH labels are required for uptime_url
gcloud monitoring uptime create wordpress-uptime-check \
    --resource-type=uptime-url \
    --resource-labels="host=$WP_IP,project_id=$PROJECT_ID"

# 3. confirm
gcloud monitoring uptime list-configs \
    --format="table(name.basename(), resourceLabels.host, resourceLabels.project_id)"
```

> **The two traps here.** (a) Reading the IP before the LoadBalancer has one
> gives an empty string → `INVALID_ARGUMENT: uptime_url check is missing a
> host; uptime_url check has malformed host`. (b) Omitting `project_id` makes
> the request invalid too — `uptime_url` requires both labels.

If a check with a bad host already exists, delete it first:

```bash
gcloud monitoring uptime delete wordpress-uptime-check
```

## Task 9 — Additional engineer access

```bash
gcloud projects get-iam-policy $PROJECT_ID --format=json \
  | jq -r '.bindings[] | select(.role == "roles/viewer").members[]'
```

Promote every `user:` that has Viewer to Editor:

```bash
for USER in $(gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/viewer" \
    --format="value(bindings.members)"); do
  case "$USER" in
    user:*)
      gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="$USER" --role=roles/editor
      ;;
  esac
done
```

Or just edit the role in the console: **IAM & Admin → the second user → Edit →
Role → Editor → Save**.

---

## Teardown

These are real billable resources.

```bash
gcloud container clusters delete griffin-dev --zone $ZONE
gcloud sql instances delete griffin-dev-db
gcloud deployment-manager deployments delete prod-network
gcloud compute instances delete bastion --zone $ZONE
gcloud compute firewall-rules delete fw-ssh-dev fw-ssh-prod
gcloud compute networks delete