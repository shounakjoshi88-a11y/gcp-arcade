# GSP156 — task by task

Manual equivalent of `gsp156.sh`, in case you'd rather run the commands
yourself. Assumes Cloud Shell with the lab project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud config get-value compute/zone)
```

---

## Task 1 — Terraform installation

The lab's verbatim method — HashiCorp apt repository, persisted across Cloud
Cloud Shell sessions:

```bash
cat <<'EOF' > ~/.customize_environment
# Set up HashiCorp repository and install Terraform
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
bash ~/.customize_environment
```

Faster alternative — the official release binary, still persisted:

```bash
mkdir -p ~/bin
VER=$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/terraform/latest \
      | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -fsSL -o /tmp/terraform.zip \
  "https://releases.hashicorp.com/terraform/${VER}/terraform_${VER}_linux_amd64.zip"
unzip -o -q /tmp/terraform.zip -d ~/bin
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.customize_environment
export PATH="$HOME/bin:$PATH"
```

Verify:

```bash
terraform --version
```

Expect `Terraform v1.5.7` or later.

---

## Task 2 — Build the infrastructure

### Configuration

Create `instance.tf`:

```bash
touch instance.tf
```

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_compute_instance" "default" {
  project      = "PROJECT_ID"
  zone         = "ZONE"
  name         = "terraform"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "DEBIAN_IMAGE"
    }
  }
  network_interface {
    network = "default"
    access_config {
    }
  }
}
```

Filling in the three placeholders:

```bash
# project
export PROJECT_ID=$(gcloud config get-value project)

# zone
export ZONE=$(gcloud config get-value compute/zone)

# Debian image - the lab usually leaves it in the project metadata
gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"
```

If the metadata has no image, use the newest Debian image published by
`debian-cloud`:

```bash
gcloud compute images list --project debian-cloud \
  --filter="family=debian-12" --sort-by="~creationTimestamp" --limit=1 \
  --format="value(name)"
```

Verify the file is there and that it is the only `.tf` file (Terraform loads
all of them):

```bash
ls
```

### Initialization

```bash
terraform init
```

Downloads the `hashicorp/google` provider.

### Execution plan

```bash
terraform plan
```

You should see `Plan: 1 to add, 0 to change, 0 to destroy.`

### Apply changes

```bash
terraform apply
```

Type `yes` at the prompt. Takes a couple of minutes while the VM boots.

Non-interactively:

```bash
terraform apply -auto-approve
```

### Inspect the state

```bash
terraform show
```

The VM should also appear under **Compute Engine → VM instances** in the
console.

---

## Task 3 — Test your understanding

1. *Terraform enables you to safely and predictably create, change, and improve infrastructure.* → **True**
2. *With Terraform, you can create your own custom provider plugins.* → **False**

---

## Clean up

```bash
terraform destroy
```

Or, to also remove the state and the downloaded provider:

```bash
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```
