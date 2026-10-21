# GSP345 — task by task

Manual equivalent of `gsp345.sh`. Assumes Cloud Shell with the lab project
active and the lab already started (it pre-creates `tf-instance-1` and
`tf-instance-2` for you).

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

> **The checkpoints conflict with each other.** Task 4 creates a third
> instance and task 5 destroys it again, so the lab only scores a task when
> you click **Check my progress** for it. Click the button after each task.

---

## Setup — Install Terraform

```bash
cat <<'EOF' > ~/.customize_environment
# Set up HashiCorp repository and install Terraform
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
bash ~/.customize_environment
terraform --version
```

---

## Task 1 — Create the configuration files

```bash
mkdir -p modules/instances modules/storage
touch main.tf variables.tf
touch modules/instances/{instances.tf,outputs.tf,variables.tf}
touch modules/storage/{storage.tf,outputs.tf,variables.tf}
```

`variables.tf` (same content in the root and in each module):

```hcl
variable "region" {
  default = "REGION"
}

variable "zone" {
  default = "ZONE"
}

variable "project_id" {
  default = "PROJECT_ID"
}
```

`main.tf`:

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
```

```bash
terraform init
```

## Task 2 — Import infrastructure

Read the details of the two pre-created instances:

```bash
gcloud compute instances list --format="table(name,zone,machineType,id,disks[0].source)"
```

`modules/instances/instances.tf`:

```hcl
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "MACHINE_TYPE"
  zone         = var.zone

  allow_stopping_for_update = true

  metadata_startup_script = <<-EOT
	#!/bin/bash
	EOT

  boot_disk {
    initialize_params {
      image = "IMAGE"
    }
  }

  network_interface {
    network = "default"
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "MACHINE_TYPE"
  zone         = var.zone

  allow_stopping_for_update = true

  metadata_startup_script = <<-EOT
	#!/bin/bash
	EOT

  boot_disk {
    initialize_params {
      image = "IMAGE"
    }
  }

  network_interface {
    network = "default"
  }
}
```

Import them (the ID is the numeric instance id, not the name):

```bash
terraform init
terraform import module.instances.google_compute_instance.tf-instance-1 INSTANCE_ID_1
terraform import module.instances.google_compute_instance.tf-instance-2 INSTANCE_ID_2
terraform apply
```

## Task 3 — Configure a remote backend

`modules/storage/storage.tf`:

```hcl
resource "google_storage_bucket" "storage-bucket" {
  name                        = "BUCKET_NAME"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}
```

Add to `main.tf`:

```hcl
module "storage" {
  source     = "./modules/storage"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
```

```bash
terraform init
terraform apply
```

Now add the backend to the `terraform` block in `main.tf`:

```hcl
terraform {
  backend "gcs" {
    bucket = "BUCKET_NAME"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
```

```bash
terraform init
```

Answer **yes** when it asks to copy the existing state to the new backend.
Non-interactively: `terraform init -migrate-state`.

## Task 4 — Modify and update infrastructure

In `modules/instances/instances.tf`, set all three instances to
`e2-standard-2` and add a third:

```hcl
resource "google_compute_instance" "tf-instance-3" {
  name         = "tf-instance-3"
  machine_type = "e2-standard-2"
  zone         = var.zone

  allow_stopping_for_update = true

  metadata_startup_script = <<-EOT
	#!/bin/bash
	EOT

  boot_disk {
    initialize_params {
      image = "IMAGE"
    }
  }

  network_interface {
    network = "default"
  }
}
```

```bash
terraform init
terraform apply
```

## Task 5 — Destroy resources

Delete the `tf-instance-3` resource block from `instances.tf`, then:

```bash
terraform init
terraform apply
```

## Task 6 — Use a module from the Registry

[terraform-google-modules/network/google](https://registry.terraform.io/modules/terraform-google-modules/network/google)
version `10.0.0`. Add to `main.tf`:

```hcl
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "10.0.0"

  project_id   = var.project_id
  network_name = "terraform-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name   = "subnet-02"
      subnet_ip     = "10.10.20.0/24"
      subnet_region = var.region
    }
  ]
}
```

```bash
terraform init
terraform apply
```

Then in `instances.tf`, point each instance at the new network and subnet:

```hcl
  network_interface {
    network    = "terraform-vpc"
    subnetwork = "subnet-01"   # subnet-02 for tf-instance-2
  }
```

```bash
terraform init
terraform apply
```

## Task 7 — Configure a firewall

Add to `main.tf`:

```hcl
resource "google_compute_firewall" "tf-firewall" {
  name    = "tf-firewall"
  network = "projects/PROJECT_ID/global/networks/terraform-vpc"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}
```

```bash
terraform init
terraform apply
```

---

## Clean up

```bash
cd ~/gsp345
terraform destroy -auto-approve
```

The bucket is created with `force_destroy = true`, so it goes too.
