# Create and Configure VPC Networks — task by task

Manual equivalent of `gsp_vpc_networks.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The lab assigns **two zones** per run. Take them from the setup panel:

| Placeholder | Used for |
|---|---|
| Zone 1 | `mynet-us-vm`, `managementnet-us-vm`, `privatenet-us-vm` |
| Zone 2 | `mynet-notus-vm` |

Region 1 is the region of Zone 1, Region 2 is the region of Zone 2.

The three checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a VPC network and VM instances | 30 |
| 2 | Create custom mode VPC networks with firewall rules | 40 |
| 3 | Create VM instances | 30 |

---

## Task 1 — Explore the default network

Delete the four default firewall rules, then the default network:

```bash
gcloud compute firewall-rules delete default-allow-icmp \
    default-allow-internal default-allow-rdp default-allow-ssh --quiet

gcloud compute networks delete default --quiet
```

The firewall rules are separate resources — deleting the network does **not**
delete them, so remove them first.

## Task 2 — Create an auto mode network

```bash
gcloud services enable \
    iap.googleapis.com \
    networkmanagement.googleapis.com

gcloud compute networks create mynetwork --subnet-mode=auto
```

### The four standard firewall rules

Ticking *all available rules* in the console creates these four. The CLI does
**not** create them for you, so they have to be made explicitly:

```bash
gcloud compute firewall-rules create mynetwork-allow-custom \
    --network=mynetwork --direction=INGRESS --priority=65534 \
    --action=ALLOW --rules=all --source-ranges=10.128.0.0/9

gcloud compute firewall-rules create mynetwork-allow-icmp \
    --network=mynetwork --direction=INGRESS --priority=65534 \
    --action=ALLOW --rules=icmp --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create mynetwork-allow-rdp \
    --network=mynetwork --direction=INGRESS --priority=65534 \
    --action=ALLOW --rules=tcp:3389 --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create mynetwork-allow-ssh \
    --network=mynetwork --direction=INGRESS --priority=65534 \
    --action=ALLOW --rules=tcp:22 --source-ranges=0.0.0.0/0
```

### The IAP rule

```bash
gcloud compute firewall-rules create allow-iap-ssh \
    --network=mynetwork --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=iap-gce
```

### The two VM instances

Both are `e2-medium` and carry the `iap-gce` network tag.

```bash
gcloud compute instances create mynet-us-vm \
    --zone=ZONE_1 \
    --machine-type=e2-medium \
    --network-interface=network=mynetwork,subnet=mynetwork \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --tags=iap-gce

gcloud compute instances create mynet-notus-vm \
    --zone=ZONE_2 \
    --machine-type=e2-medium \
    --network-interface=network=mynetwork,subnet=mynetwork \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --tags=iap-gce
```

> **The subnet is named `mynetwork`, not `default`.** In an auto mode network
> the subnet takes the name of the **network**, and one is created in every
> region — so the same subnet name works in both zones.

### Convert it to a custom mode network

```bash
gcloud compute networks update mynetwork --switch-to-custom-subnet-mode
```

Click **Check my progress** — *Create a VPC network and VM instances*.

## Task 3 — Create custom mode networks

```bash
gcloud compute networks create managementnet --subnet-mode=custom

gcloud compute networks subnets create managementsubnet-us \
    --network=managementnet --region=REGION_1 --range=10.240.0.0/20

gcloud compute networks create privatenet --subnet-mode=custom

gcloud compute networks subnets create privatesubnet-us \
    --network=privatenet --region=REGION_1 --range=172.16.0.0/24

gcloud compute networks subnets create privatesubnet-notus \
    --network=privatenet --region=REGION_2 --range=172.20.0.0/20
```

The firewall rules:

```bash
gcloud compute firewall-rules create managementnet-allow-icmp-ssh-rdp \
    --network=managementnet --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=icmp,tcp:22,tcp:3389 --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create privatenet-allow-icmp-ssh-rdp \
    --network=privatenet --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=icmp,tcp:22,tcp:3389 --source-ranges=0.0.0.0/0
```

Click **Check my progress** — *Create custom mode VPC networks with firewall
rules*.

### The two VM instances

Both are `e2-micro` this time.

```bash
gcloud compute instances create managementnet-us-vm \
    --zone=ZONE_1 \
    --machine-type=e2-micro \
    --network-interface=network=managementnet,subnet=managementsubnet-us \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard

gcloud compute instances create privatenet-us-vm \
    --zone=ZONE_1 \
    --machine-type=e2-micro \
    --network-interface=network=privatenet,subnet=privatesubnet-us \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard
```

Click **Check my progress** — *Create VM instances*.

### The multiple-choice question in task 4

*Which firewall rule allows the ping to `mynet-notus-vm`'s external IP
address?*

| Option | Answer |
|---|---|
| `mynetwork-allow-ssh` | No — tcp:22, not ICMP |
| `mynetwork-allow-rdp` | No — tcp:3389, not ICMP |
| `mynetwork-allow-custom` | No — it allows ICMP, but only from `10.128.0.0/9`, the **internal** range |
| `mynetwork-allow-icmp` | **Yes** — icmp from `0.0.0.0/0`, so it covers the external address too |

`mynetwork-allow-custom` is the trap: it does allow ICMP, but only for traffic
*inside* the network. An external ping arrives from outside `10.128.0.0/9`,
so only `mynetwork-allow-icmp` covers it. The lab puts it as: *"public access
to those instances is only controlled by the ICMP firewall rules that you
established earlier."*

### The second multiple-choice question in task 4

*Which instances should you be able to ping from `mynet-us-vm` using internal
IP addresses?*

| Option | Answer |
|---|---|
| `managementnet-us-vm` | No — it is on the `managementnet` network |
| `privatenet-us-vm` | No — it is on the `privatenet` network |
| `mynet-notus-vm` | **Yes** — it is on the same `mynetwork` as `mynet-us-vm` |

`mynet-us-vm` and `mynet-notus-vm` share a VPC network, so the internal ping
works even though they sit in different zones and regions. The other two are
on separate networks, and VPC networks are isolated private domains — the
lab expects **100% packet loss** there.

## Task 4 — Explore the connectivity across networks

```bash
gcloud compute instances list --sort-by=ZONE

gcloud compute ssh mynet-us-vm --zone=ZONE_1 --tunnel-through-iap
```

From inside `mynet-us-vm`:

| Ping | Result |
|---|---|
| the **external** IP of any instance | works |
| the **internal** IP of `mynet-notus-vm` | works — same VPC network, different region |
| the **internal** IP of `managementnet-us-vm` | 100% packet loss — different VPC network |
| the **internal** IP of `privatenet-us-vm` | 100% packet loss — different VPC network |

VPC networks are isolated private domains. Internal traffic between them needs
VPC peering or a VPN.

## Clean up

```bash
gcloud compute instances delete mynet-us-vm managementnet-us-vm privatenet-us-vm \
    --zone=ZONE_1 --quiet
gcloud compute instances delete mynet-notus-vm --zone=ZONE_2 --quiet
gcloud compute networks delete mynet