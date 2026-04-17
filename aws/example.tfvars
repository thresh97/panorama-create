region                 = "us-east-1"
prefix                 = "panorama"
ssh_key                = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@domain.com"
allowed_mgmt_cidrs     = ["203.0.113.0/24"]

mgmt_vpc_cidr          = "10.255.0.0/24"
panorama_version       = "11.2.8"
panorama_instance_type = "m5.4xlarge"

# instance_count       = 1              # 1=standalone/LC  2=HA pair  3=Log Collector Group
# availability_zone    = "us-east-1a"  # Optional; single-instance only, ignored when instance_count > 1
# panorama_ami_id      = "ami-xxxxxxxxxxxxxxxxx"  # Optional; overrides AMI lookup

# log_disk_size_gb    = 2000  # Optional: additional gp3 EBS volume for Panorama logs (0 = none)
