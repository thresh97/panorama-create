# --------------------------------------------------------------------------
# 1. PROVIDERS & DATA SOURCES
# --------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "random" {}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_string" "deploy_id" {
  length  = 3
  special = false
  upper   = false
  numeric = false
}

locals {
  deploy_prefix = var.deployment_code != null && var.deployment_code != "" ? var.deployment_code : random_string.deploy_id.result
  full_prefix   = "${local.deploy_prefix}-${var.prefix}"
}

# --------------------------------------------------------------------------
# 2. AMI LOOKUP
# --------------------------------------------------------------------------
# NOTE: You must subscribe to the Panorama BYOL listing in AWS Marketplace
# before deploying: https://aws.amazon.com/marketplace/pp/prodview-paloaltonetworks-panorama

/*
To find AMI IDs for your region:

  VERSION=11.2.8
  aws ec2 describe-images \
    --owners aws-marketplace \
    --filters "Name=name,Values=Panorama-AWS-${VERSION}*" \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' \
    --output text
*/

data "aws_ami" "panorama" {
  count       = var.panorama_ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["Panorama-AWS-${var.panorama_version}*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  panorama_ami = var.panorama_ami_id != null ? var.panorama_ami_id : data.aws_ami.panorama[0].id
}

# --------------------------------------------------------------------------
# 3. SSH KEY PAIR
# --------------------------------------------------------------------------
resource "aws_key_pair" "panorama" {
  key_name   = "${local.full_prefix}-panorama-key"
  public_key = var.ssh_key
}

# --------------------------------------------------------------------------
# 4. PANORAMA MANAGEMENT VPC
# --------------------------------------------------------------------------
resource "aws_vpc" "mgmt" {
  cidr_block           = var.mgmt_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.full_prefix}-panorama-vpc" }
}

# One subnet per instance, one per AZ, using consecutive /28 slices of mgmt_vpc_cidr.
# With the default 10.255.0.0/24: instance 0 → 10.255.0.0/28 (AZ-a),
#                                  instance 1 → 10.255.0.16/28 (AZ-b),
#                                  instance 2 → 10.255.0.32/28 (AZ-c).
resource "aws_subnet" "panorama" {
  count  = var.instance_count
  vpc_id = aws_vpc.mgmt.id

  cidr_block        = cidrsubnet(var.mgmt_vpc_cidr, 4, count.index)
  availability_zone = (var.instance_count == 1 && var.availability_zone != null) ? var.availability_zone : data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = count.index == 0 ? "${local.full_prefix}-panorama-subnet" : "${local.full_prefix}-panorama-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "mgmt" {
  vpc_id = aws_vpc.mgmt.id
  tags   = { Name = "${local.full_prefix}-igw" }
}

resource "aws_route_table" "panorama" {
  vpc_id = aws_vpc.mgmt.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mgmt.id
  }

  tags = { Name = "${local.full_prefix}-panorama-rt" }
}

resource "aws_route_table_association" "panorama" {
  count          = var.instance_count
  subnet_id      = aws_subnet.panorama[count.index].id
  route_table_id = aws_route_table.panorama.id
}

resource "aws_security_group" "panorama" {
  name        = "${local.full_prefix}-panorama-sg"
  description = "Panorama management security group"
  vpc_id      = aws_vpc.mgmt.id

  dynamic "ingress" {
    for_each = toset(["22", "443"])
    content {
      from_port   = tonumber(ingress.value)
      to_port     = tonumber(ingress.value)
      protocol    = "tcp"
      cidr_blocks = var.allowed_mgmt_cidrs
    }
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.allowed_mgmt_cidrs
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.mgmt_vpc_cidr]
    description = "Allow all VPC-internal traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound internet"
  }

  tags = { Name = "${local.full_prefix}-panorama-sg" }
}

# --------------------------------------------------------------------------
# 5. VIRTUAL MACHINE - PANORAMA
# --------------------------------------------------------------------------
resource "aws_eip" "panorama" {
  count  = var.instance_count
  domain = "vpc"
  tags = {
    Name = count.index == 0 ? "${local.full_prefix}-panorama-eip" : "${local.full_prefix}-panorama-eip-${count.index + 1}"
  }
}

