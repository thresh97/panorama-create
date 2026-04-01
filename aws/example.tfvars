region                 = "us-east-1"
prefix                 = "panorama"
ssh_key                = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@domain.com"
allowed_mgmt_cidrs     = ["203.0.113.0/24"]

mgmt_vpc_cidr          = "10.255.0.0/24"
panorama_version       = "11.2.8"
panorama_instance_type = "m5.4xlarge"

# availability_zone    = "us-east-1a"   # Optional; defaults to first available AZ
# panorama_ami_id      = "ami-xxxxxxxxxxxxxxxxx"  # Optional; overrides AMI lookup
