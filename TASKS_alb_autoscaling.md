# Configure an Application Load Balancer with Autoscaling — task by task

Manual equivalent of `gsp_alb_autoscaling.sh`. Assumes Cloud Shell with
the lab project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

**The two regions and the zones change with every lab run** — the same lab
was `us-east4` / `us-east4-c` once and `us-central1` / `us-central1-a` the
next. Take them from the lab instructions, and from the project default:

```bash
gcloud config get-value compute/region
gcloud config get-value compute/zone
```

| Name | What it is | Where it goes |
|---|---|---|
| `REGION 1` | the lab's first region | the Cloud NAT, the `webserver` VM, the `us-1-mig` group |
| `ZONE 1` | a zone in REGION 1 | the `webserver` VM |
| `REGION 2` | a different region | the `notus-1-mig` group |
| `STRESS ZONE` | a zone in a **US** region other than REGION 1 | the `stress-test` VM |

> The stress test VM has to go in a region that is **different but closer
> to REGION 1** than to REGION 2. That is the whole point of task 6: the
> load balancer forwards the traffic to the closer backend, so `us-1-mig`
> gets it first and `notus-1-mig` only joins in once the load is high.

---

## Task 1 — Configure a health check firewall rule

The health checkers, and the load balancer itself, reach the backends from
two fixed ranges.

```bash
gcloud compute firewall-rules create fw-allow-health-checks \
    --network=default \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-checks
```

> The rule only applies to the instances that carry the `allow-health-checks`
> network tag — that tag is what the instance template sets later.

Click **Check my progress** — *Create a health check firewall rule*.

---

## Task 2 — Create a NAT configuration using Cloud Router

The web server VM of task 3 has **no external IP**, so it needs a Cloud NAT
to reach the package mirrors.

```bash
gcloud compute routers create nat-router-us1 \
    --network=default \
    --region="REGION 1"

gcloud compute routers nats create nat-config \
    --router=nat-router-us1 \
    --region="REGION 1" \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips
```

Wait for the NAT to be `RUNNING`:

```bash
gcloud compute routers nats describe nat-config \
    --router=nat-router-us1 --region="REGION 1" --format="value(status)"
```

Click **Check my progress** — *Create a NAT configuration using Cloud Router*.

---

## Task 3 — Create a custom image for a web server

Create a VM with no external IP and install Apache on it through a startup
script, then turn its boot disk into an image.

```bash
gcloud compute instances create webserver \
    --zone="ZONE 1" \
    --machine-type=e2-micro \
    --network-interface=network=default,no-address \
    --tags=allow-health-checks \
    --metadata=startup-script='#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2
echo "STARTUP-SCRIPT-DONE"' \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --boot-disk-device-name=webserver
```

Watch the script finish on the serial console:

```bash
gcloud compute instances get-serial-port-output webserver --zone="ZONE 1" \
    | grep STARTUP-SCRIPT-DONE
```

Stop the VM and turn the disk into an image:

```bash
gcloud compute instances stop webserver --zone="ZONE 1"

gcloud compute images create mywebserver \
    --source-disk=webserver \
    --source-disk-zone="ZONE 1" \
    --family=webserver-family
```

Delete the VM — the image takes its place:

```bash
gcloud compute instances delete webserver --zone="ZONE 1" --keep-disks=boot
```

> The image is what the instance template of task 4 is built from, and it
> already has Apache installed **and enabled**, so the instances of the
> group serve HTTP the moment they boot.

Click **Check my progress** — *Create a custom image for a web server*.

---

## Task 4 — Configure an instance template and create instance groups

### The health check

```bash
gcloud compute health-checks create http http-health-check \
    --port=80
```

> **HTTP, not TCP.** The lab's health check is HTTP on port 80, and it is the
> *legacy* health check — the one without a region, which is what the
> autohealing of a regional instance group accepts. A health check created
> with `--global` is the newer kind, and the autohealing rejects it with
> *"the health check must be a legacy health check"*.

### The instance template

```bash
gcloud compute instance-templates create mywebserver-template \
    --machine-type=e2-micro \
    --network-interface=network=default,no-address \
    --tags=allow-health-checks \
    --image=mywebserver \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --boot-disk-device-name=mywebserver-template
```

> **No subnet in the template.** A template is a global resource and both
> instance groups use it — one in each region — so the VM has to pick up the
> default subnet of its own region. Pinning a subnet here breaks the second
> group.

### The two managed instance groups

```bash
gcloud compute instance-groups managed create us-1-mig \
    --template=mywebserver-template \
    --region="REGION 1" \
    --size=1 \
    --base-instance-name=us-1-mig \
    --health-check=http-health-check \
    --initial-delay=60

gcloud compute instance-groups managed set-autoscaling us-1-mig \
    --region="REGION 1" \
    --min-num-replicas=1 \
    --max-num-replicas=2 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60

gcloud compute instance-groups managed set-autohealing us-1-mig \
    --region="REGION 1" \
    --health-check=http-health-check \
    --initial-delay=60

gcloud compute instance-groups managed set-named-ports us-1-mig \
    --region="REGION 1" \
    --named-ports=http:80
```

Then the same four commands for the second region, with `notus-1-mig` and
`REGION 2`:

