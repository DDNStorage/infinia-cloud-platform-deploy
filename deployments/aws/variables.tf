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

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of Subnet IDs where instances will be deployed"
  type        = list(string)
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
  default     = 7500
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

variable "realm_entry_secret" {
  type    = string
  default = ""

}

variable "realm_entry_host" {
  type    = string
  default = ""

}

variable "realm_secret" {
  description = "Secret for the Infinia realm"
  type        = string
  sensitive   = true # Mark as sensitive to prevent logging
  default     = "PA-ssW00r^d"
}

variable "admin_password" {
  description = "Admin password for Infinia"
  type        = string
  sensitive   = true # Mark as sensitive to prevent logging
  default     = "PA-ssW00r^d"
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
