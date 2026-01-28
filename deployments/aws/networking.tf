# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Resource
resource "aws_vpc" "main" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = var.vpc_cidr

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name       = var.vpc_name != "" ? var.vpc_name : "${var.infinia_deployment_name}-vpc"
    Deployment = var.infinia_deployment_name
  }
}

# Explicitly set VPC DNS attributes (workaround for AWS provider issues)
resource "aws_vpc_dhcp_options" "main" {
  count           = var.create_vpc ? 1 : 0
  domain_name     = "ec2.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name       = "${var.infinia_deployment_name}-dhcp-options"
    Deployment = var.infinia_deployment_name
  }
}

resource "aws_vpc_dhcp_options_association" "main" {
  count           = var.create_vpc ? 1 : 0
  vpc_id          = aws_vpc.main[0].id
  dhcp_options_id = aws_vpc_dhcp_options.main[0].id
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name       = "${var.infinia_deployment_name}-igw"
    Deployment = var.infinia_deployment_name
  }
}

# Subnets
resource "aws_subnet" "main" {
  count = var.create_vpc ? length(var.subnet_cidrs) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index] : data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = var.enable_public_ip

  tags = {
    Name       = "${var.infinia_deployment_name}-subnet-${count.index + 1}"
    Deployment = var.infinia_deployment_name
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = var.create_vpc ? 1 : 0
  domain = "vpc"

  tags = {
    Name       = "${var.infinia_deployment_name}-nat-eip"
    Deployment = var.infinia_deployment_name
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  count         = var.create_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.main[0].id

  tags = {
    Name       = "${var.infinia_deployment_name}-nat"
    Deployment = var.infinia_deployment_name
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table for private subnets
resource "aws_route_table" "private" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-private-rt"
    Deployment = var.infinia_deployment_name
  }
}

# Route Table for public subnet (for NAT gateway)
resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-public-rt"
    Deployment = var.infinia_deployment_name
  }
}

# Public subnet association (first subnet for NAT gateway)
resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.main[0].id
  route_table_id = aws_route_table.public[0].id
}

# Private subnet associations (remaining subnets)
resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? length(aws_subnet.main) - 1 : 0
  subnet_id      = aws_subnet.main[count.index + 1].id
  route_table_id = aws_route_table.private[0].id
}

# VPC Endpoints for SSM (Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  count               = var.create_vpc ? 1 : 0
  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.main[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name       = "${var.infinia_deployment_name}-ssm-endpoint"
    Deployment = var.infinia_deployment_name
  }
}

resource "aws_vpc_endpoint" "ssm_messages" {
  count               = var.create_vpc ? 1 : 0
  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.main[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name       = "${var.infinia_deployment_name}-ssmmessages-endpoint"
    Deployment = var.infinia_deployment_name
  }
}

resource "aws_vpc_endpoint" "ec2_messages" {
  count               = var.create_vpc ? 1 : 0
  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.main[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name       = "${var.infinia_deployment_name}-ec2messages-endpoint"
    Deployment = var.infinia_deployment_name
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  count       = var.create_vpc ? 1 : 0
  name        = "${var.infinia_deployment_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-vpc-endpoints-sg"
    Deployment = var.infinia_deployment_name
  }
}

# Default Security Group for created VPC
resource "aws_security_group" "default" {
  count       = var.create_vpc ? 1 : 0
  name        = "${var.infinia_deployment_name}-default-sg"
  description = "Default security group for ${var.infinia_deployment_name} deployment"
  vpc_id      = aws_vpc.main[0].id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All traffic within VPC (TCP)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All traffic within VPC (UDP)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ICMP within VPC
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all traffic from same security group (default VPC behavior)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${var.infinia_deployment_name}-default-sg"
    Deployment = var.infinia_deployment_name
  }
}