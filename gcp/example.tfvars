project_id            = "your-gcp-project-id"
region                = "us-east1"
prefix                = "panorama"
ssh_key               = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@domain.com"
allowed_mgmt_cidrs    = ["203.0.113.0/24"]

mgmt_vpc_cidr         = "10.255.0.0/24"
panorama_version      = "11.2"
panorama_machine_type = "n2-standard-16"

# zone                 = "us-east1-b"        # Optional; defaults to {region}-b
# panorama_image_name  = "panorama-1126"     # Optional; overrides image family lookup
