# Configure an Internal Network Load Balancer — task by task

Manual equivalent of `gsp_internal_lb.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

**The network and the subnets are pre-created by the lab.** `my-internal-app`
with `subnet-a` (10.10.20.0/24) and `subnet-b` (10.10.30.0/24), plus the
`app-allow-icmp` and `app-allow-ssh-rdp` firewall rules. The region is the
region of those subnets.

The three zones are lab-assigned per run:

| Name | What it is | Where it goes |
|---|---|---|
| `ZONE 1` | zone in REGION | `instance-group-1` and `instance-template-1` (subnet-a) |
| `ZONE 2` | zone in REGION | `instance-group-2` and `instance-template-2` (subnet-b) |
| `ZONE 3` | zone in REGION | the `utility-vm` |

---

## Task 1 — Configure internal traffic and health check firewall rules

### The HTTP firewall rule

```bash
gcloud compute firewall-rules create app-allow-http \
    --network=my-internal-app \
    --action=ALLOW \
    --direction=INGRESS \
    --rules=tcp:80 \
    --source-ranges=10.10.0.0/16 \
    --target-tags=lb-backend
```

### The health check firewall rule

```bash
gcloud compute firewall-rules create app-allow-health-check \
    --network=my-internal-app \
    --action=ALLOW \
    --direction=INGRESS \
    --rules=tcp \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=lb-backend
```

Click **Check my progress** — *Configure internal traffic and health check
firewall rules*.

---

## Task 2 — Create a NAT configuration using Cloud Router

```bash
gcloud compute routers create nat-router-REGION \
    --network=my-internal-app \
    --region=REGION

gcloud compute routers nats create nat-config \
    --router=nat-router-REGION \
    --region=REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips
```

Wait for the NAT to be `RUNNING`:

```bash
gcloud compute routers nats describe nat-config \
    --router=nat-router-REGION --region=REGION --format="value(status)"
```

Click **Check my progress** — *Create a NAT configuration using Cloud Router*.

---

## Task 3 — Configure two instance templates

### instance-template-1 (subnet-a)

```bash
gcloud compute instance-templates create instance-template-1 \
    --machine-type=e2-micro \
    --network=my-internal-app \
    --subnet=subnet-a \
    --region=REGION \
    --tags=lb-backend \
    --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
    --image-family=debian-12 --image-project=debian-cloud \
    --no-address
```

### instance-template-2 (subnet-b)

```bash
gcloud compute instance-templates create instance-template-2 \
    --machine-type=e2-micro \
    --network=my-internal-app \
    --subnet=subnet-b \
    --region=REGION \
    --tags=lb-backend \
    --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
    --image-family=debian-12 --image-project=debian-cloud \
    --no-address
```

### The utility VM

```bash
gcloud compute instances create utility-vm \
    --machine-type=e2-medium \
    --zone=ZONE3 \
    --network=my-internal-app \
    --subnet=subnet-a \
    --private-network-ip=10.10.20.50 \
    --no-address \
    --image-family=debian-12 --image-project=debian-cloud
```

Verify the backends from the utility VM:

```bash
gcloud compute ssh utility-vm --zone=ZONE3 --tunnel-through-iap
# inside:
curl 10.10.20.2
curl 10.10.30.2
```

Click **Check my progress** — *Configure two instance templates*.

---

## Task 4 — Create two managed instance groups

```bash
gcloud compute instance-groups managed create instance-group-1 \
    --template=instance-template-1 \
    --zone=ZONE1 \
    --size=1 \
    --base-instance-name=instance-group-1 \
    --health-check=my-ilb-health-check \
    --initial-delay=45

gcloud compute instance-groups managed set-autoscaling instance-group-1 \
    --zone=ZONE1 \
    --max-num-replicas=1 \
    --min-num-replicas=1 \
    --target-cpu-utilization=0.8 \
    --cool-down-period=45

gcloud compute instance-groups managed create instance-group-2 \
    --template=instance-template-2 \
    --zone=ZONE2 \
    --size=1 \
    --base-instance-name=instance-group-2 \
    --health-check=my-ilb-health-check \
    --initial-delay=45

gcloud compute instance-groups managed set-autoscaling instance-group-2 \
    --zone=ZONE2 \
    --max-num-replicas=1 \
    --min-num-replicas=1 \
    --target-cpu-utilization=0.8 \
    --cool-down-period=45
```

> The health check is a **regional** one (TCP, port 80), created in task 5
> before the group can use it — the console creates it when you open the
> health check dropdown.

Click **Check my progress** — *Create two managed instance groups*.

---

## Task 5 — Configure and test the internal Network Load Balancer

### The health check

```bash
gcloud compute health-checks create tcp my-ilb-health-check \
    --port=80 \
    --region=REGION
```

### The backend service

```bash
gcloud compute backend-services create my-ilb \
    --load-balancing-scheme=INTERNAL \
    --protocol=TCP \
    --region=REGION \
    --health-checks=my-ilb-health-check \
    --health-checks-region=REGION \
    --enable-logging \
    --logging-sample-rate=1.0

gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-1 \
    --instance-group-zone=ZONE1 \
    --region=REGION

gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-2 \
    --instance-group-zone=ZONE2 \
    --region=REGION
```

### The static address and the forwarding rule

```bash
gcloud compute addresses create my-ilb-ip \
    --region=REGION \
    --subnet=subnet-b \
    --addresses=10.10.30.5

gcloud compute forwarding-rules create my-ilb \
    --load-balancing-scheme=INTERNAL \
    --ports=80 \
    --network=my-internal-app \
    --subnet=subnet-b \
    --region=REGION \
    --backend-service=my-ilb \
    --backend-service-region=REGION \
    --address=my-ilb-ip
```

### Test it

From the utility VM:

```bash
gcloud compute ssh utility-vm --zone=ZONE3 --tunnel-through-iap
```

```bash
curl -s 10.10.30.5
```

Run it several times and the responses should alternate between the two
backends.

Click **Check my progress** — *Configure and test an internal Network Load
Balancer*.

---

## Clean up

```bash
gcloud compute forwarding-rules delete my-ilb --region=REGION --quiet
gcloud compute backend-services delete my-ilb --region=REGION --quiet
gcloud compute health-checks delete my-ilb-health-check --region=REGION --quiet
gcloud compute instance-groups managed delete instance-group-1 --zone=ZONE1 --quiet
gcloud compute instance-groups managed delete instance-group-2 --zone=ZONE2 --quiet
gcloud compute instance-templates delete instance-template-1 instance-template-2 --quiet
gcloud compute instances delete utility-vm --zone=ZONE3 --quiet
gcloud compute addresses delete my-ilb-ip --region=REGION --quiet
gcloud compute routers nats delete nat-config --router=nat-router-REGION --region=REGION --quiet
gcloud compute routers delete nat-router-REGION --region=REGION --quiet
gcloud compute firewall-rules delete app-allow-http app-allow-health-check --quiet
```