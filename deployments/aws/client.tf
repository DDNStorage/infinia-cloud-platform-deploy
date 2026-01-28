# Create IAM Role for Session Manager
resource "aws_network_interface" "infinia_interface" {
  count           = var.num_infinia_instances
  subnet_id       = element(local.subnet_ids, count.index % length(local.subnet_ids))
  security_groups = [local.security_group_id]
  interface_type  = var.interface_type == "" ? null : var.interface_type
  tags = {
    Name = "${var.infinia_deployment_name}-interface-eni-${format("%02d", count.index)}"
  }
}


resource "aws_instance" "client" {
  count                       = var.num_client_instances
  ami                         = var.client_ami_id
  instance_type               = var.instance_type_client
  subnet_id                   = element(local.subnet_ids, count.index % length(local.subnet_ids))
  security_groups             = [local.security_group_id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = var.enable_public_ip
  user_data                   = local.user_startup_script_client
  depends_on                  = [time_sleep.wait_for_nonrealm_nodes]
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
    Role       = "client"
  }
}

