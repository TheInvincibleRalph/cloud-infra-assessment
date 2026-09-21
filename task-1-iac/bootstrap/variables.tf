variable "aws_region" {
  description = "AWS region in which to create the Terraform backend resources."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63
    error_message = "state_bucket_name must contain between 3 and 63 characters."
  }
}

variable "project" {
  description = "Project tag applied to every taggable backend resource."
  type        = string
  default     = "cloud-engineer-assessment"
}

variable "environment" {
  description = "Environment tag applied to every taggable backend resource."
  type        = string
  default     = "shared"
}

variable "owner" {
  description = "Owner tag used for accountability and cost allocation."
  type        = string
}
