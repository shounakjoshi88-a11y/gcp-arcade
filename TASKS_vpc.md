# Get Started with Virtual Private Cloud Networking and Compute Engine — task by task

Manual equivalent of `gsp_vpc.sh`. Assumes Cloud Shell with the lab project
active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The lab assigns **two regions** per run. Take them from the setup panel:

| Placeholder | Used for |
|---|---|
| Region 1 | `mynet-us-vm` |
| Region 2 | `mynet-r2-vm` |

The lab has **one** checkpoint: *Create a VPC network and VM instance*.

---

## Task 1 — Explore the default network

Delete the four default firewall rules, then the default network:

```bash
gcloud compute firewall-rules delete default-allow-icmp \
    default-allow-internal default-allow-rdp default-allow-ssh --quiet

gcloud compute networks delete default --quiet
```

The rules are separate resources — deleting the network does **not** delete
them, so remove them first.

## Task 2 — Create a VPC network and VM instances

```bash
gcloud compute networks create mynetwork --subnet-mode=auto
```

### The four standard firewall rules

Ticking *all available rules* in the console creates these four. The CLI does
**not** create them, so make them explicitly:

```bash
gcloud compute firewall-rules create mynetwork-allow-custom \
    --network=mynetwork --direction=INGRESS --priority=1000 \
    --action=ALLOW --allow=tcp,udp,icmp --source-ranges=10.128.0.0/9

gcloud compute firewall-rules create mynetwork-allow-icmp \
    --network=mynetwork --direction=INGRESS --priority=1000 \
    --action=ALLOW --allow=icmp --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create mynetwork-allow-rdp \
    --network=mynetwork --direction=INGRESS --priority=1000 \
    --action=ALLOW --allow=tcp:3389 --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create mynetwork-allow-ssh \
    --network=mynetwork --direction=INGRESS --priority=1000 \
    --action=ALLOW --allow=tcp:22 --source-ranges=0.0.0.0/0
```

> The internal rule is called `allow-custom` on an auto mode network. It was
> `default-allow-internal` on the default network.

### The two VM instances

```bash
gcloud compute instances create mynet-us-vm \
    --zone=REGION_1-a \
    --machine-type=e2-micro \
    --network-interface=network=mynetwork,subnet=mynetwork \
    --image-family=debian-12 --image-project=debian-cloud

gcloud compute instances create mynet-r2-vm \
    --zone=REGION_2-b \
    --machine-type=e2-micro \
    --network-interface=network=mynetwork,subnet=mynetwork \
    --image-family=debian-12 --image-project=debian-cloud
```

> **The subnet is named `mynetwork`, not `default`.** In an auto mode network
> the subnet takes the name of the **network**, and one is created in every
> region — so the same subnet name works in both zones.

Click **Check my progress** — *Create a VPC network and VM instance*.

## Task 3 — Explore the connectivity for VM instances

```bash
gcloud compute instances list --sort-by=ZONE
```

Note the internal and external IPs, then SSH into the first instance:

```bash
gcloud compute ssh mynet-us-vm --zone=REGION_1-a
```

From inside it:

| Test | Allowed by |
|---|---|
| `ping -c 3 <mynet-r2-vm internal IP>` | `mynetwork-allow-custom` |
| `ping -c 3 <mynet-r2-vm external IP>` | `mynetwork-allow-icmp` |
| SSH in | `mynetwork-allow-ssh` |

Now remove the rules **one at a time** and watch what breaks:

```bash
# the external ping stops working
gcloud compute firewall-rules delete mynetwork-allow-icmp --quiet

# the internal ping stops working too
gcloud compute firewall-rules delete mynetwork-allow-custom --quiet

# SSH stops working
gcloud compute firewall-rules delete mynetwork-allow-ssh --quiet
```

`mynetwork-allow-rdp` is left in place.

## Clean up

```bash
gcloud compute instances delete mynet-us-vm --zone=REGION_1-a --quiet
gcloud compute instances delete mynet-r2-vm --zone=REGION_2-b --quiet
gcloud compute networks delete mynetwor