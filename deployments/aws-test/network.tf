# ======================================
# Data source
# ======================================
data "aws_availability_zones" "available" {}

# ======================================
# VPC
# ======================================
resource "aws_vpc" "infinia_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.infinia_deployment_name}-vpc"
  }
}

# ======================================
# Internet Gateway
# ======================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.infinia_vpc.id
  tags = {
    Name = "${var.infinia_deployment_name}-igw"
  }
}

# ======================================
# Subnets
# ======================================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.infinia_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.infinia_deployment_name}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.infinia_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.infinia_deployment_name}-private-subnet"
  }
}
# ======================================
# Elastic IP for NAT Gateway
# ======================================
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.igw]
}

# ======================================
# NAT Gateway
# ======================================
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = {
    Name = "${var.infinia_deployment_name}-nat"
  }
}

# ======================================
# Route Tables
# ======================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.infinia_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.infinia_deployment_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.infinia_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.infinia_deployment_name}-private-rt"
  }
}

# ======================================
# Route Table Associations
# ======================================
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ======================================
# Security Group
# ======================================
resource "aws_security_group" "infinia_sg" {
  name        = "${var.infinia_deployment_name}-sg"
  description = "Allow TCP 8111 internally"
  vpc_id      = aws_vpc.infinia_vpc.id

  ingress {
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.infinia_deployment_name}-sg"
  }
}
