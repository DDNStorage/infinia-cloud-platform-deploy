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

# Retrieve available availability zones dynamically
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "infinia_vpc" {
  cidr_block           = "10.0.0.0/16"  # Different CIDR block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "infinia-vpc"
  }
}

# Private subnets
resource "aws_subnet" "infinia_subnets" {
  count = 6

  vpc_id            = aws_vpc.infinia_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "infinia-subnet-${count.index + 1}"
  }
}

# Public Subnet for NAT Gateway
resource "aws_subnet" "infinia_public_subnet" {
  vpc_id                  = aws_vpc.infinia_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "infinia-public-subnet"
  }
}

# Add VPC Endpoints for SSM Services
locals {
  ssm_endpoints = {
    ssm          = "com.amazonaws.${var.aws_region}.ssm"
    ssmmessages  = "com.amazonaws.${var.aws_region}.ssmmessages"
    ec2messages  = "com.amazonaws.${var.aws_region}.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssm_endpoints" {
  for_each          = local.ssm_endpoints
  vpc_id            = aws_vpc.infinia_vpc.id
  service_name      = each.value
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.infinia_subnets[*].id
  security_group_ids = [aws_security_group.infinia_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "endpoint-${each.key}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "infinia_igw" {
  vpc_id = aws_vpc.infinia_vpc.id

  tags = {
    Name = "infinia-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "infinia_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.infinia_public_subnet.id

  tags = {
    Name = "infinia-nat-gateway"
  }

  depends_on = [aws_internet_gateway.infinia_igw]
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.infinia_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.infinia_igw.id
  }

  tags = {
    Name = "infinia-public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.infinia_public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}


# Route Table
resource "aws_route_table" "infinia_route_table" {
  vpc_id = aws_vpc.infinia_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.infinia_nat.id
  }

  tags = {
    Name = "infinia-route-table"
  }
}

# Associate each subnet with the route table
resource "aws_route_table_association" "infinia_subnet_association" {
  count = length(aws_subnet.infinia_subnets)

  subnet_id      = aws_subnet.infinia_subnets[count.index].id
  route_table_id = aws_route_table.infinia_route_table.id
}

# Security Group
resource "aws_security_group" "infinia_sg" {
  name        = "infinia-security-group"
  description = "Security group for Infinia VPC"
  vpc_id      = aws_vpc.infinia_vpc.id

  # Allow SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere"
  }

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  # Allow HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  # Allow all traffic within the security group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all traffic within security group"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "infinia-sg"
  }
}

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

# EC2 Instance
resource "aws_instance" "infinia" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.infinia_subnets[0].id
  security_groups = [aws_security_group.infinia_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  root_block_device {
    volume_size           = 256
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-realm",
    Role = "realm"
  }

  # user_data = <<-EOF
  #             #!/bin/bash
  #             LOG_FILE="/var/log/redsetup.log"
  #             exec > >(tee -a "$LOG_FILE") 2>&1

  #             # Download and process template
  #             sudo wget ${local.environment_variables.BASE_PKG_URL}/releases/rmd_template.json -O /tmp/rmd_template.json
  #             sudo awk -v ver='${local.environment_variables["RED_VER"]}' '{gsub("\\$\\{RED_VER\\}", ver)}1' /tmp/rmd_template.json > /tmp/rmd.json

  #             # Run the redsetup command
  #             sudo redsetup -realm-entry \
  #                 -realm-entry-secret ${local.environment_variables.REALM_ENTRY_SECRET} \
  #                 --admin-password ${local.environment_variables.ADMIN_PASSWORD} \
  #                 -ctrl-plane-ip $(hostname --ip-address) \
  #                 -release-metadata-file /tmp/rmd.json \

  #             # Authenticate and configure Infinia
  #             sudo redcli user login realm_admin -p ${local.environment_variables.ADMIN_PASSWORD}
  #             sudo redcli realm config generate
  #             sudo redcli realm config update -f realm_config.yaml
  #             sudo redcli license install -a ${local.environment_variables.LICENSE_KEY} -y

  #             echo "Setup completed successfully!" | tee -a "$LOG_FILE"
  #             EOF
}





# resource "aws_instance" "infinia_realm_entry" {
#   ami           = var.ami_id
#   instance_type = var.instance_type
#   subnet_id     = aws_subnet.infinia_subnet.id
#   availability_zone = var.availability_zone
#   iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

#   tags = {
#     Name = "${var.infinia_deployment_name}-realm"
#   }

#   # user_data = <<-EOF
#   #             #!/bin/bash
#   #             LOG_FILE="/var/log/redsetup.log"
#   #             exec > >(tee -a "$LOG_FILE") 2>&1

#   #             export BASE_PKG_URL=${local.environment_variables.BASE_PKG_URL}
#   #             export RELEASE_TYPE=${local.environment_variables.RELEASE_TYPE}
#   #             export TARGET_ARCH=${local.environment_variables.TARGET_ARCH}
#   #             export REL_DIST_PATH=${local.environment_variables.REL_DIST_PATH}
#   #             export REL_PKG_URL=${local.environment_variables.REL_PKG_URL}
#   #             export RED_VER=${local.environment_variables.RED_VER}
              
#   #             sudo wget $BASE_PKG_URL/releases/rmd_template.json -O /tmp/rmd_template.json && envsubst < /tmp/rmd_template.json > /tmp/rmd.json
#   #             sudo redsetup -realm-entry \
#   #                 -realm-entry-secret ${local.environment_variables.REALM_ENTRY_SECRET} \
#   #                 --admin-password ${local.environment_variables.ADMIN_PASSWORD} \
#   #                 -ctrl-plane-ip $(hostname --ip-address) \
#   #                 -release-metadata-file /tmp/rmd.json \
              
#   #             sudo redcli realm config generate \
#   #             sudo redcli realm config update -f realm_config.yaml \
#   #             sudo redcli license install -a ${local.environment_variables.LICENSE_KEY} -y
#   #             EOF
# }

resource "aws_instance" "infinia_non_realm_nodes" {
  count         = var.num_non_realm_nodes
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.infinia_subnets[count.index % length(aws_subnet.infinia_subnets)].id
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  depends_on    = [aws_instance.infinia]

  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  root_block_device {
    volume_size           = 256
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-nonrealm-${format("%02d", count.index + 1)}",
    Role = "nonrealm"
  }

  # user_data = <<-EOF
  #             #!/bin/bash
  #             LOG_FILE="/var/log/redsetup.log"
  #             exec > >(tee -a "$LOG_FILE") 2>&1

  #             sudo redsetup --realm-entry-address ${aws_instance.infinia.private_ip} --realm-entry-secret ${var.realm_entry_secret}
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
variable "public_subnet_cidr" {}
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
