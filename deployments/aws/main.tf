resource "aws_instance" "infinia_realm" {
  count                = 1
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  subnet_id                   = element(local.subnet_ids, count.index % length(local.subnet_ids))
  security_groups             = [local.security_group_id]
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
  depends_on      = [aws_instance.infinia_realm]
  create_duration = "5m"
}


resource "aws_instance" "infinia_none_realm" {
  count                = var.num_infinia_instances
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  subnet_id                   = element(local.subnet_ids, count.index % length(local.subnet_ids))
  security_groups             = [local.security_group_id]
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
    for_each = var.use_ebs_volumes ? toset(range(var.ebs_volumes_per_vm)) : []
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

resource "time_sleep" "wait_for_nonrealm_nodes" {
  depends_on      = [aws_instance.infinia_none_realm]
  create_duration = "5m"
}

# ---- Phase-2 on the realm via SSM after all nodes are up ----
# Requires: AWS credentials available where `terraform apply` runs,
#           realm/nonrealm instances have the SSM agent/IAM profile (you already do),
#           and your existing time_sleep resources.

resource "time_sleep" "after_nonrealm" {
  depends_on      = [aws_instance.infinia_none_realm]
  create_duration = "2m"
}

resource "null_resource" "realm_phase2" {
  depends_on = [time_sleep.wait_for_nonrealm_nodes]

  triggers = {
    realm_id    = aws_instance.infinia_realm[0].id
    want_nodes  = tostring(local.instance_count)
    region      = var.aws_region
    admin_pw    = var.admin_password # only to retrigger on change
    license_key = var.realm_license  # only to retrigger on change
  }

  provisioner "local-exec" {
    # Only pass non-sensitive args as flags.
    # Secrets go via environment below.
    command = join(" ", [
      "python3", "scripts/realm_phase2.py",
      "--region", var.aws_region,
      "--instance-id", aws_instance.infinia_realm[0].id,
      "--want", tostring(local.instance_count),
      "--admin", local.admin_password,
      "--license", local.realm_license,
    ])

    # Provide secrets via env to avoid any escaping issues
    environment = {
      ADMIN_PW    = var.admin_password
      LICENSE_KEY = var.realm_license
    }

    # Enhanced error handling for GitHub Actions
    on_failure = fail
  }

  # Add a cleanup provisioner to capture logs on failure
  provisioner "local-exec" {
    when    = destroy
    command = "echo '::notice title=Cleanup::Realm phase2 resource is being destroyed'"
  }
}
