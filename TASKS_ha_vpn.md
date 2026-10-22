# Configure Google Cloud HA VPN — task by task

Manual equivalent of `gsp_ha_vpn.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

**The two regions and the three zones are lab-assigned per run** — they are
on the lab setup panel. In the commands below:

| Name | What it is | Where it goes |
|---|---|---|
| `REGION 1` | first region of the lab | `vpc-demo-subnet1`, `on-prem-subnet1`, both gateways, both routers, all four tunnels |
| `REGION 2` | second region of the lab | `vpc-demo-subnet2` only |
| `ZONE 1` | zone in REGION 1 | `vpc-demo-instance1` |
| `ZONE 2` | zone in REGION 2 | `vpc-demo-instance2` |
| `ZONE 3` | zone in REGION 1 | `on-prem-instance1` |

If the lab started your shell with `ZONE`, `ZONE_1` and `ZONE_2` in the
environment, they are already the three zones above.

---

## Task 1 — The vpc-demo VPC network, its subnets and its VMs

### The network and the two subnets

```bash
gcloud compute networks create vpc-demo --subnet-mode=custom

gcloud compute networks subnets create vpc-demo-subnet1 \
    --network=vpc-demo --range=10.1.1.0/24 --region="REGION 1"

gcloud compute networks subnets create vpc-demo-subnet2 \
    --network=vpc-demo --range=10.2.1.0/24 --region="REGION 2"
```

> **Custom mode, not auto mode.** The network spans two regions, so it has to
> be a custom mode global network — the console's "Automatic" would only give
> you one subnet per region with the wrong ranges.

### The firewall rules

```bash
gcloud compute firewall-rules create vpc-demo-allow-custom \
    --network=vpc-demo --allow=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=10.0.0.0/8

gcloud compute firewall-rules create vpc-demo-allow-ssh-icmp \
    --network=vpc-demo --allow=tcp:22,icmp
```

### The two instances — one per region

```bash
gcloud compute instances create vpc-demo-instance1 \
    --machine-type=e2-medium --zone="ZONE 1" \
    --network-interface=network=vpc-demo,subnet=vpc-demo-subnet1

gcloud compute instances create vpc-demo-instance2 \
    --machine-type=e2-medium --zone="ZONE 2" \
    --network-interface=network=vpc-demo,subnet=vpc-demo-subnet2
```

Click **Check my progress** — *Create the vpc-demo VPC network and the VM
instances*.

---

## Task 2 — The on-prem VPC network, its subnet and its VM

`on-prem` plays the customer's data centre. It is an ordinary second VPC.

```bash
gcloud compute networks create on-prem --subnet-mode=custom

gcloud compute networks subnets create on-prem-subnet1 \
    --network=on-prem --range=192.168.1.0/24 --region="REGION 1"

gcloud compute firewall-rules create on-prem-allow-custom \
    --network=on-prem --allow=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=192.168.0.0/16

gcloud compute firewall-rules create on-prem-allow-ssh-icmp \
    --network=on-prem --allow=tcp:22,icmp

gcloud compute instances create on-prem-instance1 \
    --machine-type=e2-medium --zone="ZONE 3" \
    --network-interface=network=on-prem,subnet=on-prem-subnet1
```

Click **Check my progress** — *Create the on-prem VPC network and the VM
instance*.

---

## Task 3 — The HA VPN gateways

```bash
gcloud compute vpn-gateways create vpc-demo-vpn-gw1 \
    --network=vpc-demo --region="REGION 1"

gcloud compute vpn-gateways create on-prem-vpn-gw1 \
    --network=on-prem --region="REGION 1"

gcloud compute vpn-gateways describe vpc-demo-vpn-gw1 --region="REGION 1"
gcloud compute vpn-gateways describe on-prem-vpn-gw1 --region="REGION 1"
```

> **Both gateways go in the same region.** HA VPN is a regional product: a
> tunnel can only connect two gateways that are in the same region. That
> region is REGION 1, the region of the on-prem network.

Each gateway gets two interfaces, each with its own public IP. Check the
`describe` output for `gatewayInterfaces` — the create call returns before
the interfaces exist, and the tunnel create in task 5 fails without them.

Click **Check my progress** — *Create the HA VPN gateways*.

---

## Task 4 — The Cloud Routers

HA VPN needs **dynamic routing** (BGP), and BGP needs a Cloud Router on each
side.

```bash
gcloud compute routers create vpc-demo-router1 \
    --network=vpc-demo --region="REGION 1" --asn=65001