resource "aws_instance" "panorama" {
  count         = var.instance_count
  ami           = local.panorama_ami
  instance_type = var.panorama_instance_type
  subnet_id     = aws_subnet.panorama[count.index].id
  private_ip    = cidrhost(cidrsubnet(var.mgmt_vpc_cidr, 4, count.index), 4)

  vpc_security_group_ids = [aws_security_group.panorama.id]
  key_name               = aws_key_pair.panorama.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 81
  }

  tags = {
    Name = count.index == 0 ? "${local.full_prefix}-panorama" : "${local.full_prefix}-panorama-${count.index + 1}"
  }
}

resource "aws_eip_association" "panorama" {
  count         = var.instance_count
  instance_id   = aws_instance.panorama[count.index].id
  allocation_id = aws_eip.panorama[count.index].id
}

# --------------------------------------------------------------------------
# 6. MIGRATION: moved blocks for existing single-instance deployments
# --------------------------------------------------------------------------
moved {
  from = aws_subnet.panorama
  to   = aws_subnet.panorama[0]
}

moved {
  from = aws_route_table_association.panorama
  to   = aws_route_table_association.panorama[0]
}

moved {
  from = aws_eip.panorama
  to   = aws_eip.panorama[0]
}

moved {
  from = aws_instance.panorama
  to   = aws_instance.panorama[0]
}

moved {
  from = aws_eip_association.panorama
  to   = aws_eip_association.panorama[0]
}

# --------------------------------------------------------------------------
# 7. VARIABLES
# --------------------------------------------------------------------------
variable "region" {
  type        = string
  description = "AWS region (e.g., us-east-1)"
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "AZ override for single-instance deployments (instance_count = 1). Ignored when instance_count > 1 — instances are distributed across AZs automatically."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of Panorama instances. 1=standalone/LC, 2=HA pair, 3=Log Collector Group. Instances are placed in separate AZs automatically."

  validation {
    condition     = contains([1, 2, 3], var.instance_count)
    error_message = "instance_count must be 1, 2, or 3."
  }
}

variable "deployment_code" {
  type    = string
  default = null
}

variable "prefix" {
  type    = string
  default = "panorama"
}

variable "ssh_key" {
  type        = string
  description = "SSH public key for the panadmin user"
}

variable "allowed_mgmt_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach Panorama on ports 22/443"
}

variable "mgmt_vpc_cidr" {
  type    = string
  default = "10.255.0.0/24"
}

variable "panorama_version" {
  type    = string
  default = "11.2.8"
}

variable "panorama_instance_type" {
  type    = string
  default = "m5.4xlarge"
}

variable "panorama_ami_id" {
  type        = string
  default     = null
  description = "Explicit AMI ID override. If null, the latest BYOL AMI matching panorama_version is looked up automatically."
}

# --------------------------------------------------------------------------
# 8. OUTPUTS
# --------------------------------------------------------------------------
output "panorama_public_ip" {
  description = "Public IP of the first Panorama instance. Use panorama_public_ips for all instances."
  value       = aws_eip.panorama[0].public_ip
}

output "panorama_public_ips" {
  description = "Public IP addresses of all Panorama instances (index matches instance number)."
  value       = aws_eip.panorama[*].public_ip
}

output "panorama_private_ips" {
  description = "Private IP addresses of all Panorama instances."
  value       = aws_instance.panorama[*].private_ip
}

output "panorama_availability_zones" {
  description = "Availability zones of all Panorama instances."
  value       = aws_subnet.panorama[*].availability_zone
}

output "panorama_vpc_id" {
  description = "AWS VPC ID of the management VPC. Paste this as panorama_vpc_id in the vmseries-architectures deployment."
  value       = aws_vpc.mgmt.id
}

output "environment_info" {
  value = {
    account_id     = data.aws_caller_identity.current.account_id
    region         = data.aws_region.current.name
    vpc_name       = "${local.full_prefix}-panorama-vpc"
    instance_count = var.instance_count
  }
}
