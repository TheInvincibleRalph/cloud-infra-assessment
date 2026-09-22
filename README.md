# Cloud and Infrastructure Engineer Assessment

This repository contains three independent tasks:

- [`task-1-iac/`](task-1-iac/README.md): highly available AWS infrastructure with Terraform.
- [`task-2-cicd/`](task-2-cicd/README.md): tested and scanned container delivery to Amazon ECR.
- [`task-3-scripting/`](task-3-scripting/README.md): Bash HTTP health checker with retries and JSON output.

## Prerequisites

- AWS account and AWS CLI v2
- Terraform 1.10+
- Docker
- Go 1.25+
- Bash, `curl`, `jq`, and `awk`
- GitHub repository access

Each task README contains its setup, design decisions, assumptions, and cleanup commands.

Do not commit credentials, `*.tfstate`, `*.tfvars`, `backend.hcl`, or Terraform plan files. Provider `.terraform.lock.hcl` files should be committed.