gcloud compute routers create on-prem-router1 \
    --network=on-prem --region="REGION 1" --asn=65002
```

The two ASNs have to be different — that is how the two sides recognise each
other.

Click **Check my progress** — *Create the Cloud Routers*.

---

## Task 5 — The four VPN tunnels

Two tunnels from each gateway, so that the pair gives the 99.99% SLA.

```bash
gcloud compute vpn-tunnels create vpc-demo-tunnel0 \
    --vpn-gateway=vpc-demo-vpn-gw1 --peer-gcp-gateway=on-prem-vpn-gw1 \
    --router=vpc-demo-router1 --interface=0 --region="REGION 1" \
    --ike-version=2 --shared-secret="YOUR_SHARED_SECRET"

gcloud compute vpn-tunnels create vpc-demo-tunnel1 \
    --vpn-gateway=vpc-demo-vpn-gw1 --peer-gcp-gateway=on-prem-vpn-gw1 \
    --router=vpc-demo-router1 --interface=1 --region="REGION 1" \
    --ike-version=2 --shared-secret="YOUR_SHARED_SECRET"

gcloud compute vpn-tunnels create on-prem-tunnel0 \
    --vpn-gateway=on-prem-vpn-gw1 --peer-gcp-gateway=vpc-demo-vpn-gw1 \
    --router=on-prem-router1 --interface=0 --region="REGION 1" \
    --ike-version=2 --shared-secret="YOUR_SHARED_SECRET"

gcloud compute vpn-tunnels create on-prem-tunnel1 \
    --vpn-gateway=on-prem-vpn-gw1 --peer-gcp-gateway=vpc-demo-vpn-gw1 \
    --router=on-prem-router1 --interface=1 --region="REGION 1" \
    --ike-version=2 --shared-secret="YOUR_SHARED_SECRET"
```

> **The interfaces have to match.** `vpc-demo-tunnel0` uses interface 0 and
> points at `on-prem-vpn-gw1`; on the other side `on-prem-tunnel0` also uses
> interface 0. A crossed pair — interface 0 to interface 1 — still creates
> fine and still shows as ESTABLISHED, but it is not the topology the lab
> asks for and the SLA does not hold.
>
> **All four tunnels need the same shared secret.** The secret is between
> the two ends of one tunnel, and both ends of a tunnel are here. The
> script generates one, keeps it in `~/gsp-ha-vpn/shared_secret` and reuses
> it, so a re-run does not break the pair.

Click **Check my progress** — *Create the VPN tunnels*.

---

## Task 6 — The BGP peering for every tunnel

Each tunnel needs a router interface and a BGP peer. The addresses come in
pairs: the vpc-demo side takes the `.1` of each /30, the on-prem side the
`.2`.

```bash
# vpc-demo side
gcloud compute routers add-interface vpc-demo-router1 \
    --interface-name=if-tunnel0-to-on-prem \
    --ip-address=169.254.0.1 --mask-length=30 \
    --vpn-tunnel=vpc-demo-tunnel0 --region="REGION 1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
    --peer-name=bgp-on-prem-tunnel0 --interface=if-tunnel0-to-on-prem \
    --peer-ip-address=169.254.0.2 --peer-asn=65002 --region="REGION 1"

gcloud compute routers add-interface vpc-demo-router1 \
    --interface-name=if-tunnel1-to-on-prem \
    --ip-address=169.254.1.1 --mask-length=30 \
    --vpn-tunnel=vpc-demo-tunnel1 --region="REGION 1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
    --peer-name=bgp-on-prem-tunnel1 --interface=if-tunnel1-to-on-prem \
    --peer-ip-address=169.254.1.2 --peer-asn=65002 --region="REGION 1"

# on-prem side
gcloud compute routers add-interface on-prem-router1 \
    --interface-name=if-tunnel0-to-vpc-demo \
    --ip-address=169.254.0.2 --mask-length=30 \
    --vpn-tunnel=on-prem-tunnel0 --region="REGION 1"

