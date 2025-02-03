variable "infinia_deployment_name" {
  description = "Deployment name for Infinia resources, must be between 4 and 8 lowercase characters"
  type        = string

  validation {
    condition     = length(var.infinia_deployment_name) >= 4 && length(var.infinia_deployment_name) <= 8 && var.infinia_deployment_name == lower(var.infinia_deployment_name)
    error_message = "The deployment name must be between 4 and 8 characters, all lowercase."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-west-2"
}

variable "infinia_ami_id" {
  description = "AMI ID for the Infinia SDS instances"
  type        = string
}

variable "client_ami_id" {
  description = "AMI ID for the client instances"
  type        = string
}

variable "num_infinia_instances" {
  description = "Number of Infinia SDS instances to deploy"
  type        = number
  default     = 1
}

variable "num_client_instances" {
  description = "Number of client instances to deploy"
  type        = number
  default     = 1
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
  type = number
}

variable "num_ephemeral_devices" {
  description = "The number of ephemeral devices"
  type = number
}

variable "enable_public_ip" {
  description = "enable public IP for EC2 instances"
  type = bool
}