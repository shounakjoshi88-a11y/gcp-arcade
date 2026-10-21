# Exploring IAM — task by task

Manual equivalent of `gsp_iam.sh`. Assumes Cloud Shell with the lab project
active, signed in as **Username 1**.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

This lab uses **two** Google accounts. Username 1 is you; **Username 2** is in
the lab's Connection Details panel. Keep Username 1 signed in — signing out
deletes Username 2.

The four checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a bucket and upload a sample file | 25 |
| 2 | Remove project access | 25 |
| 3 | Add storage permissions | 25 |
| 4 | Set up the Service Account User and create a VM | 25 |

---

## Task 1 — Sign in with both users

Open an incognito window, sign in as Username 1. Open a second tab, click the
user icon → **Add account**, and sign in as Username 2.

## Task 2 — Explore the IAM console

**IAM & admin → IAM → Grant Access**, and open the role drop-down to see the
roles. Cancel. Then switch to the Username 2 tab and look at the IAM page —
Username 2 can see the policy but cannot edit it, because it does not have
the Project Owner role.

## Task 3 — Create a bucket and upload a sample file

```bash
gcloud storage buckets create -l US gs://$PROJECT_ID
```

The object in the bucket has to be called **`sample.txt`** — the lab has you
upload a file and rename it, so the name is what matters:

```bash
printf 'This is a sample file for the Exploring IAM lab.\n' > ~/sample.txt
gcloud storage cp ~/sample.txt gs://$PROJECT_ID/sample.txt
```

Click **Check my progress** — *Create a bucket and upload a sample file*.

Then switch to the **Username 2** tab: **Cloud Storage → Buckets** should show
the bucket.

## Task 4 — Remove project access

Find Username 2 — it is the user that holds `roles/viewer` and is not you:

```bash
gcloud projects get-iam-policy $PROJECT_ID --format="json" | \
  jq -r '.bindings[] | select(.role == "roles/viewer") | .members[]?'
```

Remove the Viewer role:

```bash
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member=user:USER_2_EMAIL --role=roles/viewer
```

> **Careful.** Removing the role from the wrong user — especially yourself —
> means restarting the lab. Username 2 is the *viewer* who is not
> `student_xx`; the script works this out for you.

Click **Check my progress** — *Remove project access*.

In the Username 2 tab, **Cloud Storage → Buckets** now shows an error.

## Task 5 — Add storage permissions

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=user:USER_2_EMAIL --role=roles/storage.objectViewer
```

Click **Check my progress** — *Add storage permissions*.

In the Username 2 tab, open Cloud Shell and run:

```bash
gcloud storage ls gs://$PROJECT_ID
```

Username 2 has no project Viewer role, so it cannot see the project in the
console — only this one bucket.

## Task 6 — Set up the Service Account User

### The service account

```bash
gcloud iam service-accounts create read-bucket-objects \
    --display-name="read-bucket-objects"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:read-bucket-objects@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer"
```

### The Service Account User role, for the whole company

```bash
gcloud iam service-accounts add-iam-policy-binding \
    read-bucket-objects@$PROJECT_ID.iam.gserviceaccount.com \
    --member=domain:altostrat.com --role=roles/iam.serviceAccountUser
```

`altostrat.com` is a fake company Google uses for training.

### Compute Engine access for the company

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=domain:altostrat.com --role=roles/compute.instanceAdmin.v1
```

### The VM

```bash
gcloud compute instances create demoiam \
    --zone=ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 --image-project=debian-cloud \
    --service-account=read-bucket-objects@$PROJECT_ID.iam.gserviceaccount.com \
    --scopes="https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.read_write"
```

The **Storage: Read Write** access scope matters — it is what lets
`gcloud storage cp` work from inside the VM at all.

Click **Check my progress** — *Set up the Service Account User and create a VM*.

## Task 7 — Explore the Service Account User role

SSH into `demoiam` with the console's **SSH** button — over SSH you act as the
service account.

```bash
gcloud compute instances list
```

> WARNING: Some requests did not succeed. — Request had insufficient
> authentication scopes.

The service account has no `compute.instance.list`. But it can read storage:

```bash
gcloud storage cp gs://$PROJECT_ID/sample.txt .
mv sample.txt sample2.txt
gcloud storage cp sample2.txt gs://$PROJECT_ID
```

> AccessDeniedException: 403 Caller does not have storage.objects.create
> access to bucket ...

It may read objects, not create them — the service account has Storage Object
**Viewer**.

Now give it the right role. In the console: **IAM & admin → Service Accounts
→ read-bucket-objects → Edit → Storage Object Creator → Save**. Or:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:read-bucket-objects@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectCreator"
```

The upload succeeds now.

## Clean up

```bash
gcloud compute instances delete demoiam --zone=ZONE --quiet
gcloud iam service-accounts delete read-bucket-objects@$PROJECT_ID.iam.gserviceaccount.com --quiet
gcloud storage rm -r gs://$PROJECT_ID
```
