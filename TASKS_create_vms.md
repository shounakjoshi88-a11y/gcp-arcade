# Create Virtual Machines — task by task

Manual equivalent of `gsp_create_vms.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The zone is lab-assigned per run — take it from the setup panel. All three VMs
go in it.

The three checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a utility virtual machine | 30 |
| 2 | Create a Windows virtual machine | 30 |
| 3 | Create a custom virtual machine | 40 |

---

## Task 1 — Create a utility virtual machine

```bash
gcloud compute instances create utility-vm \
    --zone=ZONE \
    --machine-type=e2-medium \
    --network-interface=network=default,subnet=default,no-address \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard
```

The lab asks you to *look at* the machine type menu first — it lists the
vCPU count, the memory and the symbolic name (`e2-medium`) that you would
pass to `--machine-type`. Then it has you select `e2-standard-4` to watch the
price change, and finally settle on the shared-core **e2-medium**.

`no-address` is the CLI form of the console's **External IPv4 address: None**.

Click **Check my progress** — *Create a utility virtual machine*.

### The exploration that follows

The lab then has you open the VM's details and look at:

| Thing | Where |
|---|---|
| CPU platform | VM details → the CPU platform field, e.g. *Intel Cascade Lake* |
| Availability policies | VM details → provisioning model, automatic restart, host maintenance |
| Logs | VM details → **Logging** → expand a log entry |

```bash
gcloud compute instances describe utility-vm --zone=ZONE --format="value(cpuPlatform)"
gcloud compute instances describe utility-vm --zone=ZONE --flatten="scheduling" --format="value(scheduling)"
```

## Task 2 — Create a Windows virtual machine

### The firewall rules first

Ticking **Allow HTTP traffic** and **Allow HTTPS traffic** in the console does
two things: it creates the rules *and* it tags the instance.

```bash
gcloud compute firewall-rules create default-allow-http \
    --network=default --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

gcloud compute firewall-rules create default-allow-https \
    --network=default --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 \
    --target-tags=https-server
```

### The VM

```bash
gcloud compute instances create utility-wm \
    --zone=ZONE \
    --machine-type=e2-standard-2 \
    --network-interface=network=default,subnet=default \
    --image-family=windows-2025 --image-project=windows-cloud \
    --boot-disk-size=64 --boot-disk-type=pd-ssd \
    --tags=http-server,https-server
```

> The Windows image **family** changes between releases. If the create fails,
> list what is available:
>
> ```bash
> gcloud compute images list --project windows-cloud \
>     --filter="family:windows-2025" --format="value(family)"
> ```

Click **Check my progress** — *Create a Windows virtual machine*.

### Set the Windows password

There is **no gcloud command** for this — do it in the console:
**Compute Engine → VM instances → utility-wm → Set Windows password → Set**,
then copy the password and click Close.

You do not connect to the Windows VM in this lab; that needs an RDP client.
Note that the connection button on a Windows VM says **RDP**, not SSH.

## Task 3 — Create a custom virtual machine

The console's **Custom** machine type with 2 cores and 4 GB:

```bash
gcloud compute instances create utility-cm \
    --zone=ZONE \
    --custom-cpu=2 --custom-memory=4GB \
    --network-interface=network=default,subnet=default \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard
```

The resulting machine type is `e2-custom-2-4096`.

Click **Check my progress** — *Create a custom virtual machine*.

### Check it over SSH

```bash
gcloud compute ssh utility-cm --zone=ZONE
```

Then, inside the VM:

```bash
free              # memory and swap
sudo dmidecode -t 17   # the installed RAM
nproc             # how many processors
lscpu             # details of the CPUs
exit
```

## Clean up

```bash
gcloud compute instances delete utility-vm utility-wm utility-cm --zone=ZONE --quiet
```
