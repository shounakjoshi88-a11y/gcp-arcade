# Running a Containerized App on Google Kubernetes Engine — task by task

Manual equivalent of `gsp_containerized_app.sh`. Lab code **GSP015**; the whole
lab is Cloud Shell commands, so every graded objective is scriptable.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=us-east4-a          # the lab fixes this zone
```

---

## Task 1 — Creating a cluster

```bash
gcloud config set compute/zone us-east4-a
gcloud container clusters create hello-world
```

`hello-world` comes up with **three nodes** (the command's default), which is
what the lab describes. Takes 3–6 minutes.

Click **Check my progress** — *Create a Kubernetes Cluster.*

---

## Tasks 2–3 — Building and publishing the Hello World app

```bash
echo $DEVSHELL_PROJECT_ID

git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples
cd kubernetes-engine-samples/quickstarts/hello-app
cat Dockerfile

docker build -t gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0 .
```

Then publish it. The lab prints `gcloud docker -- push …`, but `gcloud docker`
was removed from the CLI years ago — use plain `docker push` after configuring
the credential helper:

```bash
gcloud auth configure-docker gcr.io
docker push gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0
```

If that push is rejected (`Container Registry is deprecated`), Google is
retiring gcr.io. Use Artifact Registry instead and deploy from that path:

```bash
gcloud artifacts repositories create hello-repo --repository-format=docker \
  --location=us-east4 --description="hello-app images"
gcloud auth configure-docker us-east4-docker.pkg.dev

docker tag  gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0 \
            us-east4-docker.pkg.dev/$DEVSHELL_PROJECT_ID/hello-repo/hello-app:1.0
docker push us-east4-docker.pkg.dev/$DEVSHELL_PROJECT_ID/hello-repo/hello-app:1.0
```

No checkpoint here — the lab scores tasks 2–3 together with the deployment.

---

## Task 4 — Deploying the Hello World app

```bash
kubectl create deployment hello-app \
  --image=gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0      # or the Artifact Registry path

kubectl get deployments
kubectl get pods
```

Click **Check my progress** — *Build and Deploy Hello World App (hello-app)*.

Then allow external traffic:

```bash
kubectl expose deployment hello-app --name=hello-app \
  --type=LoadBalancer --port=80 --target-port=8080

kubectl get svc hello-app        # repeat until EXTERNAL-IP leaves <pending>
curl http://<external-ip>/       # Hello, world!
```

The external IP usually populates in 1–3 minutes.

Click **Check my progress** — *Allow external traffic to hello-app deployment.*

---

## Task 5 — Test your understanding

| Question | Answer |
|---|---|
| `docker push` publishes the container image in Google Cloud to … | **Container Registry** |
| Kubernetes is an open-source container-orchestration system for automating deployment, scaling and management of containerized applications. | **True** |
| In Kubernetes, `kubectl expose` creates a …, the forwarding rules for the load balancer, and the firewall rules that allow external traffic. | **Service** |

---

## Clean up

```bash
kubectl delete svc hello-app --ignore-not-found
gcloud container clusters delete hello-world --zone="$ZONE" --quiet
```
