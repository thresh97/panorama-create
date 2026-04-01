# panorama-create — Azure

> **FOR LAB AND DEMONSTRATION USE ONLY.**
> This code is provided without warranty of any kind, express or implied. It is not validated for production use. No support is provided. Use at your own risk.

Terraform deployment for a Palo Alto Networks Panorama management VM in Azure.

This is **Phase 1** of a two-phase deployment workflow. After deploying Panorama here, bootstrap and configure it, then use the `panorama_vnet_id` output in the [vmseries-architectures](https://github.com/mharms/vmseries-architectures) deployment.

## Architecture

Deploys a single management VNET with:
- A `/24` management VNET (default `10.255.0.0/24`)
- A Panorama subnet with NSG allowing SSH/HTTPS from `allowed_mgmt_cidrs`
- Panorama VM with static private IP (`.4`) and a public IP

## Usage

```bash
cd azure/
terraform init
terraform apply -var-file="example.tfvars"
```

Copy the `panorama_vnet_id` output value — you'll need it as `private_panorama_vnet_id` in the firewall deployment.

## Outputs

| Output | Description |
|--------|-------------|
| `panorama_public_ip` | Public IP for SSH/HTTPS access to Panorama |
| `panorama_vnet_id` | Full Azure resource ID of the mgmt VNET — paste into `vmseries-architectures` |
| `environment_info` | Tenant/subscription/resource group info |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `subscription_id` | — | Azure subscription ID |
| `location` | — | Azure region (e.g., `eastus`) |
| `prefix` | `panorama` | Resource name prefix |
| `deployment_code` | auto-generated | Short code prepended to all resource names |
| `ssh_key` | — | SSH public key for `panadmin` user |
| `allowed_mgmt_cidrs` | — | CIDRs allowed to reach Panorama on ports 22/443 |
| `mgmt_vnet_cidr` | `10.255.0.0/24` | VNET address space |
| `panorama_version` | `11.2.8` | Panorama image version |
| `panorama_vm_size` | `Standard_D16s_v5` | VM size |
| `create_marketplace_agreement` | `false` | Accept marketplace terms (first deployment only) |

## Post-Deployment: Bootstrap Panorama

```bash
# Requires: pip install paramiko pan-os-python (in venv/)
python panorama-bootstrap.py <panorama_public_ip> --username panadmin --ssh-key ~/.ssh/id_rsa
```

## Phase 2: Deploy Firewalls

```bash
cd ../../../vmseries-architectures/azure
# Set private_panorama_vnet_id = "<panorama_vnet_id output>" in your tfvars
terraform init && terraform apply -var-file="example.tfvars"
```
