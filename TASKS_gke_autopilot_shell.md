# Deploying GKE Autopilot Clusters from Cloud Shell — task by task

Manual equivalent of `gsp_gke_autopilot_shell.sh`. This is the **Cloud Shell**
lab, not the console one (`gsp_gke_autopilot.sh`). Every command is in the lab,
so all three graded objectives are scriptable — unlike the console variant,
whose second checkpoint refused four different kubectl-built workloads.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export my_region=us-west1        # the zone/region is assigned per run
```

The region comes from the project metadata when it is set. If it is not, read it
off the lab's setup panel or from the org policy, exactly as the script does:

```bash
gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])"

# what the org policy actually allows (it rejects everything else)
gcloud resource-manager org-policies describe constraints/gcp.resourceLocations \
  --project "$PROJECT_ID" --effective --format="value(listPolicy.allowedValues)"
```

---

## Task 1 — Deploy the GKE cluster

```bash
gcloud container clusters create-auto autopilot-cluster-1 --region "$my_region"
```

Autopilot is **regional** and has no node pools, node counts or machine types —
Google provisions the nodes. 5–15 minutes.

Click **Check my progress** — *Deploy GKE clusters.*

---

## Tasks 2–3 — Connect to the cluster and inspect it

Read-only; nothing is graded here.

```bash
gcloud container clusters get-credentials autopilot-cluster-1 --region "$my_region"

kubectl config current-context
kubectl config use-context gke_${PROJECT_ID}_${my_region}_autopilot-cluster-1
kubectl cluster-info
kubectl config get-contexts
kubectl config view          # certificate data shows as DATA+OMITTED
nano ~/.kube/config
```

---

## Task 4 — Deploy Pods to the cluster

```bash
kubectl create deployment --image nginx nginx-1
kubectl get pods                     # wait for 1/1 Running
kubectl top nodes                    # metrics take a minute to appear
kubectl top pods
```

Autopilot starts with zero nodes, so the Pod can sit `Pending` for a couple of
minutes while the first node is created. That is normal — wait for `Running`.

Put the Pod's name in a variable, then push `test.html` into the running
container:

```bash
export my_nginx_pod=$(kubectl get pods -l app=nginx-1 -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$my_nginx_pod"

nano ~/test.html            # <title>This is title</title> + <h1>Hello world</h1>
kubectl cp ~/test.html $my_nginx_pod:/usr/share/nginx/html/test.html
```

Expose the **Pod** (that is the lab's command — the Service is named after the
Pod, e.g. `nginx-1-6b7bff9fc7-t7fzk`):

```bash
kubectl expose pod $my_nginx_pod --port 80 --type LoadBalancer
kubectl get services        # repeat until EXTERNAL-IP leaves <pending>
curl http://<external-ip>/test.html
```

Click **Check my progress** — *Deploy Pods to GKE clusters.*

---

## Task 5 — Deploy a new Pod from a YAML manifest

The lab clones `training-data-analyst` (a multi-gigabyte repo) only to read one
file, so write the manifest yourself. It is the lab's content verbatim:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: new-nginx
  labels:
    name: new-nginx
spec:
  containers:
  - name: new-nginx
    image: nginx
    ports:
    - containerPort: 80
```

```bash
kubectl apply -f new-nginx-pod.yaml
kubectl get pods            # new-nginx 1/1 Running
```

Click **Check my progress** — *Deploy a new pod using a Yaml file.*

### The rest of task 5 is interactive — do it by hand

Nothing is graded after this point, and all of it needs a terminal, a second
Cloud Shell tab and a text editor:

```bash
kubectl exec -it new-nginx -- /bin/bash
  apt-get update && apt-get install -y nano
  cd /usr/share/nginx/html
  nano test.html            # <title>This is title</title> + <h1>Hello world</h1>
  exit

kubectl port-forward new-nginx 10081:80      # tab 2:
curl http://127.0.0.1:10081/test.html

kubectl logs new-nginx -f --timestamps       # tab 3
```

---

## Notes

- **No knowledge check** in this lab, so there are no answers to record.
- The lab's `kubectl create deployment --image nginx nginx-1` uses the bare
  `nginx` tag; the script keeps it that way. Autopilot's admission controller
  rewrites the image to a digest, which is why `describe pod` shows a
  `docker.io/library/nginx@sha256:…` ID.
- `kubectl cp` needs the container running. If it fails with `no such file or
  directory`, the Pod is still pulling the image — re-run task 4.

---

## Clean up

```bash
kubectl delete pod new-nginx --ignore-not-found
kubectl delete deployment nginx-1 --ignore-not-found
gcloud container clusters delete autopilot-cluster-1 --region="$my_region" --quiet
```
