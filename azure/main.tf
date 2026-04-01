# --------------------------------------------------------------------------
# 1. PROVIDERS & DATA SOURCES
# --------------------------------------------------------------------------
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "random" {}

data "azurerm_client_config" "current" {}

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
# 2. MARKETPLACE AGREEMENT
# --------------------------------------------------------------------------
resource "azurerm_marketplace_agreement" "paloalto_panorama" {
  count     = var.create_marketplace_agreement ? 1 : 0
  publisher = "paloaltonetworks"
  offer     = "panorama"
  plan      = "byol"
}

# --------------------------------------------------------------------------
# 3. PANORAMA MANAGEMENT VNET
# --------------------------------------------------------------------------
resource "azurerm_resource_group" "mgmt" {
  name     = "${local.full_prefix}-mgmt-rg"
  location = var.location
}

resource "azurerm_virtual_network" "mgmt_vnet" {
  name                = "${local.full_prefix}-panorama-vnet"
  address_space       = [var.mgmt_vnet_cidr]
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
}

resource "azurerm_subnet" "panorama" {
  name                 = "panorama"
  resource_group_name  = azurerm_resource_group.mgmt.name
  virtual_network_name = azurerm_virtual_network.mgmt_vnet.name
  address_prefixes     = [cidrsubnet(var.mgmt_vnet_cidr, 4, 0)]
}

resource "azurerm_network_security_group" "panorama" {
  name                = "${local.full_prefix}-panorama-nsg"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name

  security_rule {
    name                       = "AllowMgmtInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "443"]
    source_address_prefixes    = var.allowed_mgmt_cidrs
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowICMP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.allowed_mgmt_cidrs
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowOutboundInternet"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "panorama" {
  subnet_id                 = azurerm_subnet.panorama.id
  network_security_group_id = azurerm_network_security_group.panorama.id
}

# --------------------------------------------------------------------------
# 4. VIRTUAL MACHINE - PANORAMA
# --------------------------------------------------------------------------
resource "azurerm_public_ip" "panorama_pip" {
  name                = "${local.full_prefix}-panorama-pip"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "panorama_nic" {
  name                = "${local.full_prefix}-panorama-nic"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.panorama.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(cidrsubnet(var.mgmt_vnet_cidr, 4, 0), 4)
    public_ip_address_id          = azurerm_public_ip.panorama_pip.id
  }
}

resource "azurerm_linux_virtual_machine" "panorama" {
  name                  = "${local.full_prefix}-panorama"
  resource_group_name   = azurerm_resource_group.mgmt.name
  location              = azurerm_resource_group.mgmt.location
  size                  = var.panorama_vm_size
  admin_username        = "panadmin"
  network_interface_ids = [azurerm_network_interface.panorama_nic.id]

  admin_ssh_key {
    username   = "panadmin"
    public_key = var.ssh_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "paloaltonetworks"
    offer     = "panorama"
    sku       = "byol"
    version   = var.panorama_version
  }

  plan {
    name      = "byol"
    publisher = "paloaltonetworks"
    product   = "panorama"
  }

  depends_on = [azurerm_marketplace_agreement.paloalto_panorama]
}

# --------------------------------------------------------------------------
# 5. VARIABLES
# --------------------------------------------------------------------------
variable "subscription_id" {
  type = string
}

variable "deployment_code" {
  type    = string
  default = null
}

variable "create_marketplace_agreement" {
  type    = bool
  default = false
}

variable "prefix" {
  type    = string
  default = "panorama"
}

variable "location" {
  type = string
}

variable "ssh_key" {
  type = string
}

variable "allowed_mgmt_cidrs" {
  type = list(string)
}

variable "panorama_version" {
  type    = string
  default = "11.2.8"
}

variable "panorama_vm_size" {
  type    = string
  default = "Standard_D16s_v5"
}

variable "mgmt_vnet_cidr" {
  type    = string
  default = "10.255.0.0/24"
}

# --------------------------------------------------------------------------
# 6. OUTPUTS
# --------------------------------------------------------------------------
output "panorama_public_ip" {
  description = "Public IP address of the Panorama VM."
  value       = azurerm_public_ip.panorama_pip.ip_address
}

output "panorama_vnet_id" {
  description = "Full Azure resource ID of the management VNET. Paste this as private_panorama_vnet_id in the vmseries-architectures deployment."
  value       = azurerm_virtual_network.mgmt_vnet.id
}

output "environment_info" {
  value = {
    tenant_id           = data.azurerm_client_config.current.tenant_id
    subscription_id     = var.subscription_id
    mgmt_resource_group = azurerm_resource_group.mgmt.name
  }
}
