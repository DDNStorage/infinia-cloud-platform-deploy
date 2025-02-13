# Create IAM Role for Session Manager
resource "aws_iam_role" "ssm_role" {
  name = "${var.infinia_deployment_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AmazonSSMManagedInstanceCore Policy to Role
resource "aws_iam_role_policy_attachment" "ssm_core_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${var.infinia_deployment_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_network_interface" "efa" {
  count           = var.num_infinia_instances
  subnet_id       = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  interface_type  = var.interface_type == "" ? null : var.interface_type
  tags = {
    Name = "${var.infinia_deployment_name}-efa-eni-${format("%02d", count.index)}"
  }
}

# Deploy Infinia SDS Instances
resource "aws_instance" "infinia" {
  count                = var.num_infinia_instances
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  dynamic "network_interface" {
    for_each = var.interface_type != "" ? [1] : []
    content {
      network_interface_id = aws_network_interface.efa[count.index].id
      device_index         = 0
    }
  }

  # Use subnet_id, security_groups, and public IP only if interface_type is empty
  subnet_id                   = var.interface_type == "" ? element(var.subnet_ids, count.index % length(var.subnet_ids)) : null
  security_groups             = var.interface_type == "" ? [var.security_group_id] : null
  associate_public_ip_address = var.interface_type == "" ? var.enable_public_ip : null

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      subnet_id,
      security_groups,
      ami,
      instance_type,
      key_name,
      root_block_device,
      tags,
      volume_tags
    ]
  }

  root_block_device {
    volume_size           = var.root_device_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Attach EBS volumes only if use_ebs_volumes is true
  dynamic "ebs_block_device" {
    for_each = var.use_ebs_volumes ? range(var.num_ephemeral_devices) : []
    content {
      device_name           = "/dev/sd${element(["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u"], ebs_block_device.value)}"
      volume_size           = var.ebs_volume_size # Default size for each disk
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }


  tags = {
    Name       = "${var.infinia_deployment_name}-sn-${format("%02d", count.index)}"
    Deployment = var.infinia_deployment_name
    Role       = count.index == 0 ? "realm" : "nonrealm"
  }
}

# Deploy Client Instances
resource "aws_instance" "client" {
  count                       = var.num_client_instances
  ami                         = var.client_ami_id
  instance_type               = var.instance_type_client
  subnet_id                   = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups             = [var.security_group_id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = var.enable_public_ip

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      subnet_id,
      security_groups,
      ami,
      instance_type,
      key_name,
      root_block_device,
      tags,
      volume_tags
    ]
  }

  root_block_device {
    volume_size           = var.root_device_size # Set root volume size to 150 GB
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
    Deployment = var.infinia_deployment_name
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/aws_ec2.yml"
  content  = <<EOT
plugin: aws_ec2
regions:
  - us-east-1
filters:
  tag:Role: ['realm', 'nonrealm']
  tag:Deployment: "${var.infinia_deployment_name}"
use_extra_vars: true
keyed_groups:
  - prefix: role
    key: tags['Role']
hostnames:
  - instance-id
EOT
}

resource "local_file" "ansible_vars" {
  filename = "${path.module}/ansible/vars.yml"
  content  = <<EOT
# vars.yml
# Non-sensitive variables
infinia_version: ${var.infinia_version}
ansible_connection: aws_ssm
ansible_aws_ssm_bucket_name: red-ansible-scripts
ansible_aws_ssm_region: us-east-1
ansible_aws_ssm_timeout: 3600
ansible_aws_ssm_retries: 200
EOT
}


# # Deploy Load Balancer Instance
# resource "aws_instance" "load_balancer" {
#   ami           = var.client_ami_id
#   instance_type = "t3.medium"
#   subnet_id     = element(var.subnet_ids, 0)
#   security_groups = [var.security_group_id]
#   key_name      = var.key_pair_name

#   lifecycle {
#     create_before_destroy = false
#     ignore_changes = [
#       subnet_id,
#       security_groups,
#       ami,
#       instance_type,
#       key_name,
#       root_block_device,
#       tags,
#       volume_tags
#     ]
#   }

#   root_block_device {
#     volume_size           = 150
#     volume_type           = "gp3"
#     delete_on_termination = true
#   }

#   tags = {
#     Name = "${var.infinia_deployment_name}-nginx"
#   }
# }


