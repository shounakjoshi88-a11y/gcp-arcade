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
| `ZONE 3` | zone in REGION 1, **not** ZONE 1 | `on-prem-instance1` |

If the lab started your shell with `ZONE`, `ZONE_1` and `ZONE_2` (or `Z1`,
`Z2`, `Z3`) in the environment, they are already the three zones above.

> **Not every zone is available in a lab project.** A zone that cannot be
> fetched comes back as
> `Permission denied on 'locations/<zone>' (or it may not exist)`, and the
> instance create fails with the same message. Check what the project
> allows with:
>
> ```bash
> gcloud compute zones describe us-central1-b
> ```
>
> The on-premises VM needs a zone in REGION 1 that is **not** the zone of
> `vpc-demo-instance1` — the lab leaves that one to you.

---

## Task 1 — Set up a Global VPC environment

### The network and the two subnets

```bash
gcloud compute networks create vpc-demo --subnet-mode custom

gcloud compute networks subnets create vpc-demo-subnet1 \
    --network vpc-demo --range 10.1.1.0/24 --region "REGION 1"

gcloud compute networks subnets create vpc-demo-subnet2 \
    --network vpc-demo --range 10.2.1.0/24 --region "REGION 2"
```

> **Custom mode, not auto mode.** The network spans two regions, so it has to
> be a custom mode global network. The console's "Automatic" would give you
> one subnet per region with the wrong ranges.
>
> The create output shows `BGP_ROUTING_MODE: REGIONAL` — task 6 changes it.

### The firewall rules

```bash
gcloud compute firewall-rules create vpc-demo-allow-custom \
    --network vpc-demo \
    --allow tcp:0-65535,udp:0-65535,icmp \
    --source-ranges 10.0.0.0/8

gcloud compute firewall-rules create vpc-demo-allow-ssh-icmp \
    --network vpc-demo --allow tcp:22,icmp
```

### The two instances — one per region

```bash
gcloud compute instances create vpc-demo-instance1 \
    --machine-type=e2-medium --zone "ZONE 1" --subnet vpc-demo-subnet1

gcloud compute instances create vpc-demo-instance2 \
    --machine-type=e2-medium --zone "ZONE 2" --subnet vpc-demo-subnet2
```

`--subnet` is enough: the network comes from the subnet, and the instance
gets an external IP, which is what the SSH ping in task 6 needs.

---

## Task 2 — Set up a simulated on-premises environment

`on-prem` plays the customer's data centre. It is an ordinary second VPC.

```bash
gcloud compute networks create on-prem --subnet-mode custom

gcloud compute networks subnets create on-prem-subnet1 \
    --network on-prem --range 192.168.1.0/24 --region "REGION 1"

gcloud compute firewall-rules create on-prem-allow-custom \
    --network on-prem \
    --allow tcp:0-65535,udp:0-65535,icmp \
    --source-ranges 192.168.0.0/16

gcloud compute firewall-rules create on-prem-allow-ssh-icmp \
    --network on-prem --allow tcp:22,icmp

gcloud compute instances create on-prem-instance1 \
    --machine-type=e2-medium --zone "ZONE 3" --subnet on-prem-subnet1
```

> **ZONE 3 has to be a different zone from ZONE 1**, and in the same region.
> The lab says so explicitly, and a shared zone is not rejected by the API —
> it just makes the two VMs land on the same host.

Click **Check my progress** — *Create two VPC networks and instances*.

---

## Task 3 — Set up an HA VPN gateway

```bash
gcloud compute vpn-gateways create vpc-demo-vpn-gw1 \
    --network vpc-demo --region "REGION 1"

gcloud compute vpn-gateways create on-prem-vpn-gw1 \
    --network on-prem --region "REGION 1"

gcloud compute vpn-gateways describe vpc-demo-vpn-gw1 --region "REGION 1"
gcloud compute vpn-gateways describe on-prem-vpn-gw1 --region "REGION 1"
```

> **Both gateways go in the same region.** HA VPN is a regional product: a
> tunnel can only connect two gateways that are in the same region. That
> region is REGION 1, the region of the on-prem network.
>
> The create call returns before the interfaces exist. The `describe` output
> has to show `vpnInterfaces` with `id: 0` and `id: 1` — the tunnel create
> in task 4 fails without them.

### The Cloud Routers

HA VPN needs **dynamic routing** (BGP), and BGP needs a Cloud Router on each
side.

```bash
gcloud compute routers create vpc-demo-router1 \
    --region "REGION 1" --network vpc-demo --asn 65001

gcloud compute routers create on-prem-router1 \
    --region "REGION 1" --network on-prem --asn 65002
```

The two ASNs have to be different — that is how the two sides recognise each
other.

Click **Check my progress** — *Configure HA VPN gateways*.

---

## Task 4 — Create two VPN tunnels

Two tunnels from each gateway, so that the pair gives the 99.99% SLA.

