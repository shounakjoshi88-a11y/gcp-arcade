# Create and Configure Virtual Machines — task by task

Manual equivalent of `gsp_minecraft.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The zone is lab-assigned per run — take it from the setup panel.

The five checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create the VM and prepare the data disk | 20 |
| 2 | Install the Java Runtime Environment (JRE) and the Minecraft server | 20 |
| 3 | Allow client traffic | 20 |
| 4 | Schedule regular backups | 20 |
| 5 | Server maintenance | 20 |

---

## Task 1 — Create the VM

### The static external IP

```bash
gcloud compute addresses create mc-server-ip --region=REGION

ADDRESS=$(gcloud compute addresses describe mc-server-ip --region=REGION \
    --format='value(address)')
```

### The VM

```bash
gcloud compute instances create mc-server \
    --zone=ZONE \
    --machine-type=e2-medium \
    --network-interface="address=$ADDRESS,network-tier=PREMIUM,subnet=default" \
    --scopes="https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.read_write" \
    --tags=minecraft-server \
    --create-disk="auto-delete=yes,boot=yes,device-name=mc-server,image=projects/debian-cloud/global/images/family/debian-12,mode=rw,size=10,type=pd-balanced" \
    --create-disk="device-name=minecraft-disk,mode=rw,name=minecraft-disk,size=50,type=pd-ssd"
```

Three things to notice:

| Lab setting | CLI |
|---|---|
| Network tag `minecraft-server` | `--tags=minecraft-server` |
| **Reserve** a static external IP called `mc-server-ip` | `--network-interface=address=$ADDRESS` |
| Access scopes: *Set access for each API*, Storage **Read Write** | `--scopes=...devstorage.read_write` |

> The storage scope is not optional. The backup script runs
> `gcloud storage cp` **on the VM**, and without `devstorage.read_write` that
> command is denied.

The data disk is named `minecraft-disk` on purpose — the mount point in the
next task is `/dev/disk/by-id/google-minecraft-disk`, and that path comes from
the **disk name**.

> ### Do not switch on OS Login
>
> Some scripts create the VM with `--metadata=enable-oslogin=true`. Do not do
> that here. With OS Login enabled, `gcloud compute ssh` and
> `gcloud compute scp` use the OS Login flow, which needs the
> **`roles/iam.osLogin`** permission — and a lab student account usually does
> not have it. Both commands then fail with a permissions error, even though
> the console's **SSH** button works fine (it uses the classic
> metadata-based key instead).
>
> The classic flow works with any account that has Editor, so the VM is
> created without that metadata item.
>
> If you already created the VM with OS Login on, turn it off and restart it:
>
> ```bash
> gcloud compute instances remove-metadata mc-server --keys=enable-oslogin --zone=ZONE
> gcloud compute instances stop mc-server --zone=ZONE
> gcloud compute instances start mc-server --zone=ZONE
> ```

## Task 2 — Prepare the data disk

```bash
gcloud compute ssh mc-server --zone=ZONE
```

Then, on the VM:

```bash
sudo mkdir -p /home/minecraft

sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard \
    /dev/disk/by-id/google-minecraft-disk

sudo mount -o discard,defaults /dev/disk/by-id/google-minecraft-disk /home/minecraft
```

`mkfs.ext4` and `mount` are destructive if you re-run them on a disk that is
already prepared, so check first:

```bash
blkid /dev/disk/by-id/google-minecraft-disk    # has a filesystem?
mountpoint -q /home/minecraft                   # already mounted?
```

Click **Check my progress** — *Create the VM and prepare the data disk*.

## Task 3 — Install and run the Minecraft server

Still on the VM:

```bash
sudo apt-get update
sudo apt-get install -y default-jre-headless wget screen

cd /home/minecraft

sudo wget https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar

sudo java -Xmx1024M -Xms1024M -jar server.jar nogui
```

That last command stops with *"You need to agree to the EULA"*. Accept it:

```bash
echo "eula=true" | sudo tee eula.txt
```

Start the server in a `screen` session so it survives your SSH session:

```bash
sudo screen -S mcs java -Xmx1024M -Xms1024M -jar server.jar nogui
```

Detach with **Ctrl+A, Ctrl+D**. Reattach later with `sudo screen -r mcs`.

> The server takes a minute or two to finish starting. Watch for
> `Done (…s)!` before you leave it.

Click **Check my progress** — *Install the Java Runtime Environment (JRE) and
the Minecraft server*.

## Task 4 — Allow client traffic

Minecraft uses **TCP 25565**.

```bash
gcloud compute firewall-rules create minecraft-rule \
    --network=default --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:25565 --source-ranges=0.0.0.0/0 \
    --target-tags=minecraft-server
```

Test the server at `https://mcsrvstat.us/server/<your static IP>`.

Click **Check my progress** — *Allow client traffic*.

## Task 5 — Schedule regular backups

### The bucket

```bash
export YOUR_BUCKET_NAME=$PROJECT_ID

gcloud storage buckets create gs://$YOUR_BUCKET_NAME-minecraft-backup
```

### The backup script

On the VM, in `/home/minecraft`:

```bash
sudo nano /home/minecraft/backup.sh
```

```bash
#!/bin/bash
screen -r mcs -X stuff '/save-all\n/save-off\n'
/usr/bin/gcloud storage cp -R ${BASH_SOURCE%/*}/world gs://${YOUR_BUCKET_NAME}-minecraft-backup/$(date "+%Y%m%d-%H%M%S")-world
screen -r mcs -X stuff '/save-on\n'
```

```bash
sudo chmod 755 /home/minecraft/backup.sh
```

Run it once, so the bucket really holds a backup:

```bash
export YOUR_BUCKET_NAME=$PROJECT_ID
cd /home/minecraft
sudo -E ./backup.sh
```

### The cron job

```bash
sudo crontab -e
```

Add this line:

```
0 */4 * * * /home/minecraft/backup.sh
```

> **One addition the lab leaves out:** cron does not read `~/.profile`, so
> `YOUR_BUCKET_NAME` would be empty and the backup would go to a bucket
> called `-minecraft-backup`. Add the variable to the crontab itself:
>
> ```
> YOUR_BUCKET_NAME=your-project-id
> 0 */4 * * * /home/minecraft/backup.sh
> ```
>
> The `YOUR_BUCKET_NAME=...` line is valid crontab syntax and cron applies it
> to the job below it.

Click **Check my progress** — *Schedule regular backups*.

## Task 6 — Server maintenance

Stop the Minecraft server:

```bash
sudo screen -r -X stuff '/stop\n'
```

Then add the startup and shutdown scripts to the metadata:

```bash
gcloud compute instances add-metadata mc-server \
    --metadata="startup-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/startup.sh,shutdown-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/shutdown.sh" \
    --zone=ZONE
```

The two scripts are Google's, not yours:

- `startup.sh` mounts the disk and starts the server in a detached `screen`
- `shutdown.sh` sends `/stop` to the server so it shuts down cleanly

The lab also stops the VM in the console. If you do that, you can start it
again and the startup script will bring the server back:

```bash
gcloud compute instances start mc-server --zone=ZONE
```

Click **Check my progress** — *Server maintenance*.

## Clean up

```bash
gcloud compute instances delete mc-server --zone=ZONE --quiet
gcloud compute disks delete minecraft-disk --zone=ZONE --quiet
gcloud compute addresses delete mc-server-ip --region=REGION --quiet
gcloud compute firewall-rules delete minecraft-rule --quiet
gcloud storage rm -r gs://$