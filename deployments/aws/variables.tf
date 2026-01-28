variable "infinia_deployment_name" {
  description = "Deployment name for Infinia resources, must be between 4 and 8 lowercase characters"
  type        = string

}

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "infinia_ami_id" {
  description = "AMI ID for the Infinia SDS instances"
  type        = string
}

variable "client_ami_id" {
  description = "AMI ID for the client instances"
  type        = string
  default     = ""
}

variable "num_infinia_instances" {
  description = "Number of Infinia SDS instances to deploy"
  type        = number
  default     = 1
}

variable "num_client_instances" {
  description = "Number of client instances to deploy"
  type        = number
  default     = 0
}

variable "key_pair_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
}

variable "instance_type_infinia" {
  description = "Instance type for Infinia SDS instances"
  type        = string
  default     = "i3en.24xlarge"
}

variable "instance_type_client" {
  description = "Instance type for client instances"
  type        = string
  default     = "t3.medium"
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use existing one"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (used only if create_vpc is true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC (used only if create_vpc is true)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed (required if create_vpc is false)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of Subnet IDs where instances will be deployed (required if create_vpc is false)"
  type        = list(string)
  default     = []
}

variable "subnet_cidrs" {
  description = "List of CIDR blocks for subnets (used only if create_vpc is true). First subnet is public (for NAT gateway), rest are private."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones for subnets (used only if create_vpc is true). If empty, will use first N AZs in the region"
  type        = list(string)
  default     = []
}

variable "security_group_id" {
  description = "Security group ID for the instances"
  type        = string
}

variable "root_device_size" {
  description = "The size for the root device"
  type        = number
  default     = 0
}

variable "num_ephemeral_devices" {
  description = "The number of ephemeral devices"
  type        = number
  default     = 0
}

variable "interface_type" {
  description = "The ethernet interface type"
  type        = string
  default     = ""
}

variable "use_ebs_volumes" {
  description = "Flag to determine whether EBS volumes should be attached"
  type        = bool
  default     = false # Default is no EBS volumes unless explicitly enabled
}

variable "ebs_volume_size" {
  description = "Size of each EBS volume (in GB)"
  type        = number
  default     = 128
}


variable "ebs_volumes_per_vm" {
  description = "Number of EBS volumes attached to each VM"
  type        = number
  default     = 2
}

variable "enable_public_ip" {
  description = "Flag to determin whether enalbe public IP"
  type        = bool
  default     = false
}

variable "infinia_version" {
  description = "The infinia version"
  type        = string
  default     = "2.2.16"
}

variable "infinia_license" {
  type    = string
  default = ""
}

variable "base_pkg_url" {
  type    = string
  default = "https://storage.googleapis.com/ddn-redsetup-public"
}

variable "release_type" {
  type    = string
  default = ""
}

variable "rel_dist_path" {
  type = string

  default = "ubuntu/24.04"
}

variable "bucket_name" {
  description = "Name of the AWS S3 bucket for Ansible SSM"
  type        = string
}

variable "sleep_durations" {
  description = "Map of instance types to sleep durations"
  type        = map(string)
  default = {
    "m7a.xlarge"   = "5m"
    "i3en.2xlarge" = "3m"

  }
}

# variables.tf
variable "admin_password" {
  type      = string
  sensitive = true
}

variable "realm_license" {
  type      = string
  sensitive = true
}