```bash
gcloud compute instance-groups managed create notus-1-mig \
    --template=mywebserver-template \
    --region="REGION 2" \
    --size=1 \
    --base-instance-name=notus-1-mig \
    --health-check=http-health-check \
    --initial-delay=60

gcloud compute instance-groups managed set-autoscaling notus-1-mig \
    --region="REGION 2" \
    --min-num-replicas=1 \
    --max-num-replicas=2 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60

gcloud compute instance-groups managed set-autohealing notus-1-mig \
    --region="REGION 2" \
    --health-check=http-health-check \
    --initial-delay=60

gcloud compute instance-groups managed set-named-ports notus-1-mig \
    --region="REGION 2" \
    --named-ports=http:80
```

> The named port matters: the backend service of task 5 refers to the port
> by the name `http`, and a group without that named port has no healthy
> backend.

Click **Check my progress** — *Configure an instance template and create
instance groups*.

---

## Task 5 — Configure the Application Load Balancer (HTTP)

### The backend service and its two backends

```bash
gcloud compute backend-services create http-backend \
    --global \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-health-check \
    --global-health-checks \
    --enable-logging \
    --logging-sample-rate=1.0

gcloud compute backend-services add-backend http-backend \
    --instance-group=us-1-mig \
    --instance-group-region="REGION 1" \
    --balancing-mode=RATE \
    --max-rate-per-instance=50 \
    --capacity-scaler=1.0 \
    --global

gcloud compute backend-services add-backend http-backend \
    --instance-group=notus-1-mig \
    --instance-group-region="REGION 2" \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --capacity-scaler=1.0 \
    --global
```

The two groups get **different balancing modes on purpose**: the first one
is rate based (50 RPS per instance), the second one is utilization based
(80% CPU).

### The frontend

```bash
gcloud compute url-maps create http-lb \
    --default-service=http-backend

gcloud compute target-http-proxies create http-lb-proxy \
    --url-map=http-lb

gcloud compute forwarding-rules create http-lb-ipv4 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80 \
    --ip-version=IPV4

gcloud compute forwarding-rules create http-lb-ipv6 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80 \
    --ip-version=IPV6
```

> **Two forwarding rules.** The lab asks for IPv4 *and* IPv6. Both point at
> the same target proxy, and the IPv6 one gets its own address.

Get the address and try it:

```bash
gcloud compute forwarding-rules describe http-lb-ipv4 --global \
    --format="value(IPAddress)"
```

It can take a few minutes before it answers:

```bash
curl http://<the IP address>
```

Click **Check my progress** — *Configure an Application Load Balancer (HTTP)
with IPv4 and IPv6*.

---

## Task 6 — Stress test an Application Load Balancer (HTTP)

### Knowledge check

> **The Application Load Balancer (HTTP) should forward traffic to the
> region that is closest to you.**
>
> **Answer: True.**

The load balancer sends the traffic to the closest backend that has spare
capacity. The stress test VM sits in a US region, so it is much closer to
`us-east4` than to `asia-south1` — `us-1-mig` gets the traffic first, and
`notus-1-mig` only joins in once the load is high enough that the first
backend cannot keep up.

### Access the Application Load Balancer (HTTP)

Wait for the load balancer to answer:

```bash
LB_IP=[LB_IP_v4]
while [ -z "$RESULT" ] ;
do
  echo "Waiting for Load Balancer";
  sleep 5;
  RESULT=$(curl -m1 -s $LB_IP | grep Apache);
done
```

Then open `http://[LB_IP_v4]` in a browser.

### Stress test the Application Load Balancer (HTTP)

Create a VM in a US region other than `us-east4` — it needs a public address
to reach the public load balancer:

```bash
gcloud compute instances create stress-test \
    --zone="STRESS ZONE" \
    --machine-type=e2-micro \
    --network-interface=network=default \
    --image=mywebserver \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --boot-disk-device-name=stress-test
```

Install ApacheBench and hit the load balancer:

```bash
gcloud compute ssh stress-test --zone="STRESS ZONE" --command="
    sudo apt-get update -y
    sudo apt-get install -y apache2-utils
    ab -n 500000 -c 1000 http://<the IP address>/
"
```

While that runs, watch the instance groups scale up:

```bash
gcloud compute instance-groups managed describe us-1-mig \
    --region="REGION 1" --format="table(name,targetSize,status.isStable)"
```

- Load balancing → `http-lb` → **Monitoring** for the traffic
- Compute Engine → Instance groups → `us-1-mig` → **Monitoring** for the
  number of instances

Click **Check my progress** — *Stress test an Application Load Balancer
(HTTP)*.

---

## Clean up

```bash
gcloud compute instances delete stress-test --zone="STRESS ZONE" --quiet
gcloud compute forwarding-rules delete http-lb-ipv4 http-lb-ipv6 --global --quiet
gcloud compute target-http-proxies delete http-lb-proxy --quiet
gcloud compute url-maps delete http-lb --quiet
gcloud compute backend-services delete http-backend --global --quiet
gcloud compute instance-groups managed delete us-1-mig --region="REGION 1" --quiet
gcloud compute instance-groups managed delete notus-1-mig --region="REGION 2" --quiet
gcloud compute instance-templates delete mywebserver-template --quiet
gcloud compute health-checks delete http-health-check --quiet
gcloud compute images delete mywebserver --quiet
gcloud compute disks delete webserver --zone="ZONE 1" --quiet
gcloud compute routers nats delete nat-config --router=nat-router-us1 --region="REGION 1" --quiet
gcloud compute routers delete nat-router-us1 --region="REGION 1" --quiet
gcloud compute firewall-rules delete fw-allow-health-checks --quiet
```
