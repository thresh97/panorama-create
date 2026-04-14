# panorama-create — GCP

> **FOR LAB AND DEMONSTRATION USE ONLY.**
> This code is provided without warranty of any kind, express or implied. It is not validated for production use. No support is provided. Use at your own risk.

Terraform deployment for a Palo Alto Networks Panorama management VM in GCP.

This is **Phase 1** of a two-phase deployment workflow. After deploying Panorama here, bootstrap and configure it, then use the `panorama_vpc_id` output in the [vmseries-architectures](https://github.com/mharms/vmseries-architectures) deployment.

## Prerequisites

**Authenticate Terraform to GCP** using Application Default Credentials before deploying:

```bash
gcloud auth application-default login
```

No marketplace subscription step is required — Panorama images in the `paloaltonetworksgcp-public` project are publicly accessible.

To list available Panorama images:
```bash
gcloud compute images list \
  --project paloaltonetworksgcp-public \
  --no-standard-images \
  --format="table(name,creationTimestamp,family)" \
  --sort-by="~creationTimestamp" | grep panorama
```

## Architecture

Deploys a single management VPC with:
- A `/24` management VPC (default `10.255.0.0/24`)
- A Panorama subnet with firewall rules allowing SSH/HTTPS from `allowed_mgmt_cidrs`
- Panorama instance with static private IP (`.4`) and a static external IP

GCP does not require `mgmt-interface-swap` for Panorama — NIC0 serves as the management interface directly.

## Usage

```bash
cd gcp/
terraform init
terraform apply -var-file="example.tfvars"
```

Copy the `panorama_vpc_id` output value — you'll need it as `panorama_vpc_id` in the firewall deployment.

## Outputs

| Output | Description |
|--------|-------------|
| `panorama_public_ip` | External IP for SSH/HTTPS access to Panorama |
| `panorama_vpc_id` | Self-link of the mgmt VPC — paste into `vmseries-architectures` |
| `environment_info` | Project/region/zone/network info |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | — | GCP project ID |
| `region` | — | GCP region (e.g., `us-east1`) |
| `zone` | `{region}-b` | GCP zone |
| `prefix` | `panorama` | Resource name prefix |
| `deployment_code` | auto-generated | Short code prepended to all resource names |
| `ssh_key` | — | SSH public key for the `admin` user |
| `allowed_mgmt_cidrs` | — | CIDRs allowed to reach Panorama on ports 22/443 |
| `mgmt_vpc_cidr` | `10.255.0.0/24` | VPC address space |
| `panorama_version` | `11.2` | Panorama minor version — selects latest image in the `panorama-{major}{minor}` family |
| `panorama_machine_type` | `n2-standard-16` | GCP machine type (16 vCPU / 64 GB RAM) |
| `panorama_image_name` | auto-lookup | Explicit image name override (e.g., `panorama-1126`) |

## Post-Deployment: Bootstrap Panorama

```bash
# Requires: pip install paramiko pan-os-python (in venv/)
python panorama-init.py <panorama_public_ip> --username admin --ssh-key ~/.ssh/id_rsa
```

## Phase 2: Deploy Firewalls

```bash
cd ../../vmseries-architectures/gcp
# Set panorama_vpc_id = "<panorama_vpc_id output>" in your tfvars
terraform init && terraform apply -var-file="example.tfvars"
```
