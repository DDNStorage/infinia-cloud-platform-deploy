# Create an Internal Hosted Zone
resource "aws_route53_zone" "internal_zone" {
  name = var.domain_name
  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "${var.infinia_deployment_name}-internal-hosted-zone"
  }
}

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
    volume_size           = 150
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-cn-${format("%02d", count.index)}"
  }
}

# Request ACM Certificate
resource "aws_acm_certificate" "internal_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.infinia_deployment_name}-internal-cert"
  }
}

# DNS Validation for ACM Certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.internal_cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.internal_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 300
}

# Wait for DNS Validation
resource "aws_acm_certificate_validation" "internal_cert_validation" {
  certificate_arn         = aws_acm_certificate.internal_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  depends_on = [aws_route53_record.cert_validation]
}

# Create an Internal Network Load Balancer
resource "aws_lb" "internal_lb" {
  name               = "${var.infinia_deployment_name}-lb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.infinia_deployment_name}-lb"
  }
}

# Target Group for Infinia Instances
resource "aws_lb_target_group" "infinia_tg" {
  name        = "${var.infinia_deployment_name}-tg"
  port        = 443
  protocol    = "TLS"
  vpc_id      = var.vpc_id

  health_check {
    port               = "443"
    protocol           = "TCP"
    interval           = 10
    timeout            = 5
    unhealthy_threshold = 3
    healthy_threshold   = 2
  }

  tags = {
    Name = "${var.infinia_deployment_name}-tg"
  }
}

# HTTPS Listener for the Load Balancer
resource "aws_lb_listener" "infinia_https_listener" {
  load_balancer_arn = aws_lb.internal_lb.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.internal_cert_validation.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.infinia_tg.arn
  }

  tags = {
    Name = "${var.infinia_deployment_name}-https-listener"
  }
}

# Attach Infinia Instances to the Target Group
resource "aws_lb_target_group_attachment" "infinia_tg_attachments" {
  count            = length(aws_instance.infinia)
  target_group_arn = aws_lb_target_group.infinia_tg.arn
  target_id        = aws_instance.infinia[count.index].id
}

# DNS Record for Internal LB
resource "aws_route53_record" "internal_lb" {
  zone_id = aws_route53_zone.internal_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.internal_lb.dns_name
    zone_id                = aws_lb.internal_lb.zone_id
    evaluate_target_health = true
  }
}
