output "infinia_instance_private_ips" {
  description = "The private IP addresses of the Infinia instances"
  value       = aws_instance.infinia[*].private_ip
}

output "infinia_instance_ids" {
  description = "The instance IDs of the Infinia instances"
  value       = aws_instance.infinia[*].id
}

output "client_instance_private_ips" {
  description = "The private IP addresses of the client instances"
  value       = aws_instance.client[*].private_ip
}

output "client_instance_ids" {
  description = "The instance IDs of the client instances"
  value       = aws_instance.client[*].id
}

output "vpc_id" {
  description = "The ID of the VPC where resources are deployed"
  value       = var.vpc_id
}

output "subnet_ids" {
  description = "The IDs of the subnets used for deployment"
  value       = var.subnet_ids
}

output "security_group_id" {
  description = "The ID of the security group used for the instances"
  value       = var.security_group_id
}

output "infinia_instance_count" {
  description = "The number of Infinia instances deployed"
  value       = var.num_infinia_instances
}

output "client_instance_count" {
  description = "The number of client instances deployed"
  value       = var.num_client_instances
}

output "load_balancer_private_ip" {
  description = "The private IP address of the load balancer instance"
  value       = aws_instance.load_balancer.private_ip
}

output "load_balancer_instance_id" {
  description = "The instance ID of the load balancer instance"
  value       = aws_instance.load_balancer.id
}
