variable "aws_region" {
  description = "AWS region for ECR and the GitHub Actions IAM role."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name and mandatory project tag."
  type        = string
  default     = "cloud-engineer-assessment"
}

variable "environment" {
  description = "Environment represented by the shared image registry."
  type        = string
  default     = "shared"
}

variable "owner" {
  description = "Mandatory owner tag for accountability and cost allocation."
  type        = string
}

variable "ecr_repository_name" {
  description = "Name of the private ECR repository."
  type        = string
  default     = "cloud-engineer-assessment/assessment-api"
}

variable "github_repository" {
  description = "GitHub repository in owner/name format."
  type        = string
  default     = "TheInvincibleRalph/cloud-infra-assessment"
}

variable "github_branch" {
  description = "Only this branch may assume the GitHub Actions IAM role."
  type        = string
  default     = "master"
}

variable "github_subject_claim" {
  description = "Optional complete GitHub OIDC subject claim. Leave null for the conventional repository and branch claim."
  type        = string
  default     = null
  nullable    = true
}

variable "create_github_oidc_provider" {
  description = "Create the account-level GitHub OIDC provider. Set false when the account already has one."
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN when create_github_oidc_provider is false."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.create_github_oidc_provider || var.existing_github_oidc_provider_arn != null
    error_message = "existing_github_oidc_provider_arn is required when create_github_oidc_provider is false."
  }
}