gcloud compute routers add-bgp-peer on-prem-router1 \
    --peer-name=bgp-vpc-demo-tunnel0 --interface=if-tunnel0-to-vpc-demo \
    --peer-ip-address=169.254.0.1 --peer-asn=65001 --region="REGION 1"

gcloud compute routers add-interface on-prem-router1 \
    --interface-name=if-tunnel1-to-vpc-demo \
    --ip-address=169.254.1.2 --mask-length=30 \
    --vpn-tunnel=on-prem-tunnel1 --region="REGION 1"

gcloud compute routers add-bgp-peer on-prem-router1 \
    --peer-name=bgp-vpc-demo-tunnel1 --interface=if-tunnel1-to-vpc-demo \
    --peer-ip-address=169.254.1.1 --peer-asn=65001 --region="REGION 1"
```

> The peer address is the **other** end of the /30, and the peer ASN is the
> ASN of the router on the other side. Getting either backwards leaves the
> session down.

Click **Check my progress** — *Create the BGP peering for each tunnel*.

---

## Task 7 — The firewall rules between the two VPCs

The rules from tasks 1 and 2 only allow traffic *inside* each VPC. The two
VPCs need to be opened to each other.

```bash
gcloud compute firewall-rules create vpc-demo-allow-subnets-from-on-prem \
    --network=vpc-demo --allow=tcp,udp,icmp --source-ranges=192.168.1.0/24

gcloud compute firewall-rules create on-prem-allow-subnets-from-vpc-demo \
    --network=on-prem --allow=tcp,udp,icmp \
    --source-ranges=10.1.1.0/24,10.2.1.0/24
```

Click **Check my progress** — *Allow the traffic between the two VPCs*.

---

## Task 8 — Global dynamic routing

`vpc-demo` has a subnet in a second region. With the default **regional**
dynamic routing, the Cloud Router in REGION 1 only advertises the subnets in
its own region, so `vpc-demo-instance2` is unreachable through the tunnel.

```bash
gcloud compute networks update vpc-demo --bgp-routing-mode=GLOBAL
```

```bash
gcloud compute networks describe vpc-demo --format="value(bgpRoutingMode)"
```

> The lab asks for `vpc-demo`. The script also sets `on-prem` to `GLOBAL`,
> which the lab does not ask for: with regional routing the on-prem router
> would not advertise a subnet that sits in another region, and the ping in
> task 9 would fail.

Click **Check my progress** — *Enable global dynamic routing*.

---

## Task 9 — Verify and test

The tunnels establish on their own, but it takes a minute or two.

```bash
gcloud compute vpn-tunnels list --region="REGION 1"
```

Every tunnel should be `ESTABLISHED`. Then check the BGP sessions:

```bash
gcloud compute routers get-status vpc-demo-router1 --region="REGION 1" \
    --format="value(bgp[0].peers[].state)"
```

Both peers should be `ESTABLISHED`.

Finally, ping across the tunnel from the on-prem VM:

```bash
gcloud compute ssh on-prem-instance1 --zone="ZONE 3" \
    --command="ping -c 4 10.1.1.2"
```

`10.1.1.2` is `vpc-demo-instance1`. The second one, in the other region, is
`10.2.1.2` — `vpc-demo-instance2` — and it only answers once global dynamic
routing is on:

```bash
gcloud compute ssh on-prem-instance1 --zone="ZONE 3" \
    --command="ping -c 4 10.2.1.2"
```

Click **Check my progress** — *Verify and test the HA VPN gateway
configuration*.

---

## Clean up

```bash
gcloud compute vpn-tunnels delete vpc-demo-tunnel0 vpc-demo-tunnel1 --region="REGION 1" --quiet
gcloud compute vpn-tunnels delete on-prem-tunnel0 on-prem-tunnel1 --region="REGION 1" --quiet
gcloud compute routers delete vpc-demo-router1 on-prem-router1 --region="REGION 1" --quiet
gcloud compute vpn-gateways delete vpc-demo-vpn-gw1 on-prem-vpn-gw1 --region="REGION 1" --quiet
gcloud compute instances delete vpc-demo-instance1 --zone="ZONE 1" --quiet
gcloud compute instances delete vpc-demo-instance2 --zone="ZONE 2" --quiet
gcloud compute instances delete on-prem-instance1 --zone="ZONE 3" --quiet
gcloud compute networks delete vpc-demo on-prem --quiet
```
