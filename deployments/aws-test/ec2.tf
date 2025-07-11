resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${var.infinia_deployment_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_iam_role" "ssm_role" {
  name = "${var.infinia_deployment_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_instance" "infinia" {
  count         = var.num_infinia_instances
  ami           = var.infinia_ami_id
  instance_type = var.instance_type_infinia
  #   key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id                   = aws_subnet.private.id
  security_groups             = [aws_security_group.infinia_sg.id]
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.root_device_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  dynamic "ebs_block_device" {
    for_each = var.use_ebs_volumes ? range(var.num_ephemeral_devices) : []
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

resource "aws_ec2_instance_state" "infinia_grouped_instances" {
  for_each    = { for i, inst in aws_instance.infinia : i => inst.id }
  instance_id = each.value
  state       = "running"
}


resource "aws_lb" "internal_nlb" {
  name               = "${var.infinia_deployment_name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.private.id]
}

resource "aws_lb_target_group" "nlb_target_group" {
  name     = "${var.infinia_deployment_name}-tg"
  port     = 8111
  protocol = "TCP"
  vpc_id   = aws_vpc.infinia_vpc.id
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.internal_nlb.arn
  port              = 8111
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_target_group.arn
  }
}

resource "aws_lb_target_group_attachment" "infinia_attachments" {
  for_each = { for i, inst in aws_instance.infinia : i => inst }

  target_group_arn = aws_lb_target_group.nlb_target_group.arn
  target_id        = each.value.id
  port             = 8111
}
