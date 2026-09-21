output "state_bucket_name" {
  description = "S3 bucket to place in the production backend configuration."
  value       = aws_s3_bucket.terraform_state.id
}

output "backend_configuration" {
  description = "Values to copy into environments/prod/backend.hcl."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "task-1-iac/prod/terraform.tfstate"
    region         = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
