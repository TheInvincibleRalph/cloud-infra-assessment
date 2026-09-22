# Task 1: Highly Available AWS Web Application

## Overview

Terraform provisions a Python web application on private EC2 instances behind an AWS Application Load Balancer. AWS was selected because its VPC, ALB, Auto Scaling, S3, and EC2 services directly satisfy the requirements.

## Architecture

```text
                         Internet
                            |
                  Application Load Balancer
                  public subnet A + B
                       /          \
                      / HTTP 8080  \
        private subnet A        private subnet B
        EC2, no public IP       EC2, no public IP
                      \          /
                       Auto Scaling Group
                    min 2, desired 2, max 4
                      CPU target: 50%

Terraform state: encrypted, versioned S3 bucket
State locking: native S3 lock file
```

Two AZs are selected dynamically. One public and one private subnet are created in each AZ. The ALB uses both public subnets, while the ASG uses both private subnets.

## Setup and Deploy

Prerequisites: Terraform 1.10+, AWS CLI v2, and authenticated AWS credentials with VPC, EC2, ELB, Auto Scaling, and S3 permissions.

```bash
export AWS_PROFILE="terraform-project"
export AWS_REGION="us-east-2"
aws sts get-caller-identity
```

Create the remote-state bucket first:

```bash
cd task-1-iac/bootstrap
export TF_VAR_state_bucket_name="your-unique-terraform-state-bucket"
export TF_VAR_owner="your-name"
terraform init
terraform fmt -check
terraform validate
terraform plan 
terraform apply 
```

Configure and deploy production:

```bash
terraform init -backend-config=backend.hcl -reconfigure
terraform fmt -check
terraform validate
terraform plan 
terraform apply
terraform output -raw application_url
```

Verify:

[webapp](webapp.png)

## Design Decisions and Trade-offs

- **ALB and EC2 ASG:** Directly demonstrates load balancing, multi-AZ compute, health replacement, and CPU scaling.
- **Minimum two instances:** Preserves capacity across two AZs, but costs more than a single instance.
- **Private instances:** No public IPs; port `8080` accepts traffic only from the ALB security group.
- **No NAT Gateway:** Reduces assessment cost. The application is embedded in launch-template user data and needs no internet downloads.
- **User-data template:** Installs the visible `app/server.py` and systemd service on every replacement instance. A production system would normally use a Packer-built AMI or a versioned container image.
- **HTTP only:** A real production service should add Route 53, ACM, HTTPS redirect, WAF, logging, and monitoring.
- **S3 locking:** Uses `use_lockfile = true`; no DynamoDB table is required.

### How Multi-AZ Is Implemented

There is no single `multi_az = true` setting for this design. Multi-AZ behavior is produced by connecting four parts of the configuration:

1. `data.tf` discovers the Availability Zones available to the account in the selected region.
2. `locals.tf` selects the first two available zones.
3. `networking.tf` uses `for_each` to create one public and one private subnet in each selected zone.
4. `load-balancer.tf` places the ALB in both public subnets, while `autoscaling.tf` gives the ASG both private subnet IDs.

With `min_size = 2` and `desired_capacity = 2`, EC2 Auto Scaling balances the application instances across the two enabled Availability Zones. If an instance becomes unhealthy, the ASG replaces it; if an AZ is impaired, the load balancer can continue routing to healthy targets in the other AZ.

## Assumptions

- The region provides at least two AZs and supports `t3.micro`.
- Amazon Linux 2023 includes Python 3.
- A domain and TLS certificate were not supplied.
- The low-cost assessment does not require private-instance outbound internet or SSH.

## What I Would Add With More Time

- HTTPS, Route 53, AWS WAF, and stricter security headers.
- CloudWatch alarms, dashboards, ALB access logs, and centralized application logs.
- SSM Session Manager through VPC endpoints for private administration without SSH.
- Automated tests with `terraform test`, Checkov or tfsec, and Terratest.
- A CI workflow that runs format, validation, linting, security scanning, and reviewed plans.
- Separate reusable modules and isolated state per environment once a second environment justifies the abstraction.


## Cleanup

Destroy the application before the state backend:

```bash
cd task-1-iac/environments/prod
terraform destroy
```

The state bucket is intentionally protected by `prevent_destroy`. After confirming the application stack is gone and deciding that its state history is no longer needed, remove the `prevent_destroy` lifecycle block from `bootstrap/main.tf`, empty all object versions in the bucket, and then run:

```bash
cd ../../bootstrap
terraform destroy
```
