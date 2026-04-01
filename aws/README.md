# panorama-create — AWS

> **FOR LAB AND DEMONSTRATION USE ONLY.**
> This code is provided without warranty of any kind, express or implied. It is not validated for production use. No support is provided. Use at your own risk.

Terraform deployment for a Palo Alto Networks Panorama management VM in AWS.

This is **Phase 1** of a two-phase deployment workflow. After deploying Panorama here, bootstrap and configure it, then use the `panorama_vpc_id` output in the [vmseries-architectures](https://github.com/mharms/vmseries-architectures) deployment.

## Prerequisites

**Subscribe to Panorama in AWS Marketplace before first deployment.** Terraform cannot accept marketplace terms on your behalf in AWS.

1. Go to the [Panorama BYOL listing on AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-paloaltonetworks-panorama)
2. Click **Continue to Subscribe** and accept the terms
3. You only need to do this once per AWS account

To find the AMI ID for your region and version after subscribing:
```bash
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=PA-Panorama-AWS-11.2.8*" \
  --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' \
  --output text
```

## Architecture

Deploys a single management VPC with:
- A `/24` management VPC (default `10.255.0.0/24`)
- A Panorama subnet with Security Group allowing SSH/HTTPS from `allowed_mgmt_cidrs`
- Internet Gateway and route table for outbound internet access
- Panorama EC2 instance with static private IP (`.4`) and an Elastic IP

## Usage

```bash
cd aws/
terraform init
terraform apply -var-file="example.tfvars"
```

Copy the `panorama_vpc_id` output value — you'll need it as `panorama_vpc_id` in the firewall deployment.

## Outputs

| Output | Description |
|--------|-------------|
| `panorama_public_ip` | Elastic IP for SSH/HTTPS access to Panorama |
| `panorama_vpc_id` | AWS VPC ID of the mgmt VPC — paste into `vmseries-architectures` |
| `environment_info` | Account/region/VPC info |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | — | AWS region (e.g., `us-east-1`) |
| `prefix` | `panorama` | Resource name prefix |
| `deployment_code` | auto-generated | Short code prepended to all resource names |
| `ssh_key` | — | SSH public key for `panadmin` user |
| `allowed_mgmt_cidrs` | — | CIDRs allowed to reach Panorama on ports 22/443 |
| `mgmt_vpc_cidr` | `10.255.0.0/24` | VPC address space |
| `panorama_version` | `11.2.8` | Panorama version (used for AMI lookup) |
| `panorama_instance_type` | `m5.4xlarge` | EC2 instance type (16 vCPU / 64 GB RAM) |
| `availability_zone` | first available | AZ for the Panorama subnet |
| `panorama_ami_id` | auto-lookup | Explicit AMI ID override (skips AMI data source) |

## Post-Deployment: Bootstrap Panorama

```bash
# Requires: pip install paramiko pan-os-python (in venv/)
python panorama-init.py <panorama_public_ip> --username panadmin --ssh-key ~/.ssh/id_rsa
```

## Phase 2: Deploy Firewalls

```bash
cd ../../vmseries-architectures/aws
# Set panorama_vpc_id = "<panorama_vpc_id output>" in your tfvars
terraform init && terraform apply -var-file="example.tfvars"
```
