output "ecr_repository_name" {
  description = "Value for the GitHub Actions ECR_REPOSITORY variable."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "Full private ECR repository URL."
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Value for the GitHub Actions AWS_ROLE_ARN secret."
  value       = aws_iam_role.github_actions.arn
}

output "aws_region" {
  description = "Value for the GitHub Actions AWS_REGION variable."
  value       = var.aws_region
}

