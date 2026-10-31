# ---------------------------------------------------------------------------------------------
# Module terraform-aws-web : ALB + target group + listener + Launch Template + ASG.
# Toutes les ressources s'appellent "this" (convention du cours).
# Pas de SSH : aucun port 22 nulle part, pas de key_pair.
# Les lignes "checkov:skip" documentent les resultats de scan que l'on accepte, avec la raison.
# ---------------------------------------------------------------------------------------------

locals {
  tags = merge(var.tags, { Module = "terraform-aws-web" })
}

# --- Security Group de l'ALB : le monde entier peut parler a l'ALB sur le port 80 ---------------
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "ALB ${var.name} : HTTP depuis Internet"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-alb" })

  # Un SG ne peut pas etre supprime tant qu'il est utilise : on cree le nouveau avant de detruire l'ancien.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Un load balancer public doit accepter le port 80 depuis Internet (0.0.0.0/0) ; HTTPS = extension possible
  security_group_id = aws_security_group.alb.id
  description       = "HTTP depuis Internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# L'ALB ne parle qu'aux instances (SG web), sur le port 80.
resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP vers les instances web"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.web.id
}

# --- Security Group des instances : port 80 UNIQUEMENT depuis le SG de l'ALB ---------------------
resource "aws_security_group" "web" {
  name_prefix = "${var.name}-web-"
  description = "Instances web ${var.name} : HTTP depuis ALB seulement, pas de SSH"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-web" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  #checkov:skip=CKV_AWS_260:Faux positif : la regle n'a aucun CIDR, la source est le Security Group de l'ALB (referenced_security_group_id)
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP depuis ALB (reference au SG, pas de CIDR)"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

# Sortie : HTTP (apt) et HTTPS (apt, API SSM). Pas de NAT : les instances sortent par l'Internet Gateway.
# Le DNS (resolveur du VPC) et le service de temps AWS ne passent pas par les Security Groups.
resource "aws_vpc_security_group_egress_rule" "web_http_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP sortant (apt)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS sortant (apt, API SSM Parameter Store)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --- ALB, target group, listener -----------------------------------------------------------------
resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Pas de protection contre la suppression : le Learner Lab impose un terraform destroy apres chaque session
  #checkov:skip=CKV_AWS_91:Pas de logs d'acces : demanderait un bucket S3 avec une policy dediee, hors perimetre du socle
  #checkov:skip=CKV2_AWS_20:Pas de redirection 80 vers 443 : il n'y a pas de listener HTTPS (extension optionnelle)
  #checkov:skip=CKV2_AWS_28:Pas de WAF devant l'ALB : cout et hors perimetre du socle
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false #tfsec:ignore:aws-elb-alb-not-public -- l'ALB est le point d'entree public voulu
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:Le trafic ALB -> instances reste en HTTP (port 80) : le TLS s'arrete a l'ALB si on choisit l'extension HTTPS
  name     = "${var.name}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${var.name}-web" })
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Listener HTTP voulu par le socle (port 80) ; HTTPS et redirection = extension optionnelle
  #checkov:skip=CKV_AWS_103:Sans objet : pas de TLS sur ce listener
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.tags
}

# --- Launch Template : le "moule" des instances --------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = base64encode(var.user_data)
  ebs_optimized          = true
  update_default_version = true

  iam_instance_profile {
    name = var.instance_profile_name
  }

  # IMDSv2 obligatoire : sans jeton de session, le service de metadonnees refuse la requete (protege contre le vol
  # de credentials par SSRF). Hop limit 1 : un conteneur ou un proxy sur la machine ne peut pas atteindre l'IMDS.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = var.root_device_name

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-web", Role = "web" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-web" })
  }

  tags = merge(local.tags, { Name = "${var.name}-web" })
}

# --- ASG : garde au moins 2 instances en vie, reparties sur 2 zones ------------------------------
resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-web"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [aws_lb_target_group.this.arn]

  # "ELB" : l'ASG remplace une instance si le target group la juge malade (le site ne repond plus),
  # pas seulement si la machine EC2 est arretee (type "EC2").
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # Le terraform apply attend que min_size instances soient saines dans l'ALB : si l'apply est vert, le site repond.
  wait_for_elb_capacity     = var.min_size
  wait_for_capacity_timeout = "10m"

  launch_template {
    id = aws_launch_template.this.id
    # Numero de version precis (pas "$Latest") : quand le Launch Template change, ce numero change
    # et Terraform declenche l'instance refresh ci-dessous.
    version = aws_launch_template.this.latest_version
  }

  # Remplacement progressif des instances quand le Launch Template change (nouveau user_data, nouvelle AMI...).
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-web"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
