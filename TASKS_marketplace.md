# Deploy a LAMP Stack with Google Cloud Marketplace — task by task

Manual equivalent of `gsp_marketplace.sh`. Assumes Cloud Shell with the lab
project active.

This lab is also listed as *Google Cloud Fundamentals: Getting Started with
Cloud Marketplace*. The steps and the checkpoint — **Use Cloud Marketplace to
deploy a LAMP stack** — are identical.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

---

## Task 1 — Deploy a LAMP stack using Cloud Marketplace

### The console way (what the lab asks for)

1. In the console, click **Marketplace**.
2. Search for **LAMP** and press Enter.
3. Click **LAMP Stack, by Google Click to Deploy**.
   > If you choose another LAMP stack, the lab instructions do not work.
4. Click **GET STARTED**.
5. On the **Agreements** page, tick **Terms and agreements** and click **Agree**.
6. On the *Successfully agreed to terms* popup, click **Deploy**.
7. If prompted for the **Compute Engine API** and **Infrastructure Manager
   API**, click **Enable**.
8. For **Zone**, select the zone your lab assigned.
9. For **Machine Type**, select **E2** as the Series and **e2-medium** as the
   Machine Type.
10. Leave everything else at its default and click **Deploy**.

The status reads `lamp-1 is being deployed`, then `lamp-1 has been deployed`.
Once the software is installed, the details panel shows the **site address**.

Click **Check my progress**.

### The multiple-choice question in task 1

*Which tool is used to deploy Google Cloud Marketplace solutions like the
LAMP Stack?*

| Option | Answer |
|---|---|
| Deployment Manager | **Yes** — Marketplace solutions ship as Cloud Deployment Manager templates |
| Terraform | No — a separate IaC tool that works, but is not what Marketplace uses |
| Firestore | No — a NoSQL document database |
| Template Manager | No — not a Google Cloud product; the templates are hosted *for* Deployment Manager |

The clue is in the lab itself: it asks you to enable the **Infrastructure
Manager API** next to the Compute Engine API, and the console reports
`lamp-1 is being deployed` through Deployment Manager.

### The command line way (what the script does)

The marketplace image is licensed, so it can only be launched from the console
after the terms are accepted. The script therefore creates the *same*
deployment — same deployment name, same instance name, same machine type,
same zone, same firewall rule — and installs the LAMP stack with a startup
script instead.

```bash
gcloud services enable compute.googleapis.com deploymentmanager.googleapis.com
```

`lamp.yaml`:

```yaml
resources:
- name: lamp-1-vm
  type: compute.v1.instance
  properties:
    name: lamp-1-vm
    zone: ZONE
    machineType: zones/ZONE/machineTypes/e2-medium
    canIpForward: false
    disks:
    - deviceName: persistent-disk-0
      type: PERSISTENT
      autoDelete: true
      boot: true
      initializeParams:
        sourceImage: projects/debian-cloud/global/images/family/debian-12
    networkInterfaces:
    - network: global/networks/default
      accessConfigs:
      - name: External NAT
        type: ONE_TO_ONE_NAT
    metadata:
      items:
      - key: startup-script
        value: |
          # installs apache2, php, php-mysql, mariadb-server, phpmyadmin
          # writes /etc/apache2/sites-available/lamp-server.conf
          # and the Congratulations! page in /var/www/html
- name: lamp-1-allow-http
  type: compute.v1.firewall
  properties:
    network: global/networks/default
    sourceRanges:
    - 0.0.0.0/0
    allowed:
    - IPProtocol: TCP
      ports:
      - "80"
```

Preview it first — a preview creates nothing, and it is the only way to catch
a malformed field before the real deployment:

```bash
gcloud deployment-manager deployments create lamp-1 \
    --config=lamp.yaml --preview
```

Then create it:

```bash
gcloud deployment-manager deployments create lamp-1 \
    --config=lamp.yaml \
    --labels="marketplace-suppress-benign-warnings=true"
```

## Task 2/3 — Verify the deployment

```bash
gcloud compute instances describe lamp-1-vm --zone ZONE \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)"
```

Open that address — you should get the **Congratulations!** page. The script
also drops `phpinfo.php` into the document root:

```bash
gcloud compute scp phpinfo.php lamp-1-vm:/var/www/html/phpinfo.php --zone ZONE
```

## Clean up

```bash
gcloud deployment-manager deployments delete lamp-1 --quiet
```

Or, with the script:

```bash
./gsp_mar