# Deploying GKE Autopilot Clusters — task by task

Manual equivalent of `gsp_gke_autopilot.sh`. This is the console version of the
lab (the CLI variant is "Deploying GKE Autopilot Clusters from Cloud Shell").

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=<the region on the lab setup panel>
```

The region is assigned per run and you pick it in the console dropdown, so it
is not something to guess.

---

## Task 1 — Deploy GKE clusters

Console: **Kubernetes Engine → Clusters → Create**, then:

| Field | Value |
|---|---|
| Cluster name | `autopilot-cluster-1` |
| Region | the lab's region |
| Everything else | default |

Autopilot is **regional by default** — the control plane spans zones and Google
provisions and scales nodes for you. There are no node pools, machine types or
node counts to set, which is why the console dialog does not ask for them.

CLI equivalent:

```bash
gcloud container clusters create-auto autopilot-cluster-1 --region "$REGION"

gcloud container clusters get-credentials autopilot-cluster-1 --region "$REGION"
```

Provisioning takes 5–15 minutes. When the cluster row shows a green check:

Click **Check my progress** — *Deploy GKE cluster*.

Then open the cluster and look at the **Storage** tab, as the lab asks.

---

## Task 2 — Deploy a sample workload

Console: **Kubernetes Engine → Workloads → Create deployment**

| Field | Value |
|---|---|
| Deployment name | `nginx-1` |
| Container image | `nginx:latest` (the default) |
| Configuration details | defaults (3 replicas) |

CLI equivalent:

```bash
kubectl create deployment nginx-1 --image=nginx --replicas=3
kubectl rollout status deployment/nginx-1
kubectl get pods -l app=nginx-1
```

Click **Check my progress** — *Deploy a sample nginx workload*.

---

## Task 3 — View details about workloads

Everything here is read-only, in the console under the `nginx-1` workload:

| Console tab | kubectl |
|---|---|
| Overview | `kubectl get deployment nginx-1` |
| Details | `kubectl describe deployment nginx-1` |
| Revision History | `kubectl rollout history deployment/nginx-1` |
| Events | `kubectl get events --sort-by=.lastTimestamp` |
| YAML | `kubectl get deployment nginx-1 -o yaml` |
| Managed Pods → a Pod | `kubectl get pod <pod> -o wide` and `-o yaml` |

No checkpoint — the lab only asks you to look.

---

## Clean up

```bash
gcloud container clusters delete autopilot-cluster-1 --region="$REGION" --quiet
```
