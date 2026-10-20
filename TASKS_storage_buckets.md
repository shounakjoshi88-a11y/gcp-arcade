# Create and Manage Cloud Storage Buckets and Encryption — task by task

Manual equivalent of `gsp_storage_buckets.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The bucket name has to be globally unique — the project ID works. The region
comes from your lab setup panel.

The five checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a Cloud Storage bucket | 20 |
| 2 | Make file publicly readable | 20 |
| 3 | Customer-supplied encryption keys (CSEK) | 20 |
| 4 | Enable lifecycle management | 20 |
| 5 | Enable versioning | 20 |

---

## Task 1 — Prepare the lab environment

```bash
export BUCKET_NAME_1=$PROJECT_ID

gcloud storage buckets create gs://$BUCKET_NAME_1 \
    --location=REGION \
    --no-uniform-bucket-level-access \
    --public-access-prevention=inherited
```

> **Two settings matter.** The lab wants *Fine-grained* access (object-level
> permissions) and **public access prevention unchecked**. Without both of
> them the ACL step below cannot make an object public.
>
> ```bash
> gsutil uniformbucketlevelaccess set off gs://$BUCKET_NAME_1
> ```

Download the sample file and make the two copies:

```bash
curl https://hadoop.apache.org/docs/current/hadoop-project-dist/hadoop-common/ClusterSetup.html > setup.html
cp setup.html setup2.html
cp setup.html setup3.html
```

Click **Check my progress** — *Create a Cloud Storage bucket*.

## Task 2 — Access control lists (ACLs)

```bash
gcloud storage cp setup.html gs://$BUCKET_NAME_1/

gcloud storage objects get-iam-policy gs://$BUCKET_NAME_1/setup.html
gcloud storage objects update gs://$BUCKET_NAME_1/setup.html --predefined-acl=private
gcloud storage objects get-iam-policy gs://$BUCKET_NAME_1/setup.html

gcloud storage objects add-iam-policy-binding gs://$BUCKET_NAME_1/setup.html \
    --member="allUsers" \
    --role="roles/storage.legacyObjectReader"
```

Click **Check my progress** — *Make file publicly readable*.

In the console, `setup.html` should now show a public link.

## Task 3 — Customer-supplied encryption keys (CSEK)

Generate a key:

```bash
python3 -c 'import base64, os; print(base64.b64encode(os.urandom(32)).decode())'
```

Put it in `~/.boto` — uncomment the `encryption_key=` line and paste the key
after it. If the file is empty, create it first:

```bash
gsutil config -n
nano ~/.boto
```

Upload the two other files, encrypted:

```bash
gsutil kms encryption -d gs://$BUCKET_NAME_1
gsutil cp setup2.html gs://$BUCKET_NAME_1/
gsutil cp setup3.html gs://$BUCKET_NAME_1/
```

Click **Check my progress** — *Customer-supplied encryption keys (CSEK)*.

> **The script's shortcut.** Every `gsutil` call in the lab relies on the key
> being in `~/.boto`. The script passes it explicitly instead, which works
> whatever the boto file looks like:
>
> ```bash
> gsutil -o "GS:encryption_key=$KEY" cp setup2.html gs://$BUCKET_NAME_1/
> ```
>
> It still writes the key into `~/.boto` as well, so the console and the file
> match the lab.

## Task 4 — Rotate the CSEK key

In `~/.boto`, comment out `encryption_key=`, and put the **old** key on the
`decryption_key1=` line. Then generate a new key and put it on the
`encryption_key=` line.

```bash
python3 -c 'import base64, os; print(base64.b64encode(os.urandom(32)).decode())'
```

Rewrite one object with the new key — it decrypts with the old key and
encrypts with the new one:

```bash
gsutil rewrite -k gs://$BUCKET_NAME_1/setup2.html
```

`setup3.html` was **not** rewritten, so it still has the old key. Download it
with the old key, and `setup2.html` with the new one:

```bash
gsutil cp gs://$BUCKET_NAME_1/setup2.html recover2.html
gsutil cp gs://$BUCKET_NAME_1/setup3.html recover3.html
```

## Task 5 — Enable lifecycle management

`life.json`:

```json
{
  "rule":
  [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 31}
    }
  ]
}
```

```bash
gcloud storage buckets update gs://$BUCKET_NAME_1 --lifecycle-file=life.json
gcloud storage buckets describe gs://$BUCKET_NAME_1 --format="json(lifecycle)"
```

Click **Check my progress** — *Enable lifecycle management*.

## Task 6 — Enable versioning

```bash
gcloud storage buckets update gs://$BUCKET_NAME_1 --versioning
gcloud storage buckets describe gs://$BUCKET_NAME_1 --format="json(versioning_enabled)"
```

Click **Check my progress** — *Enable versioning*.

Then make a couple of versions and recover the original:

```bash
# change the file
printf '\n<!-- a change -->\n' >> setup.html
gcloud storage cp setup.html gs://$BUCKET_NAME_1

gsutil ls -a gs://$BUCKET_NAME_1/setup.html
export VERSION_NAME=gs://$BUCKET_NAME_1/setup.html#1584457872853517
gcloud storage cp $VERSION_NAME recovered.txt
```

The first listed version is the oldest one.

## Task 7 — Synchronize a directory

```bash
mkdir -p firstlevel/secondlevel
cp setup.html firstlevel/
cp setup.html firstlevel/secondlevel/

gcloud storage rsync ./firstlevel gs://$BUCKET_NAME_1/firstlevel --recursive
```

## Clean up

```bash
gcloud storage rm -r gs://$BUCKET_NAME_1
```
