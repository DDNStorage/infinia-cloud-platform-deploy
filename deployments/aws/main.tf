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
  count                = var.num_infinia_instances
  ami                  = var.infinia_ami_id
  instance_type        = var.instance_type_infinia
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  subnet_id                   = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups             = [var.security_group_id]
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
    Role       = count.index == 0 ? "realm" : "nonrealm"
  }
}

# Deploy Client Instances
resource "aws_instance" "client" {
  count                       = var.num_client_instances
  ami                         = var.client_ami_id
  instance_type               = var.instance_type_client
  subnet_id                   = element(var.client_subnet_ids, count.index % length(var.subnet_ids))
  security_groups             = [var.client_security_group_id]
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
    volume_size           = var.root_device_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
    Deployment = var.infinia_deployment_name
  }
}

# Ansible Inventory Output
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/aws_ec2.yml"
  content  = <<EOT
plugin: aws_ec2
regions:
  - ${var.aws_region}
filters:
  tag:Deployment: "${var.infinia_deployment_name}"
use_extra_vars: true
keyed_groups:
  - prefix: role
    key: tags['Role']
hostnames:
  - instance-id
groups:
  client_nodes: "tags.Name is defined and 'cn' in tags.Name"
  realm_nodes: "tags.Role is defined and tags.Role == 'realm'"
  nonrealm_nodes: "tags.Role is defined and tags.Role == 'nonrealm'"
EOT
}

# Ansible Variables Output
resource "local_file" "ansible_vars" {
  filename = "${path.module}/ansible/vars.yml"
  content  = <<EOT
# vars.yml
infinia_version: ${var.infinia_version}
ansible_connection: aws_ssm
ansible_aws_ssm_bucket_name: ${var.bucket_name}
ansible_aws_ssm_region: ${var.aws_region}
ansible_aws_ssm_timeout: 3600
ansible_aws_ssm_retries: 200
EOT
}
