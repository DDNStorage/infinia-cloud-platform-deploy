locals {
  environment_variables = {
    BASE_PKG_URL    = "https://storage.googleapis.com/ddn-redsetup-public"
    RELEASE_TYPE    = ""
    TARGET_ARCH     = "amd64"
    REL_DIST_PATH   = "ubuntu/24.04"
    REL_PKG_URL     = "https://storage.googleapis.com/ddn-redsetup-public/releases/ubuntu/24.04"
    RED_VER         = var.infinia_version
    REALM_ENTRY_SECRET = var.realm_entry_secret
    ADMIN_PASSWORD  = var.admin_password
    LICENSE_KEY     = var.license_key
  }
}

resource "aws_vpc" "infinia_vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "infinia_subnet" {
  vpc_id     = aws_vpc.infinia_vpc.id
  cidr_block = var.subnet_cidr
  availability_zone = var.availability_zone
}

resource "aws_security_group" "infinia_sg" {
  vpc_id = aws_vpc.infinia_vpc.id

# ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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

resource "aws_iam_role_policy_attachment" "ssm_core_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${var.infinia_deployment_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_instance" "infinia_realm_entry" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.infinia_subnet.id
  availability_zone = var.availability_zone
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "${var.infinia_deployment_name}-realm"
  }

  # user_data = <<-EOF
  #             #!/bin/bash
  #             LOG_FILE="/var/log/redsetup.log"
  #             exec > >(tee -a "$LOG_FILE") 2>&1

  #             export BASE_PKG_URL=${local.environment_variables.BASE_PKG_URL}
  #             export RELEASE_TYPE=${local.environment_variables.RELEASE_TYPE}
  #             export TARGET_ARCH=${local.environment_variables.TARGET_ARCH}
  #             export REL_DIST_PATH=${local.environment_variables.REL_DIST_PATH}
  #             export REL_PKG_URL=${local.environment_variables.REL_PKG_URL}
  #             export RED_VER=${local.environment_variables.RED_VER}
              
  #             sudo wget $BASE_PKG_URL/releases/rmd_template.json -O /tmp/rmd_template.json && envsubst < /tmp/rmd_template.json > /tmp/rmd.json
  #             sudo redsetup -realm-entry \
  #                 -realm-entry-secret ${local.environment_variables.REALM_ENTRY_SECRET} \
  #                 --admin-password ${local.environment_variables.ADMIN_PASSWORD} \
  #                 -ctrl-plane-ip $(hostname --ip-address) \
  #                 -release-metadata-file /tmp/rmd.json \
              
  #             sudo redcli realm config generate \
  #             sudo redcli realm config update -f realm_config.yaml \
  #             sudo redcli license install -a ${local.environment_variables.LICENSE_KEY} -y
  #             EOF
}

resource "aws_instance" "infinia_non_realm_nodes" {
  count         = var.num_non_realm_nodes
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.infinia_subnet.id
  availability_zone = var.availability_zone
  depends_on    = [aws_instance.infinia_realm_entry]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "${var.infinia_deployment_name}-nonrealm-${format("%02d", count.index)}"
  }

  # user_data = <<-EOF
  #             #!/bin/bash
  #             LOG_FILE="/var/log/redsetup.log"
  #             exec > >(tee -a "$LOG_FILE") 2>&1

  #             sudo redsetup --realm-entry-address ${aws_instance.infinia_realm_entry.private_ip} --realm-entry-secret ${local.environment_variables.REALM_ENTRY_SECRET}
  #             EOF
}

variable "realm_entry_secret" {}
variable "admin_password" {}
variable "license_key" {}
variable "aws_region" {}
variable "ami_id" {}
variable "instance_type" {}
variable "vpc_cidr" {}
variable "infinia_version" {}
variable "subnet_cidr" {}
variable "num_non_realm_nodes" {}
variable "availability_zone" {}
variable "infinia_deployment_name" {
  description = "Deployment name for Infinia resources, must be between 4 and 8 lowercase characters"
  type        = string

  validation {
    condition     = length(var.infinia_deployment_name) >= 4 && length(var.infinia_deployment_name) <= 8 && var.infinia_deployment_name == lower(var.infinia_deployment_name)
    error_message = "The deployment name must be between 4 and 8 characters, all lowercase."
  }
}
