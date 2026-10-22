# Automating the Deployment of Infrastructure Using Terraform — task by task

Manual equivalent of `gsp_terraform.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE_1=$(gcloud config get-value compute/zone)
export ZONE_2=us-central1-b
```

The zones are lab-assigned per run — take them from the setup panel.

---

## Task 1 — Set up Terraform and the workspace

### Install the real Terraform

Cloud Shell ships a placeholder wrapper. Verify and install the real one:

```bash
terraform version
```

If it does not print `Terraform v...`:

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
hash -r
```

### Stage the workspace in `~/tfinfra`

```bash
mkdir -p ~/tfinfra/instance
cd ~/tfinfra
```

`provider.tf`:

```hcl
provider "google" {}
```

`instance/variables.tf`:

```hcl
variable "instance_name" {}
variable "instance_zone" {}
variable "instance_type" {
  default = "e2-micro"
}
variable "instance_network" {}
```

`instance/main.tf`:

```hcl
resource "google_compute_instance" "vm_instance" {
  name         = "${var.instance_name}"
  zone         = "${var.instance_zone}"
  machine_type = "${var.instance_type}"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "${var.instance_network}"
    access_config {
      # Allocate a one-to-one NAT IP to the instance
    }
  }
}
```

`mynetwork.tf`:

```hcl
resource "google_compute_network" "mynetwork" {
  name                    = "mynetwork"
  auto_create_subnetworks = "true"
}

resource "google_compute_firewall" "mynetwork-allow-http-ssh-rdp-icmp" {
  name    = "mynetwork-allow-http-ssh-rdp-icmp"
  network = google_compute_network.mynetwork.self_link
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "3389"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

module "mynet-vm-1" {
  source           = "./instance"
  instance_name    = "mynet-vm-1"
  instance_zone    = "ZONE_1"
  instance_network = google_compute_network.mynetwork.self_link
}

module "mynet-vm-2" {
  source           = "./instance"
  instance_name    = "mynet-vm-2"
  instance_zone    = "ZONE_2"
  instance_network = google_compute_network.mynetwork.self_link
}
```

Format everything:

```bash
terraform fmt
```

Click **Check my progress** — *Install Terraform and set up the workspace*.

---

## Task 2 — Initialize, plan and apply

```bash
cd ~/tfinfra

terraform init

terraform plan
```

Review the plan — it should create the network, the firewall rule and the
two VMs.

```bash
terraform apply -auto-approve
```

The apply can fail once with a subnet-provisioning error; the subnets of an
auto mode network are still being created in the background. Wait 15 seconds
and run it again.

Click **Check my progress** — *Initialize, plan and apply the Terraform
configuration*.

---

## Task 3 — Verify the deployment and the connectivity

```bash
gcloud compute instances list --filter="name:(mynet-vm-1 OR mynet-vm-2)" \
    --format="table(name,zone,networkInterfaces[0].networkIP,status)"
```

Ping between the two VMs:

```bash
VM2_IP=$(gcloud compute instances describe mynet-vm-2 --zone=ZONE_2 \
          --format="value(networkInterfaces[0].networkIP)")
gcloud compute ssh mynet-vm-1 --zone=ZONE_1 --tunnel-through-iap \
    --command="ping -c 3 $VM2_IP"
```

Click **Check my progress** — *Verify the deployment and the connectivity*.

---

## Clean up

```bash
cd ~/tfinfra
terraform destroy -auto-approve
rm -rf ~/tfinfra
```