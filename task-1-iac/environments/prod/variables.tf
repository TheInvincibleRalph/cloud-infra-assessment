variable "aws_region" {
  description = "AWS region used for the application stack."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name and mandatory project tag."
  type        = string
  default     = "cloud-engineer-assessment"
}

variable "environment" {
  description = "Deployment environment and mandatory environment tag."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Mandatory owner tag for accountability and cost allocation."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR range for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type used by the application Auto Scaling group."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Private port on which the web application listens."
  type        = number
  default     = 8080
}

variable "min_size" {
  description = "Minimum number of application instances. Two preserves multi-AZ capacity."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Normal application instance count."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of application instances during CPU-driven scaling."
  type        = number
  default     = 4
}

variable "cpu_target_percent" {
  description = "Average ASG CPU utilization that target tracking attempts to maintain."
  type        = number
  default     = 50
}

variable "enable_deletion_protection" {
  description = "Protect the load balancer from accidental deletion. Disabled for assessment cleanup."
  type        = bool
  default     = false
}

