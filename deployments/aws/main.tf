resource "aws_instance" "infinia_realm" {
  count                = 1
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  subnet_id                   = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups             = [var.security_group_id]
  associate_public_ip_address = var.enable_public_ip
  user_data                   = local.user_startup_script_realm


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
    for_each = var.use_ebs_volumes ? toset(range(var.ebs_volumes_per_vm)) : []
    content {
      device_name           = "/dev/sd${element(["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u"], ebs_block_device.key)}"
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }


  tags = {
    Name       = "${var.infinia_deployment_name}-realm-sn-${format("%02d", count.index)}"
    Deployment = var.infinia_deployment_name
    Role       = "realm"
  }
}



resource "time_sleep" "wait_for_realm_node" {
  create_duration = "5m"
}


resource "aws_instance" "infinia_none_realm" {
  count                = var.num_infinia_instances
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  subnet_id                   = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups             = [var.security_group_id]
  associate_public_ip_address = var.enable_public_ip
  depends_on                  = [aws_instance.infinia_realm, time_sleep.wait_for_realm_node]
  user_data                   = local.user_startup_script_none_realm

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
    Name       = "${var.infinia_deployment_name}-sn-${format("%02d", count.index)}"
    Deployment = var.infinia_deployment_name
    Role       = "nonrealm"
  }
}

