output "application_url" {
  description = "Public URL of the load-balanced application."
  value       = "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name assigned to the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "vpc_id" {
  description = "ID of the application VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the load balancer."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the Auto Scaling group."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "autoscaling_group_name" {
  description = "Name of the application Auto Scaling group."
  value       = aws_autoscaling_group.app.name
}

