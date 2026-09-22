# Task 2: Container Build and Delivery Pipeline

## Overview

This task provides a small Go REST API and a GitHub Actions pipeline that tests it, builds a non-root multi-stage container image, blocks images with fixable `HIGH` or `CRITICAL` vulnerabilities, and pushes successful commit-addressed images to Amazon ECR.

Go was selected because it produces a self-contained binary, makes the multi-stage build meaningful, supports dependency-free unit testing, and allows the runtime image to contain no compiler, package manager, shell, or language runtime.

## Repository Structure

```text
task-2-cicd/
├── cmd/api/main.go                  # Process startup and graceful shutdown
├── internal/httpapi/
│   ├── handler.go                   # HTTP routes
│   └── handler_test.go              # Unit tests using httptest
├── infrastructure/                  # ECR and GitHub OIDC IAM role
├── .dockerignore
├── Dockerfile                       # Test, build, and non-root runtime stages
├── Makefile                         # Local developer commands
├── go.mod
└── README.md

.github/workflows/task-2-cicd.yml    # Root location required by GitHub
```

## Application

The API listens on `PORT`, defaulting to `8080`:

- `GET /` returns the service name and build version.
- `GET /health` returns `{"status":"healthy"}`.
- `GET /api/version` returns the version injected during image compilation.

The server defines request timeouts and handles `SIGINT` and `SIGTERM` for graceful shutdown. Handlers are independent from the network listener, so tests use Go's fast in-memory `httptest` package.

## Pipeline Flow

```text
Push to main or manual dispatch
              |
              v
      Run Go unit tests
              |
              v
 Build multi-stage container image
              |
              v
 Trivy scan: HIGH and CRITICAL
              |
       failure stops pipeline
              |
              v
 Assume AWS role through GitHub OIDC
              |
              v
 Push commit-SHA image to ECR
```

The push step is last, so failed tests, builds, or vulnerability scans cannot publish an image. The job receives permission to request a GitHub OIDC token and exchanges it for short-lived AWS credentials; no AWS access keys are stored in GitHub.

## Requirement Coverage

- The `Dockerfile` uses separate test/build stages and a Distroless runtime stage.
- The final stage declares `USER nonroot:nonroot` and contains only the compiled binary.
- Three unit tests cover health, version, and unknown-route behavior.
- The workflow runs on every push to `main` and can also be dispatched manually.
- Trivy exits with code 1 when a fixable `HIGH` or `CRITICAL` vulnerability is found.
- AWS authentication and ECR push occur only after all earlier gates succeed.
- Successful images use immutable full Git commit SHA tags.
- Promotion reuses the tested image digest rather than rebuilding source.

## Docker Design

The Dockerfile has three named stages:

1. `test` copies the source and runs `go test -race ./...`.
2. `build` compiles a static Linux binary and injects the Git commit as its version.
3. `runtime` copies only that binary into Distroless and runs it as the built-in non-root user.

CI also runs tests before `docker build`. This duplication gives fast, visible test feedback while ensuring that a direct local image build cannot bypass tests.

The runtime has no shell, compiler, source, or package manager. This reduces size and attack surface, but interactive debugging is intentionally limited; production debugging should use logs, metrics, traces, or an ephemeral debug container.

## Prerequisites

- Go 1.25 or later.
- Docker with BuildKit.
- Trivy for local vulnerability scanning.
- Terraform 1.10 or later and AWS CLI v2 for provisioning ECR and IAM.
- AWS permissions to manage ECR, IAM roles/policies, and the account-level GitHub OIDC provider.
- A GitHub repository whose delivery branch is `main`.

## Run Locally

```bash
cd task-2-cicd
make test
make build IMAGE_TAG=local
make scan IMAGE_TAG=local
make run IMAGE_TAG=local
```

