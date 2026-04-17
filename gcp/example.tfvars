project_id            = "your-gcp-project-id"
region                = "us-east1"
prefix                = "panorama"
ssh_key               = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@domain.com"
allowed_mgmt_cidrs    = ["203.0.113.0/24"]

mgmt_vpc_cidr         = "10.255.0.0/24"
panorama_version      = "11.2"
panorama_machine_type = "n2-standard-16"

# instance_count       = 1              # 1=standalone/LC  2=HA pair  3=Log Collector Group
# zone                 = "us-east1-b"  # Optional; single-instance only, ignored when instance_count > 1
# panorama_image_name  = "panorama-1126"     # Optional; overrides image family lookup

# log_disk_size_gb     = 2000  # Optional: additional pd-ssd disk for Panorama logs (0 = none)
