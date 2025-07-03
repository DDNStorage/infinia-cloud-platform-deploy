# Create S3 bucket for Ansible scripts
resource "aws_s3_bucket" "ansible_scripts" {
  bucket = "red-ansible-scripts-shiloh-t2"
}

resource "aws_s3_bucket_public_access_block" "ansible_scripts" {
  bucket = aws_s3_bucket.ansible_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload scripts to S3
resource "aws_s3_object" "node_setup" {
  bucket = aws_s3_bucket.ansible_scripts.id
  key    = "infinia-node-setup.sh"
  source = "${path.module}/scripts/infinia-node-setup.sh"
  etag   = filemd5("${path.module}/scripts/infinia-node-setup.sh")
}

resource "aws_s3_object" "cluster_config" {
  bucket = aws_s3_bucket.ansible_scripts.id
  key    = "infinia-cluster-configure.sh"
  source = "${path.module}/scripts/infinia-cluster-configure.sh"
  etag   = filemd5("${path.module}/scripts/infinia-cluster-configure.sh")
}

# Create IAM Role for Session Manager and S3 access
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

# Create policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.infinia_deployment_name}-s3-access"
  role = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.ansible_scripts.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.ansible_scripts.arn}/*"
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
  - ${var.aws_region}
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
ansible_aws_ssm_bucket_name: red-ansible-scripts-shiloh-t2
ansible_aws_ssm_region: ${var.aws_region}
ansible_aws_ssm_timeout: 3600
ansible_aws_ssm_retries: 200
EOT
}
