# Create IAM Role for Session Manager
# realmn 
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
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${var.infinia_deployment_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}


# Create EFA Network Interface for Realm Node
resource "aws_network_interface" "efa_realm" {
  count           = var.interface_type == "" ? 0 : 1 # Only create if EFA is enabled
  subnet_id       = element(var.subnet_ids, 0)
  security_groups = [var.security_group_id]
  interface_type  = var.interface_type == "" ? null : var.interface_type
  tags = {
    Name = "${var.infinia_deployment_name}-efa"
  }
}

resource "aws_instance" "infinia_realm" {
  count                = 1 # Always one realm node
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  user_data            = local.user_startup_script_realm
  dynamic "network_interface" {
    for_each = var.interface_type != "" ? [1] : []
    content {
      network_interface_id = aws_network_interface.efa_realm[0].id
      device_index         = 0
    }
  }

  subnet_id                   = var.interface_type == "" ? element(var.subnet_ids, 0) : null
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

  dynamic "ebs_block_device" {
    for_each = var.use_ebs_volumes ? range(var.ebs_volumes_per_vm) : []
    content {
      device_name           = "/dev/sd${element(["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u"], ebs_block_device.value)}"
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }


  tags = {
    Name       = "${var.infinia_deployment_name}-sn-realm"
    Deployment = var.infinia_deployment_name
    Role       = "realm"
  }
}

resource "aws_instance" "infinia_none_realm" {
  count                = var.num_infinia_instances
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  user_data            = local.user_startup_script_none_realm
  depends_on           = [aws_instance.infinia_realm] # Explicit dependency on realm node

  dynamic "network_interface" {
    for_each = var.interface_type != "" ? [1] : []
    content {
      network_interface_id = aws_network_interface.efa_none_realm[count.index].id
      device_index         = 0
    }
  }

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

  dynamic "ebs_block_device" {
    for_each = var.use_ebs_volumes ? range(var.ebs_volumes_per_vm) : []
    content {
      device_name           = "/dev/sd${element(["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u"], ebs_block_device.value)}"
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-sn-${format("%02d", count.index + 1)}" # Start index from 1 for none-realm
    Deployment = var.infinia_deployment_name
    Role       = "nonerealm"
  }
}

