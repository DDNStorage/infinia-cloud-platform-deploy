output "infinia_instances" {
  description = "Details of Infinia instances"
  value = [
    for i, instance in aws_instance.infinia : {
      name       = instance.tags["Name"]
      id         = instance.id
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
      role       = instance.tags["Role"]
    }
  ]
}

output "infinia_instances_formatted" {
  description = "Formatted details of Infinia instances"
  value = <<EOT
Infinia Instances:
%{for i, instance in aws_instance.infinia~}
  ${i + 1}. ${instance.tags["Name"]}:
    - Instance ID: ${instance.id}
    - Private IP:  ${instance.private_ip}
    - Public IP:   ${instance.public_ip}
    - Role:        ${instance.tags["Role"]}
%{endfor~}
EOT
}

output "client_instances" {
  description = "Details of client instances"
  value = [
    for i, instance in aws_instance.client : {
      name       = instance.tags["Name"]
      id         = instance.id
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  ]
}

output "client_instances_formatted" {
  description = "Formatted details of client instances"
  value = <<EOT
Client Instances:
%{for i, instance in aws_instance.client~}
  ${i + 1}. ${instance.tags["Name"]}:
    - Instance ID: ${instance.id}
    - Private IP:  ${instance.private_ip}
    - Public IP:   ${instance.public_ip}
%{endfor~}
EOT
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

# output "load_balancer_private_ip" {
#   description = "The private IP address of the load balancer instance"
#   value       = aws_instance.load_balancer.private_ip
# }

# output "load_balancer_instance_id" {
#   description = "The instance ID of the load balancer instance"
#   value       = aws_instance.load_balancer.id
# }
