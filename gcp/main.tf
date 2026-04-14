# --------------------------------------------------------------------------
# 1. PROVIDERS & DATA SOURCES
# --------------------------------------------------------------------------
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "random" {}

resource "random_string" "deploy_id" {
  length  = 3
  special = false
  upper   = false
  numeric = false
}

locals {
  deploy_prefix  = var.deployment_code != null && var.deployment_code != "" ? var.deployment_code : random_string.deploy_id.result
  full_prefix    = "${local.deploy_prefix}-${var.prefix}"
  zone           = var.zone != null ? var.zone : "${var.region}-b"
  panorama_image = var.panorama_image_name != null ? "projects/paloaltonetworksgcp-public/global/images/${var.panorama_image_name}" : data.google_compute_image.panorama[0].self_link
}

# --------------------------------------------------------------------------
# 2. IMAGE LOOKUP
# --------------------------------------------------------------------------
# Panorama images live in the paloaltonetworksgcp-public project. The family
# "panorama-112" always resolves to the latest 11.2.x image. No marketplace
# subscription step is required — the images are publicly accessible.
#
# To list available Panorama images:
#   gcloud compute images list \
#     --project paloaltonetworksgcp-public \
#     --no-standard-images \
#     --format="table(name,creationTimestamp,family)" \
#     --sort-by="~creationTimestamp" | grep panorama

data "google_compute_image" "panorama" {
  count   = var.panorama_image_name == null ? 1 : 0
  project = "paloaltonetworksgcp-public"
  family  = "panorama-${replace(var.panorama_version, ".", "")}"
}

# --------------------------------------------------------------------------
# 3. PANORAMA MANAGEMENT VPC
# --------------------------------------------------------------------------
resource "google_compute_network" "mgmt" {
  name                    = "${local.full_prefix}-panorama-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "mgmt" {
  name          = "${local.full_prefix}-panorama-subnet"
  ip_cidr_range = cidrsubnet(var.mgmt_vpc_cidr, 4, 0)
  region        = var.region
  network       = google_compute_network.mgmt.id
}

resource "google_compute_firewall" "mgmt_allow_ssh_https" {
  name    = "${local.full_prefix}-panorama-allow-ssh-https"
  network = google_compute_network.mgmt.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }

  source_ranges = var.allowed_mgmt_cidrs
  target_tags   = ["panorama-mgmt"]
}

resource "google_compute_firewall" "mgmt_allow_icmp" {
  name    = "${local.full_prefix}-panorama-allow-icmp"
  network = google_compute_network.mgmt.name

  allow {
    protocol = "icmp"
  }

  source_ranges = var.allowed_mgmt_cidrs
  target_tags   = ["panorama-mgmt"]
}

resource "google_compute_firewall" "mgmt_allow_internal" {
  name    = "${local.full_prefix}-panorama-allow-internal"
  network = google_compute_network.mgmt.name

  allow {
    protocol = "all"
  }

  source_ranges = [var.mgmt_vpc_cidr]
  target_tags   = ["panorama-mgmt"]
}

# --------------------------------------------------------------------------
# 4. VIRTUAL MACHINE - PANORAMA
# --------------------------------------------------------------------------
resource "google_compute_address" "panorama" {
  name   = "${local.full_prefix}-panorama-ip"
  region = var.region
}

resource "google_compute_instance" "panorama" {
  name         = "${local.full_prefix}-panorama"
  machine_type = var.panorama_machine_type
  zone         = local.zone

  tags = ["panorama-mgmt"]

  boot_disk {
    initialize_params {
      image = local.panorama_image
      size  = 81
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.mgmt.name
    subnetwork = google_compute_subnetwork.mgmt.name
    network_ip = cidrhost(cidrsubnet(var.mgmt_vpc_cidr, 4, 0), 4)

    access_config {
      nat_ip = google_compute_address.panorama.address
    }
  }

  metadata = {
    ssh-keys = "admin:${var.ssh_key}"
  }
}

# --------------------------------------------------------------------------
# 5. VARIABLES
# --------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region (e.g., us-east1)"
}

variable "zone" {
  type        = string
  default     = null
  description = "GCP zone. Defaults to {region}-b."
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
  description = "SSH public key for the admin user"
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
  type        = string
  default     = "11.2"
  description = "Panorama minor version (e.g., '11.2'). Selects the latest image in the panorama-{major}{minor} GCP image family."
}

variable "panorama_machine_type" {
  type    = string
  default = "n2-standard-16"
}

variable "panorama_image_name" {
  type        = string
  default     = null
  description = "Explicit GCP image name override (e.g., 'panorama-1126'). If null, the latest image in the panorama_version family is used."
}

# --------------------------------------------------------------------------
# 6. OUTPUTS
# --------------------------------------------------------------------------
output "panorama_public_ip" {
  description = "Public IP address of the Panorama VM."
  value       = google_compute_address.panorama.address
}

output "panorama_vpc_id" {
  description = "Self-link of the Panorama management VPC. Paste this as panorama_vpc_id in the vmseries-architectures deployment."
  value       = google_compute_network.mgmt.self_link
}

output "environment_info" {
  value = {
    project_id   = var.project_id
    region       = var.region
    zone         = local.zone
    network_name = google_compute_network.mgmt.name
  }
}
