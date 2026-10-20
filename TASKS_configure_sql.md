# Configure Cloud SQL — task by task

Manual equivalent of `gsp_configure_sql.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The lab pre-creates the two WordPress VMs, so the zone and region come from
them:

```bash
ZONE=$(gcloud compute instances list --filter="name=wordpress-proxy" --format "get(zone)" | awk -F/ '{print $NF}')
REGION=${ZONE%-*}
```

The two checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a Cloud SQL instance | 50 |
| 2 | Create a database and configure a proxy on a Virtual Machine | 50 |

---

## Task 1 — Enable the Service Networking API

```bash
gcloud services enable servicenetworking.googleapis.com
gcloud services enable servicemanagement.googleapis.com
```

## Task 2 — Create a Cloud SQL database

### Private Services Access

The console's **Confirm network setup** button does two things. From the shell:

```bash
gcloud compute addresses create default-ip-range \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=24 \
    --description="SQL" \
    --network=default

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=default-ip-range \
    --network=default
```

### The instance

```bash
gcloud beta sql instances create wordpress-db \
    --database-version=MYSQL_8_0 \
    --cpu=1 --memory=3840MB \
    --region=$REGION \
    --root-password='Passw0rd1!' \
    --network=projects/$PROJECT_ID/global/networks/default \
    --allocated-ip-range-name=default-ip-range
```

> **If you get `unrecognized arguments`**, your gcloud build does not have
> every flag on the beta command. The flags that come and go between
> versions are `--zone` and `--storage-size`, and the private IP flags
> (`--network`, `--allocated-ip-range-name`) only exist on the **beta**
> command. The script tries a few known combinations in turn and then falls
> back to the Cloud SQL Admin API, which has no flags to guess at:

```bash
curl -s -X POST "https://sqladmin.googleapis.com/sql/v1beta4/projects/$PROJECT_ID/instances" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "wordpress-db",
    "region": "europe-west1",
    "databaseVersion": "MYSQL_8_0",
    "settings": {
      "tier": "db-custom-1-3840",
      "edition": "ENTERPRISE",
      "storageSize": 10,
      "rootPassword": "Passw0rd1!",
      "ipConfiguration": {
        "ipv4Enabled": true,
        "requireSsl": false,
        "privateNetwork": "projects/PROJECT/global/networks/default",
        "allocatedIpRange": "default-ip-range",
        "authorizedNetworks": [{ "name": "wordpress", "value": "IP/32" }]
      }
    }
  }'
```

| Console setting | CLI |
|---|---|
| Instance ID `wordpress-db` | the positional name |
| Enterprise, MySQL 8.0 | `--database-version=MYSQL_8_0` |
| 1 vCPU, 3.75 GB | `--cpu=1 --memory=3840MB` |
| 10 GB storage | `--storage-size=10` |

> ### The root password has to satisfy the password policy
>
> Cloud SQL applies a password policy to new instances. The default wants
> **at least 8 characters**, and usually a mix of upper case, lower case,
> digits and symbols. `abc1234` is 7 characters and the API rejects it with
> `INVALID_ARGUMENT: The root password does not conform to the password
> policy`.
>
> The script checks the length before it calls the API and asks again if the
> password is too short, and it prints the API's own error if the create
> still fails.
| Private IP, PSA, network `default` | `--network=... --allocated-ip-range-name=...` |

The lab also ticks **Allow unencrypted network traffic**, because WordPress
talks to the database over plain MySQL:

```bash
gcloud sql instances patch wordpress-db --no-require-ssl
```

And the proxy VM connects over the public IP, so its address has to be
allowlisted:

```bash
PROXY_IP=$(gcloud compute instances describe wordpress-proxy --zone=$ZONE \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

gcloud sql instances patch wordpress-db --authorized-networks="$PROXY_IP/32"
```

> `--authorized-networks` wants a bare `IP/32`. A `name=IP/32` value fails on
> `patch`.

Click **Check my progress** — *Create a Cloud SQL instance*.

## Task 3 — Configure a proxy on a virtual machine

### The database

```bash
gcloud sql databases create wordpress --instance=wordpress-db
```

The name has to be `wordpress` — that is what the application expects.

### The proxy

```bash
gcloud compute ssh wordpress-proxy --zone=$ZONE
```

On the VM:

```bash
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy

export SQL_CONNECTION=$PROJECT_ID:$REGION:wordpress-db
./cloud_sql_proxy -instances=$SQL_CONNECTION=tcp:3306 &
```

You should see:

```
Listening on 127.0.0.1:3306 for PROJECT_ID:REGION:wordpress-db
Ready for new connections
```

> **Start it with `nohup` instead of a bare `&`.** A background job started
> from an SSH session dies with that session, and the checkpoint wants the
> proxy to be *running*:
>
> ```bash
> nohup ./cloud_sql_proxy -instances=$SQL_CONNECTION=tcp:3306 > proxy.log 2>&1 &
> ```

Click **Check my progress** — *Create a database and configure a proxy on a
Virtual Machine*.

## Task 4 — Connect the application (in the browser)

Find the proxy VM's external IP:

```bash
curl -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip && echo
```

Open `http://<that ip>` in a browser, click **Let's Go**, and fill the form in:

| Field | Value |
|---|---|
| Database Name | `wordpress` |
| Username | `root` |
| Password | your root password |
| Database Host | `127.0.0.1` |

Click **Submit**, then **Run the installation**, then fill in any site details
and click **Install Wordpress**. It can take up to 3 minutes.

## Task 5 — Connect over the private IP

Get the Cloud SQL private IP:

```bash
gcloud sql instances describe wordpress-db --format="value(ipAddresses[0].ipAddress)"
```

Open the `wordpress-private-ip` VM's external IP in a browser, click **Let's
Go**, and fill the form in with the same values except:

| Field | Value |
|---|---|
| Database Host | the Cloud SQL **private IP** |

You should get an **Already Installed!** window, which means the private IP
connection works.

## Clean up

```bash
gcloud sql instances delete wordpress-db --quiet
gcloud compute addresses delete default-ip-range --global --quiet
```
