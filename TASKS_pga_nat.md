# Implement Private Google Access and Cloud NAT — task by task

Manual equivalent of `gsp_pga_nat.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The zone is lab-assigned per run — take it from the setup panel.

The three checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create the VM instance | 30 |
| 2 | Create a Cloud Storage bucket and Enable Private Google Access | 40 |
| 3 | Configure a Cloud NAT gateway | 30 |

---

## Task 1 — Create the VM instance

### The network and the subnet

```bash
gcloud compute networks create privatenet --subnet-mode=custom

gcloud compute networks subnets create privatenet-us \
    --network=privatenet --region=REGION --range=10.130.0.0/20
```

> **Do not enable Private Google Access yet** — the lab turns it on in task 2
> so you can see the difference.

### The firewall rule

IAP tunnels arrive from a fixed range, so the SSH rule can be limited to it:

```bash
gcloud compute firewall-rules create privatenet-allow-ssh \
    --network=privatenet --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:22 --source-ranges=35.235.240.0/20
```

### The VM instance with no external IP

```bash
gcloud compute instances create vm-internal \
    --zone=ZONE \
    --machine-type=e2-standard-2 \
    --network-interface=network=privatenet,subnet=privatenet-us,no-address \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard
```

`no-address` is the CLI form of the console's **External IPv4 address: None**.

Click **Check my progress** — *Create the VM instance*.

### Test the IAP tunnel

```bash
gcloud compute ssh vm-internal --zone=ZONE --tunnel-through-iap
```

Inside the VM:

```bash
ping -c 2 www.google.com
```

This **fails** — the instance has no external IP address.

```bash
exit
```

## Task 2 — Enable Private Google Access

### The multiple-choice questions in task 2

**"Currently, which of your VM instances can access the image from your
bucket?"** — tick **Cloud Shell** only.

This question sits *before* Private Google Access is enabled, so it asks
about the state right now:

| Option | Answer |
|---|---|
| Cloud Shell | **Yes** — it is a Compute Engine VM with an external IP address, so the copy works |
| `vm-internal` | **No** — it has no external IP and Private Google Access is disabled by default, so it can only reach inside the VPC |

Once you switch Private Google Access on at the subnet level, `vm-internal`
can read the object too.

**"Did the command prompt change to @vm-internal?"** — **True**.

After `gcloud compute ssh vm-internal --tunnel-through-iap` you are inside the
VM and the prompt reads `student-xx@vm-internal:~$` — the instance name sits
after the `@`.

### The bucket and the test object

```bash
export MY_BUCKET=$PROJECT_ID

gcloud storage buckets create gs://$MY_BUCKET --location=US

gcloud storage cp gs://cloud-training/gcpnet/private/access.svg gs://$MY_BUCKET
```

From Cloud Shell the object reads back fine, because Cloud Shell has an
external IP:

```bash
gcloud storage cp gs://$MY_BUCKET/*.svg .
```

From `vm-internal` the same command **fails**, because Private Google Access
is disabled by default.

### Enable Private Google Access

Private Google Access is a **subnet** setting:

```bash
gcloud compute networks subnets update privatenet-us \
    --region=REGION --enable-private-ip-google-access
```

Click **Check my progress** — *Create a Cloud Storage bucket and Enable
Private Google Access*.

Now the same copy from `vm-internal` works.

## Task 3 — Configure a Cloud NAT gateway

### The Cloud Router and the NAT gateway

```bash
gcloud compute routers create nat-router \
    --network=privatenet --region=REGION

gcloud compute routers nats create nat-config \
    --router=nat-router --region=REGION \
    --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges
```

Wait for the gateway's status to become **Running**.

Click **Check my progress** — *Configure a Cloud NAT gateway*.

### Verify

```bash
gcloud compute ssh vm-internal --zone=ZONE --tunnel-through-iap
```

Inside the VM:

```bash
sudo apt-get update
```

This now completes. Before the NAT gateway it only reached Google's own
package mirrors, because that is all Private Google Access covers.

> The NAT config can take **up to 3 minutes** to propagate to the VM. If
> `apt-get update` still fails, wait a minute and try again.

## Task 4 — Configure and view logs with Cloud NAT Logging

```bash
gcloud compute routers nats update nat-config \
    --router=nat-router --region=REGION --enable-logging
```

Then connect to the VM again and run `sudo apt-get update` — that generates
log entries. Look for them in **Logging → Logs Explorer**:

```
resource.type="compute_router_nat" AND resource.labels.router_name="nat-router"
```

## Clean up

```bash
gcloud compute instances delete vm-internal --zone=ZONE --quiet
gcloud compute routers nats delete nat-config --router=nat-router --region=REGION --quiet
gcloud compute routers delete nat-router --region=REGION --quiet
gcloud compute networks delete privatenet --quiet
gclou