```bash
gcloud compute vpn-tunnels create vpc-demo-tunnel0 \
    --peer-gcp-gateway on-prem-vpn-gw1 \
    --region "REGION 1" \
    --ike-version 2 \
    --shared-secret "YOUR_SHARED_SECRET" \
    --router vpc-demo-router1 \
    --vpn-gateway vpc-demo-vpn-gw1 \
    --interface 0

gcloud compute vpn-tunnels create vpc-demo-tunnel1 \
    --peer-gcp-gateway on-prem-vpn-gw1 \
    --region "REGION 1" \
    --ike-version 2 \
    --shared-secret "YOUR_SHARED_SECRET" \
    --router vpc-demo-router1 \
    --vpn-gateway vpc-demo-vpn-gw1 \
    --interface 1

gcloud compute vpn-tunnels create on-prem-tunnel0 \
    --peer-gcp-gateway vpc-demo-vpn-gw1 \
    --region "REGION 1" \
    --ike-version 2 \
    --shared-secret "YOUR_SHARED_SECRET" \
    --router on-prem-router1 \
    --vpn-gateway on-prem-vpn-gw1 \
    --interface 0

gcloud compute vpn-tunnels create on-prem-tunnel1 \
    --peer-gcp-gateway vpc-demo-vpn-gw1 \
    --region "REGION 1" \
    --ike-version 2 \
    --shared-secret "YOUR_SHARED_SECRET" \
    --router on-prem-router1 \
    --vpn-gateway on-prem-vpn-gw1 \
    --interface 1
```

> **The interfaces have to match.** `vpc-demo-tunnel0` uses interface 0 and
> points at `on-prem-vpn-gw1`; on the other side `on-prem-tunnel0` also uses
> interface 0. A crossed pair — interface 0 to interface 1 — still creates
> fine and still shows as ESTABLISHED, but it is not the topology the lab
> asks for and the SLA does not hold.
>
> **All four tunnels need the same shared secret.** The secret is between
> the two ends of one tunnel, and both ends of a tunnel are here.

Click **Check my progress** — *Configure dynamic routing with VPN tunnels*.

---

## Task 5 — Create BGP peering for each tunnel

Each tunnel needs a router interface and a BGP peer. The addresses come in
pairs: the vpc-demo side takes the `.1` of each /30, the on-prem side the
`.2`.

```bash
# vpc-demo side
gcloud compute routers add-interface vpc-demo-router1 \
    --interface-name if-tunnel0-to-on-prem \
    --ip-address 169.254.0.1 --mask-length 30 \
    --vpn-tunnel vpc-demo-tunnel0 --region "REGION 1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
    --peer-name bgp-on-prem-tunnel0 \
    --interface if-tunnel0-to-on-prem \
    --peer-ip-address 169.254.0.2 --peer-asn 65002 \
    --region "REGION 1"

gcloud compute routers add-interface vpc-demo-router1 \
    --interface-name if-tunnel1-to-on-prem \
    --ip-address 169.254.1.1 --mask-length 30 \
    --vpn-tunnel vpc-demo-tunnel1 --region "REGION 1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
    --peer-name bgp-on-prem-tunnel1 \
    --interface if-tunnel1-to-on-prem \
    --peer-ip-address 169.254.1.2 --peer-asn 65002 \
    --region "REGION 1"

# on-prem side
gcloud compute routers add-interface on-prem-router1 \
    --interface-name if-tunnel0-to-vpc-demo \
    --ip-address 169.254.0.2 --mask-length 30 \
    --vpn-tunnel on-prem-tunnel0 --region "REGION 1"

gcloud compute routers add-bgp-peer on-prem-router1 \
    --peer-name bgp-vpc-demo-tunnel0 \
    --interface if-tunnel0-to-vpc-demo \
    --peer-ip-address 169.254.0.1 --peer-asn 65001 \
    --region "REGION 1"

gcloud compute routers add-interface on-prem-router1 \
    --interface-name if-tunnel1-to-vpc-demo \
    --ip-address 169.254.1.2 --mask-length 30 \
    --vpn-tunnel on-prem-tunnel1 --region "REGION 1"

gcloud compute routers add-bgp-peer on-prem-router1 \
    --peer-name bgp-vpc-demo-tunnel1 \
    --interface if-tunnel1-to-vpc-demo \
    --peer-ip-address 169.254.1.1 --peer-asn 65001 \
    --region "REGION 1"
```

> The peer address is the **other** end of the /30, and the peer ASN is the
> ASN of the router on the other side. Getting either backwards leaves the
> session down.

Check it:

```bash
gcloud compute routers describe vpc-demo-router1 --region "REGION 1"
```

---

## Task 6 — Verify the router configurations and enable global routing

### The firewall rules between the two VPCs

The rules from tasks 1 and 2 only allow traffic *inside* each VPC. The two
VPCs need to be opened to each other.

