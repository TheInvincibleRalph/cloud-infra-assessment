# Task 2: Container CI/CD Pipeline

## Overview

A small Go REST API is tested, built as a non-root multi-stage image, scanned with Trivy, and pushed to Amazon ECR by GitHub Actions. Go was selected because it produces a small static binary and makes the build/runtime stage separation clear.

Endpoints: `GET /`, `GET /health`, and `GET /api/version`.

## Pipeline Flow

```text
Push to delivery branch
        |
     Go tests
        |
 Multi-stage image build
        |
 Trivy HIGH/CRITICAL gate
        |
 GitHub OIDC -> AWS role
        |
 Push commit-SHA image to ECR
```

The ECR push is last, so failed tests, builds, or scans cannot publish an image.

## Setup and Run

Prerequisites: Go 1.25+, Docker, Trivy, Terraform 1.10+, AWS CLI v2, and GitHub CLI.

Run locally:

```bash
cd task-2-cicd
make test
make build IMAGE_TAG=local
make scan IMAGE_TAG=local
make run IMAGE_TAG=local
```

Provision ECR and the GitHub OIDC role:

```bash
cd infra
export AWS_PROFILE="terraform-project"
export TF_VAR_owner="Raphael Adesegun"
export TF_VAR_github_repository="TheInvincibleRalph/cloud-infra-assessment"
export TF_VAR_github_subject_claim="repo:TheInvincibleRalph@139259364/cloud-infra-assessment@1380336660:ref:refs/heads/main"
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Configure GitHub Actions:

```bash
gh secret set AWS_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
gh variable set AWS_REGION --body "$(terraform output -raw aws_region)"
gh variable set AWS_ACCOUNT_ID --body "$(aws sts get-caller-identity --query Account --output text)"
gh variable set ECR_REPOSITORY --body "$(terraform output -raw ecr_repository_name)"
```

OR

In **Settings > Secrets and variables > Actions**, configure one repository secret:

- `AWS_ROLE_ARN`: Terraform output `github_actions_role_arn`.

Configure three repository variables:

- `AWS_REGION`: Terraform output `aws_region`.
- `AWS_ACCOUNT_ID`: the expected 12-digit AWS account ID.
- `ECR_REPOSITORY`: Terraform output `ecr_repository_name`.

The workflow file is `.github/workflows/task-2-cicd.yml`.


## Pipeline Blockers Solved

The pipeline initially failed at the AWS authentication step with:

```text
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

GitHub Actions successfully created an OIDC token, but AWS rejected it because the token's `sub` claim did not exactly match the IAM role trust policy. The original policy expected GitHub's older name-based subject:

```text
repo:TheInvincibleRalph/cloud-infra-assessment:ref:refs/heads/main
```

New GitHub repositories use an immutable subject containing the permanent numeric owner and repository IDs:

```text
repo:TheInvincibleRalph@139259364/cloud-infra-assessment@1380336660:ref:refs/heads/main
```

I retrieved those IDs from the GitHub repository metadata and then supplied the exact immutable subject to Terraform:

```bash
export TF_VAR_github_subject_claim="repo:TheInvincibleRalph@139259364/cloud-infra-assessment@1380336660:ref:refs/heads/main"
terraform plan
terraform apply
```

## Promotion to Production

Deploy the commit-SHA image to staging, run acceptance tests, require approval, and deploy the same ECR digest (`repository@sha256:...`) to production. Do not rebuild between staging and production.

## Design Decisions and Trade-offs

- **Multi-stage Distroless image:** Final image contains only the Go binary and runs as `nonroot`; debugging is less convenient because there is no shell.
- **Trivy before push:** Fixable HIGH/CRITICAL findings fail the workflow. ECR scan-on-push provides additional registry visibility.
- **GitHub OIDC:** Uses short-lived credentials instead of permanent AWS keys, but requires an IAM provider and trust policy.
- **Immutable SHA tags:** Provide source traceability and prevent overwrites.
- **Sequential pipeline:** Keeps the success-only push rule obvious; a larger pipeline could parallelize independent checks.

With more time, add a real staging deployment, protected production environment, SBOM, provenance, and image signing.

## Assumptions

- Publishing a verified image to ECR satisfies the deployment requirement.
- GitHub-hosted runners can access public base images and vulnerability databases.
- The GitHub OIDC provider is created once per AWS account or an existing ARN is supplied.

## Cleanup

Delete images, then destroy the Terraform stack:

```bash
aws ecr list-images \
  --repository-name cloud-engineer-assessment/assessment-api \
  --query 'imageIds[*]' --output json > /tmp/task-2-images.json
aws ecr batch-delete-image \
  --repository-name cloud-engineer-assessment/assessment-api \
  --image-ids file:///tmp/task-2-images.json
cd task-2-cicd/infra
terraform destroy
```


## What I Would Add With More Time

- A real staging target and smoke-test job.
- A protected production environment and digest-promotion workflow.
- SBOM generation, provenance attestations, and Cosign image signing.
- Dependabot and action references pinned to full commit SHAs.
- Static analysis, license policy, and secret scanning.
- Multi-architecture images when both AMD64 and ARM64 runtimes are needed.

Do not delete the GitHub OIDC provider if another repository uses it.
