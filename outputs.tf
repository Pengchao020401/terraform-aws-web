output "alb_dns_name" {
  description = "Nom DNS de l'ALB"
  value       = aws_lb.this.dns_name
}

output "alb_url" {
  description = "URL a ouvrir dans le navigateur"
  value       = "http://${aws_lb.this.dns_name}"
}

output "alb_arn" {
  description = "ARN de l'ALB"
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN du target group"
  value       = aws_lb_target_group.this.arn
}

output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "Identifiant du Launch Template"
  value       = aws_launch_template.this.id
}

output "alb_security_group_id" {
  description = "Security Group de l'ALB"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "Security Group des instances web"
  value       = aws_security_group.web.id
}