In another terminal:

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/api/version
```

Confirm the configured runtime identity:

```bash
docker inspect assessment-api:local --format '{{.Config.User}}'
```

Expected output: `nonroot:nonroot`.

## Provision ECR and GitHub OIDC

The Terraform root under `infrastructure/` creates:

- A private AES-256 encrypted ECR repository with immutable tags.
- ECR scan-on-push as defense in depth alongside the blocking Trivy scan.
- A lifecycle rule retaining the newest 30 images.
- A GitHub OIDC identity provider when the account does not already have one.
- A branch-restricted IAM role allowed to push only to this ECR repository.

Authenticate to AWS, then run:

```bash
cd task-2-cicd/infrastructure
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file=terraform.tfvars -out=task-2.tfplan
terraform apply task-2.tfplan
terraform output
```

An AWS account can contain only one IAM OIDC provider for GitHub's token URL. If one already exists, set:

```hcl
create_github_oidc_provider       = false
existing_github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
```

The role's subject claim defaults to the repository and `main` branch. GitHub repositories using enhanced organization/repository ID claims can override `github_subject_claim` with the exact claim used by that repository.

## Configure GitHub

In **Settings > Secrets and variables > Actions**, configure one repository secret:

- `AWS_ROLE_ARN`: Terraform output `github_actions_role_arn`.

Configure three repository variables:

- `AWS_REGION`: Terraform output `aws_region`.
- `AWS_ACCOUNT_ID`: the expected 12-digit AWS account ID.
- `ECR_REPOSITORY`: Terraform output `ecr_repository_name`.

The workflow intentionally listens to `main`, as required. This repository currently uses `master`; rename and configure the default branch as `main` before expecting normal pushes to trigger it.

## Vulnerability Policy

Trivy scans the assembled local image before AWS authentication or push with severity `HIGH,CRITICAL`, `ignore-unfixed: true`, and `exit-code: 1`. A fixable high or critical vulnerability therefore fails the job. Unfixed findings remain visible but do not block because the team cannot remediate them directly; remove `ignore-unfixed` for a stricter policy that blocks every high or critical finding.

ECR scan-on-push is an additional registry-side signal, not the pipeline gate. Trivy is the gate because it can fail before publication.

## Staging-to-Production Promotion

Every successful image is tagged with the complete Git commit SHA. ECR tag immutability prevents overwriting that tag. Promotion should reuse the same digest:

1. Deploy the commit-SHA image to staging.
2. Run smoke, integration, and acceptance tests.
3. Require approval through a protected GitHub `production` environment.
4. Resolve and record the staging image digest from ECR.
5. Deploy the exact `repository@sha256:...` digest to production.
6. Record the digest, source commit, approver, and deployment result.

A separate release workflow should accept an existing digest, verify it passed staging, assume an environment-specific production role, and deploy it without invoking `docker build` again. This ensures production receives the exact artifact that was tested.

## Decisions and Trade-offs

**Go standard library:** Keeps dependencies and attack surface small. A larger API would likely add structured routing, validation, observability, and generated API documentation.

**Distroless runtime:** Provides a small non-root image without a shell or package manager. Security improves at the cost of interactive debugging convenience.

**OIDC instead of AWS keys:** Eliminates long-lived GitHub credentials. The trust policy is restricted to one repository and branch, but initial IAM federation setup is required.

**Immutable SHA tags:** Make releases traceable and prevent overwrites. Friendly release tags can be aliases, but deployments should record the digest.

**One sequential job:** Makes the success-only push rule unambiguous. Larger pipelines could parallelize independent checks while retaining a final gated publication job.

**Trivy plus ECR scanning:** Trivy blocks before publishing; ECR provides continuing registry visibility. The overlap is intentional defense in depth.

## Assumptions

- ECR and the OIDC role exist before the first workflow run.
- GitHub-hosted Ubuntu runners and public base images are allowed.
- `main` is the assessment delivery branch.
- The AWS account either has no GitHub OIDC provider or its existing ARN is supplied.
- Deployment to a runtime platform is outside this task; the required deployment action is publication of a verified deployable image to ECR.

## Cleanup

The ECR repository does not enable force deletion. Delete its images deliberately before destroying infrastructure:

```bash
aws ecr list-images \
  --repository-name cloud-engineer-assessment/assessment-api \
  --region us-east-2 \
  --query 'imageIds[*]' \
  --output json > /tmp/task-2-image-ids.json

aws ecr batch-delete-image \
  --repository-name cloud-engineer-assessment/assessment-api \
  --region us-east-2 \
  --image-ids file:///tmp/task-2-image-ids.json

cd task-2-cicd/infrastructure
terraform destroy -var-file=terraform.tfvars
```

If the OIDC provider is shared, provision this stack with `create_github_oidc_provider = false`; never delete a provider used by other repositories.

## What I Would Add With More Time

- A real staging target and smoke-test job.
- A protected production environment and digest-promotion workflow.
- SBOM generation, provenance attestations, and Cosign image signing.
- Dependabot and action references pinned to full commit SHAs.
- Static analysis, license policy, and secret scanning.
- Multi-architecture images when both AMD64 and ARM64 runtimes are needed.