```bash
gcloud compute firewall-rules create vpc-demo-allow-subnets-from-on-prem \
    --network vpc-demo \
    --allow tcp,udp,icmp \
    --source-ranges 192.168.1.0/24

gcloud compute firewall-rules create on-prem-allow-subnets-from-vpc-demo \
    --network on-prem \
    --allow tcp,udp,icmp \
    --source-ranges 10.1.1.0/24,10.2.1.0/24
```

### The tunnel status

```bash
gcloud compute vpn-tunnels list
```

Four tunnels, all `ESTABLISHED`:

```bash
gcloud compute vpn-tunnels describe vpc-demo-tunnel0 --region "REGION 1"
```

`detailedStatus` should read `Tunnel is up and running.`

### The private connectivity

```bash
gcloud compute ssh on-prem-instance1 --zone "ZONE 3"
```

Inside the VM:

```bash
ping -c 4 10.1.1.2
```

`10.1.1.2` is `vpc-demo-instance1`.

### Global routing

HA VPN is a regional resource, and a Cloud Router only sees the routes in
the region it is deployed in. To reach the instance in the other region, the
VPC needs global dynamic routing:

```bash
gcloud compute networks update vpc-demo --bgp-routing-mode GLOBAL
```

```bash
gcloud compute networks describe vpc-demo
```

The output has to show `routingMode: GLOBAL`.

Back in the SSH session, the instance in the other region answers now:

```bash
ping -c 2 10.2.1.2
```

`10.2.1.2` is `vpc-demo-instance2`.

Click **Check my progress** — *Configure global dynamic routing mode*.

---

## Task 7 — Verify and test the configuration of HA VPN tunnels

This is the task that proves the high availability. Bring tunnel 0 of the
vpc-demo network down:

```bash
gcloud compute vpn-tunnels delete vpc-demo-tunnel0 --region "REGION 1"
```

The peer tunnel goes down with it:

```bash
gcloud compute vpn-tunnels describe on-prem-tunnel0 --region "REGION 1"
```

`detailedStatus` shows `Handshake with peer broken for unknown reason. Trying
again soon.` and the status drops to `FIRST_HANDSHAKE`.

In the SSH session that is still open, the traffic keeps flowing — it has
moved to the second tunnel:

```bash
ping -c 3 10.1.1.2
```

> **This task deletes a tunnel on purpose.** If the lab's progress panel
> still wants all four tunnels, skip it — but the lab's own text does it,
> and the HA test is the point of the task.

Click **Check my progress** — *Verify and test HA VPN gateway configuration*.

---

## Task 8 — (Optional) clean up

```bash
gcloud compute vpn-tunnels delete on-prem-tunnel0 --region "REGION 1"
gcloud compute vpn-tunnels delete vpc-demo-tunnel1 --region "REGION 1"
gcloud compute vpn-tunnels delete on-prem-tunnel1 --region "REGION 1"

gcloud compute routers remove-bgp-peer vpc-demo-router1 --peer-name bgp-on-prem-tunnel0 --region "REGION 1"
gcloud compute routers remove-bgp-peer vpc-demo-router1 --peer-name bgp-on-prem-tunnel1 --region "REGION 1"
gcloud compute routers remove-bgp-peer on-prem-router1 --peer-name bgp-vpc-demo-tunnel0 --region "REGION 1"
gcloud compute routers remove-bgp-peer on-prem-router1 --peer-name bgp-vpc-demo-tunnel1 --region "REGION 1"

gcloud compute routers delete on-prem-router1 --region "REGION 1"
gcloud compute routers delete vpc-demo-router1 --region "REGION 1"

gcloud compute vpn-gateways delete vpc-demo-vpn-gw1 --region "REGION 1"
gcloud compute vpn-gateways delete on-prem-vpn-gw1 --region "REGION 1"

gcloud compute instances delete vpc-demo-instance1 --zone "ZONE 1"
gcloud compute instances delete vpc-demo-instance2 --zone "ZONE 2"
gcloud compute instances delete on-prem-instance1 --zone "ZONE 3"

gcloud compute firewall-rules delete vpc-demo-allow-custom
gcloud compute firewall-rules delete vpc-demo-allow-ssh-icmp
gcloud compute firewall-rules delete vpc-demo-allow-subnets-from-on-prem
gcloud compute firewall-rules delete on-prem-allow-custom
gcloud compute firewall-rules delete on-prem-allow-ssh-icmp
gcloud compute firewall-rules delete on-prem-allow-subnets-from-vpc-demo

gcloud compute networks subnets delete vpc-demo-subnet1 --region "REGION 1"
gcloud compute networks subnets delete vpc-demo-subnet2 --region "REGION 2"
gcloud compute networks subnets delete on-prem-subnet1 --region "REGION 1"

gcloud compute networks delete vpc-demo
gcloud compute networks delete on-prem
```
