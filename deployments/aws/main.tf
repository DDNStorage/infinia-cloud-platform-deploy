# Deploy Infinia SDS Instances
resource "aws_instance" "infinia" {
  count         = var.num_infinia_instances
  ami           = var.infinia_ami_id
  instance_type = var.instance_type_infinia
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name

  root_block_device {
    volume_size           = 150
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-sn-${format("%02d", count.index)}"
  }
}

# Deploy Client Instances
resource "aws_instance" "client" {
  count         = var.num_client_instances
  ami           = var.client_ami_id
  instance_type = var.instance_type_client
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name

  root_block_device {
    volume_size           = 150 # Set root volume size to 150 GB
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
  }
}

# Deploy Load Balancer Instance
resource "aws_instance" "load_balancer" {
  ami           = var.client_ami_id
  instance_type = "t3.medium"
  subnet_id     = element(var.subnet_ids, 0)
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name

  root_block_device {
    volume_size           = 150
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-nginx"
  }
}


