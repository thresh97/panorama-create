subscription_id              = "00000000-0000-0000-0000-000000000000"
location                     = "eastus"
prefix                       = "panorama"
ssh_key                      = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@domain.com"
allowed_mgmt_cidrs           = ["203.0.113.0/24"]
create_marketplace_agreement = false # Set to true on first deployment in the sub

mgmt_vnet_cidr   = "10.255.0.0/24"
panorama_version = "11.2.8"
panorama_vm_size = "Standard_D16s_v5"
