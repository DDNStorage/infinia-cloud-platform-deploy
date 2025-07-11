variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "ap-southeast-2"
}

variable "infinia_deployment_name" {
  description = "Name prefix for Infinia deployment"
  type        = string
  default     = "infinia"
}

variable "num_infinia_instances" {
  description = "Number of Infinia SDS EC2 instances"
  type        = number
  default     = 3
}

variable "infinia_ami_id" {
  description = "AMI ID for Infinia EC2 instances"
  type        = string
  default     = "ami-06b229b9768498b16"
}

variable "instance_type_infinia" {
  description = "EC2 instance type for Infinia"
  type        = string
  default     = "i3en.2xlarge"
}

# variable "key_pair_name" {
#   description = "Name of the key pair for SSH access"
#   type        = string
#   default     = "infinia-key-pair"
# }

variable "root_device_size" {
  description = "Root volume size for EC2 instances"
  type        = number
  default     = 256
}

variable "use_ebs_volumes" {
  description = "Whether to attach extra EBS volumes"
  type        = bool
  default     = true
}

variable "num_ephemeral_devices" {
  description = "Number of EBS volumes to attach per instance if use_ebs_volumes = true"
  type        = number
  default     = 4
}

variable "ebs_volume_size" {
  description = "Size of each additional EBS volume"
  type        = number
  default     = 128
}

variable "infinia_version" {
  type    = string
  default = "2.2.20"
}
