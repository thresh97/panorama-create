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
  deploy_prefix     = var.deployment_code != null && var.deployment_code != "" ? var.deployment_code : random_string.deploy_id.result
  full_prefix       = "${local.deploy_prefix}-${var.prefix}"
  availability_zone = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

# --------------------------------------------------------------------------
# 2. AMI LOOKUP
# --------------------------------------------------------------------------
# NOTE: You must subscribe to the Panorama BYOL listing in AWS Marketplace
# before deploying: https://aws.amazon.com/marketplace/pp/prodview-paloaltonetworks-panorama
#
# To find AMI IDs for your region:
#   aws ec2 describe-images \
#     --owners aws-marketplace \
#     --filters "Name=name,Values=PA-Panorama-AWS-${var.panorama_version}*" \
#     --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' \
#     --output text

data "aws_ami" "panorama" {
  count       = var.panorama_ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["PA-Panorama-AWS-${var.panorama_version}*"]
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

resource "aws_subnet" "panorama" {
  vpc_id            = aws_vpc.mgmt.id
  cidr_block        = cidrsubnet(var.mgmt_vpc_cidr, 4, 0)
  availability_zone = local.availability_zone
  tags = { Name = "${local.full_prefix}-panorama-subnet" }
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
  subnet_id      = aws_subnet.panorama.id
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
  domain = "vpc"
  tags   = { Name = "${local.full_prefix}-panorama-eip" }
}

resource "aws_instance" "panorama" {
  ami           = local.panorama_ami
  instance_type = var.panorama_instance_type
  subnet_id     = aws_subnet.panorama.id
  private_ip    = cidrhost(cidrsubnet(var.mgmt_vpc_cidr, 4, 0), 4)

  vpc_security_group_ids = [aws_security_group.panorama.id]
  key_name               = aws_key_pair.panorama.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 81
  }

  tags = { Name = "${local.full_prefix}-panorama" }
}

resource "aws_eip_association" "panorama" {
  instance_id   = aws_instance.panorama.id
  allocation_id = aws_eip.panorama.id
}

# --------------------------------------------------------------------------
# 6. VARIABLES
# --------------------------------------------------------------------------
variable "region" {
  type        = string
  description = "AWS region (e.g., us-east-1)"
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "AZ for the Panorama subnet. Defaults to the first available AZ in the region."
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
# 7. OUTPUTS
# --------------------------------------------------------------------------
output "panorama_public_ip" {
  description = "Public IP address of the Panorama VM."
  value       = aws_eip.panorama.public_ip
}

output "panorama_vpc_id" {
  description = "AWS VPC ID of the management VPC. Paste this as panorama_vpc_id in the vmseries-architectures deployment."
  value       = aws_vpc.mgmt.id
}

output "environment_info" {
  value = {
    account_id = data.aws_caller_identity.current.account_id
    region     = data.aws_region.current.name
    vpc_name   = "${local.full_prefix}-panorama-vpc"
  }
}
