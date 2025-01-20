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

# Deploy Infinia SDS Instances with IAM Instance Profile
resource "aws_instance" "infinia" {
  count         = var.num_infinia_instances
  ami           = var.infinia_ami_id
  instance_type = var.instance_type_infinia
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name

  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  root_block_device {
    volume_size           = 256
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-sn-${format("%02d", count.index)}"
  }
}

# Deploy Client Instances with IAM Instance Profile
resource "aws_instance" "client" {
  count         = var.num_client_instances
  ami           = var.client_ami_id
  instance_type = var.instance_type_client
  subnet_id     = element(var.subnet_ids, count.index % length(var.subnet_ids))
  security_groups = [var.security_group_id]
  key_name      = var.key_pair_name

  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  root_block_device {
    volume_size           = 256
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
  }
}


# resource "aws_lb" "internal_lb" {
#   name               = "${var.infinia_deployment_name}-lb"
#   internal           = true
#   load_balancer_type = "network"
#   security_groups    = [var.security_group_id]
#   subnets            = var.subnet_ids
#   enable_deletion_protection = false
#   tags = { Name = "${var.infinia_deployment_name}-lb" }
# }

# resource "aws_lb_target_group" "infinia_tg" {
#   name        = "${var.infinia_deployment_name}-tg"
#   port        = 8111
#   protocol    = "TCP"
#   vpc_id      = var.vpc_id

#   health_check {
#     port               = "8111"
#     protocol           = "TCP"
#     interval           = 10
#     timeout            = 5
#     unhealthy_threshold = 3
#     healthy_threshold   = 2
#   }

#   tags = { Name = "${var.infinia_deployment_name}-tg" }
# }

# resource "aws_lb_listener" "infinia_listener" {
#   load_balancer_arn = aws_lb.internal_lb.arn
#   port              = 8111
#   protocol          = "TCP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.infinia_tg.arn
#   }

#   tags = { Name = "${var.infinia_deployment_name}-listener" }
# }

# resource "aws_lb_target_group_attachment" "infinia_tg_attachments" {
#   count            = length(aws_instance.infinia)
#   target_group_arn = aws_lb_target_group.infinia_tg.arn
#   target_id        = aws_instance.infinia[count.index].id
# }
