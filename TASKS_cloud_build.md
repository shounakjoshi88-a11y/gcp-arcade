# Working with Cloud Build — task by task

Manual equivalent of `gsp_cloud_build.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud config get-value compute/region)   # or copy it from the lab panel
```

The region is lab-injected, and it appears in two places: the Artifact
Registry location and the image host `<region>-docker.pkg.dev`. If it is
wrong, every push lands in a repository the grader never looks at.

---

## Task 1 — Confirm that needed APIs are enabled

```bash
gcloud services enable cloudbuild.googleapis.com artifactregistry.googleapis.com
```

Cloud Build pushes with its own service account, so it also needs write access
to the repository:

```bash
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/artifactregistry.writer"
```

No checkpoint here.

---

## Task 2 — Building containers with DockerFile and Cloud Build

```bash
cat > quickstart.sh <<'EOF'
#!/bin/sh
echo "Hello, world! The time is $(date)."
EOF
chmod +x quickstart.sh

cat > Dockerfile <<'EOF'
FROM alpine
COPY quickstart.sh /
CMD ["/quickstart.sh"]
EOF

gcloud artifacts repositories create quickstart-docker-repo \
    --repository-format=docker --location="$REGION" \
    --description="Docker repository"

gcloud builds submit --tag \
    ${REGION}-docker.pkg.dev/${PROJECT_ID}/quickstart-docker-repo/quickstart-image:tag1
```

The image then shows under **Artifact Registry → quickstart-docker-repo →
quickstart-image**.

---

## Task 3 — Building containers with a build configuration file

```bash
cat > cloudbuild.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1', '.' ]
images:
- '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
EOF

gcloud builds submit --config cloudbuild.yaml
```

Two versions of `quickstart-image` now sit in the repository, and two builds
are listed under **Cloud Build → History**.

Click **Check my progress** — *Build two container images in Cloud Build*.

---

## Task 4 — Building and testing containers with a build configuration file

Replace `quickstart.sh` so it fails when it is given an argument:

```bash
cat > quickstart.sh <<'EOF'
#!/bin/sh
if [ -z "$1" ]
then
	echo "Hello, world! The time is $(date)."
	exit 0
else
	exit 1
fi
EOF
chmod +x quickstart.sh
```

Then the build file that tests the image it just built:

```bash
cat > cloudbuild2.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1', '.' ]
- name: '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
  args: ['fail']
images:
- '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
EOF

gcloud builds submit --config cloudbuild2.yaml
echo $?     # non-zero, as the lab wants
```

Step 2 runs the freshly built image with `fail`, the script exits 1, and Cloud
Build reports `BUILD FAILURE`. **This failure is the objective** — the script
in this repo treats it as success and only complains if the build passes.

Click **Check my progress** — *Build and test containers with a build
configuration file and Cloud Build*.

---

## Clean up

```bash
gcloud artifacts repositories delete quickstart-docker-repo --location="$REGION" --quiet
```
