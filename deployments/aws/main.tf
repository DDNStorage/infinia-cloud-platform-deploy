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
# Deploy Infinia SDS Instances
resource "aws_instance" "infinia" {
  count         = var.num_infinia_instances
  ami           = var.infinia_ami_id
  instance_type = var.instance_type_infinia
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = true
  
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

  tags = {
    Name = "${var.infinia_deployment_name}-sn-${format("%02d", count.index)}"
    Role = count.index == 0 ? "realm" : "nonrealm"
  }
}

# Deploy Client Instances
resource "aws_instance" "client" {
  count         = var.num_client_instances
  ami           = var.client_ami_id
  instance_type = var.instance_type_client
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = true

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

  dynamic "ephemeral_block_device" {
    for_each = range(var.num_ephemeral_devices)  # Number of ephemeral drives
    content {
      device_name  = "/dev/sd${char(102 + ephemeral_block_device.value)}"  # e.g., /dev/sdf, /dev/sdg, etc.
      virtual_name = "ephemeral${ephemeral_block_device.value}"  # AWS Instance Store Device Name
    }
  }

  tags = {
    Name = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
  }
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


