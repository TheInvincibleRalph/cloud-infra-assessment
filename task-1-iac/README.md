# Task 1: Highly Available AWS Web Application

## Overview

This task provisions a production-style web tier on AWS using Terraform. An internet-facing Application Load Balancer receives HTTP traffic and forwards it to a minimum of two EC2 instances managed by an Auto Scaling group in private subnets across two Availability Zones. The instances have no public IP addresses.

AWS was selected because its VPC, ALB, EC2 Auto Scaling, and S3 services provide direct, widely understood implementations of the assessment requirements.

## Repository Structure

```text
task-1-iac/
├── app/
│   ├── README.md                 # Application behavior and local run commands
│   └── server.py                 # Application deployed to each EC2 instance
├── bootstrap/
│   ├── main.tf                   # Creates the S3 remote-state bucket
│   ├── outputs.tf                # Prints the production backend configuration
│   ├── variables.tf
│   └── versions.tf
├── environments/
│   └── prod/
│       ├── autoscaling.tf        # ASG capacity and CPU target tracking
│       ├── backend.tf            # Declares the S3 backend
│       ├── backend.hcl.example   # Non-secret backend configuration example
│       ├── compute.tf            # EC2 launch template and app packaging
│       ├── data.tf               # Availability Zone and AMI lookups
│       ├── load-balancer.tf      # ALB, target group, listener, health check
│       ├── locals.tf             # Shared naming and mandatory tags
│       ├── networking.tf         # VPC, subnets, routes, Internet Gateway
│       ├── outputs.tf
│       ├── providers.tf
│       ├── security.tf           # ALB and application security groups
│       ├── terraform.tfvars.example
│       ├── user-data.sh.tftpl    # Installs app and creates systemd service
│       ├── variables.tf
│       └── versions.tf
└── README.md                     # Architecture and complete operator guide
```

The application and infrastructure are separate on purpose. `app/server.py` is independently readable and runnable. Terraform packages that file into launch-template user data, allowing private instances to receive it without Git, S3 downloads, a NAT Gateway, or embedded source code hidden in a shell script.

Terraform loads every `.tf` file in `environments/prod/` as one configuration. The filenames organize the code for reviewers; they do not create separate deployments or control execution order. Terraform derives resource order from references such as `aws_vpc.main.id`, `aws_launch_template.app.id`, and `aws_lb_target_group.app.arn`.

## Architecture

```text
                              Internet
                                  |
                          HTTP :80 (public)
                                  |
                 +--------------------------------+
                 | Application Load Balancer      |
                 | public subnet A + public B     |
                 +---------------+----------------+
                                 |
                   HTTP :8080, ALB security group only
                                 |
          +----------------------+----------------------+
          |                                             |
  +-------v----------------+                    +-------v----------------+
  | Private subnet A       |                    | Private subnet B       |
  | EC2 instance           |                    | EC2 instance           |
  | no public IP           |                    | no public IP           |
  +------------------------+                    +------------------------+
          |                                             |
          +-------- EC2 Auto Scaling group -------------+
                   min=2, desired=2, max=4
                   target: 50% average CPU

  Terraform state: encrypted/versioned S3 bucket
  State locking:   native S3 lock file (`use_lockfile = true`)
```

The public subnets route to an Internet Gateway. The private route table deliberately has no internet default route, so application instances cannot be reached directly and do not need a NAT Gateway. The ALB reaches targets over the VPC's local route.

### How Multi-AZ Is Implemented

There is no single `multi_az = true` setting for this design. Multi-AZ behavior is produced by connecting four parts of the configuration:

1. `data.tf` discovers the Availability Zones available to the account in the selected region.
2. `locals.tf` selects the first two available zones.
3. `networking.tf` uses `for_each` to create one public and one private subnet in each selected zone.
4. `load-balancer.tf` places the ALB in both public subnets, while `autoscaling.tf` gives the ASG both private subnet IDs.

With `min_size = 2` and `desired_capacity = 2`, EC2 Auto Scaling balances the application instances across the two enabled Availability Zones. If an instance becomes unhealthy, the ASG replaces it; if an AZ is impaired, the load balancer can continue routing to healthy targets in the other AZ.

### Production Dependency Flow

```text
variables.tf + data.tf
          |
          v
      locals.tf
          |
          v
    networking.tf
       /       \
      v         v
security.tf  load-balancer.tf
      \         /
       v       v
       compute.tf
           |
           v
     autoscaling.tf
           |
           v
       outputs.tf
```

This is a conceptual reading order, not file execution order. At resource level, references create implicit dependencies. For example, a subnet references the VPC ID, the launch template references the application security group, and the ASG references the launch template, private subnets, and target group. Explicit `depends_on` blocks are unnecessary where those references already describe the dependency.

## What Terraform Creates

- One VPC with DNS support enabled.
- Two public and two private `/24` subnets across the first two available AZs.
- An Internet Gateway and public route table.
- A private route table with no internet route.
- An internet-facing Application Load Balancer in both public subnets.
- An ALB security group allowing public HTTP and an application security group allowing port `8080` only from the ALB.
- An EC2 launch template using the latest Amazon Linux 2023 x86-64 AMI, encrypted EBS, no public IP, and IMDSv2 enforcement.
- An Auto Scaling group spanning both private subnets with a minimum of two instances.
- A target-tracking scaling policy that maintains approximately 50% average CPU utilization.
- A visible, dependency-free Python application from `app/server.py`, installed by launch-template user data.
- A versioned, encrypted, private S3 state bucket with native S3 lock-file support.

All taggable resources inherit `project`, `environment`, `owner`, and `managed-by` tags. Auto Scaling tags explicitly propagate to instances because provider default tags alone do not satisfy ASG instance tag propagation.

## Requirement Coverage

- **Infrastructure as Code:** AWS infrastructure and backend bootstrap are fully declared in Terraform.
- **Application behind a load balancer:** The Python service runs on port `8080` behind an internet-facing ALB.
- **At least two Availability Zones:** Two public and two private subnets are created across two discovered AZs; both the ALB and ASG use those subnet pairs.
- **CPU-based auto scaling:** An ASG target-tracking policy maintains approximately 50% average CPU utilization between the configured minimum and maximum capacity.
- **Private application tier:** EC2 instances launch only in private subnets with `associate_public_ip_address = false`; application ingress is allowed only from the ALB security group.
- **Required tags:** `project`, `environment`, and `owner` are applied through provider default tags and propagated explicitly by the ASG.
- **Remote state and locking:** Production state is stored in a versioned, encrypted, private S3 bucket with native S3 lock files.

## Prerequisites

- Terraform 1.10 or later, which supports native S3 state locking.
- AWS CLI v2.
- An AWS account and credentials allowed to manage VPC, EC2, ELBv2, Auto Scaling, S3, and related IAM service-linked roles.
- A shell with `aws`, `terraform`, and `curl` available.

Authenticate without putting credentials in this repository. For example:

```bash
export AWS_PROFILE="your-profile"
export AWS_REGION="us-east-2"
aws sts get-caller-identity
```

If the profile was created with the newer browser-based `aws login` command, the AWS CLI may understand its `login_session` while the credential library used by the Terraform AWS provider does not. Configure a process-credential adapter once:

```bash
aws configure set credential_process \
  "aws configure export-credentials --profile project --format process" \
  --profile terraform-project
aws configure set region us-east-2 --profile terraform-project
```

Then clear stale environment credentials, select the adapter profile, and verify it before using Terraform:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE
export AWS_PROFILE="terraform-project"
export AWS_REGION="us-east-2"
aws sts get-caller-identity
```

The adapter asks the AWS CLI to export short-lived credentials from the browser login session. No access key, secret key, or session token belongs in this repository.

## Deploy From Scratch

### 1. Create the remote-state backend

S3 bucket names are globally unique. Choose a unique lowercase name and set your owner value:

```bash
cd task-1-iac/bootstrap
export TF_VAR_state_bucket_name="your-name-cloud-assessment-tfstate"
export TF_VAR_owner="your-name-or-email"
terraform init
terraform fmt -check
terraform validate
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output -raw backend_configuration
```

The bootstrap stack starts with local state because the remote bucket cannot be used before it exists. Its four S3 resources create the bucket, enable versioning, configure server-side encryption, and block public access. The bucket has `prevent_destroy` to reduce the chance of accidentally deleting the production state history.

Copy the example and replace its bucket value with the `state_bucket_name` output:

```bash
cd ../environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Edit the local `backend.hcl` and `terraform.tfvars`. Both are gitignored. The only required application variable is `owner`.

`backend.tf` and `backend.hcl` have separate responsibilities:

- `backend.tf` is committed and declares that the production root uses an S3 backend.
- `backend.hcl` is local and supplies the existing bucket name, state object key, region, encryption setting, and `use_lockfile = true`.
- `backend.hcl` does not create the bucket. The bootstrap stack creates it first.
- `terraform.tfvars` supplies normal infrastructure inputs and cannot configure the backend.

### 2. Deploy the application stack

```bash
terraform init -backend-config=backend.hcl -reconfigure
terraform fmt -check
terraform validate
terraform plan -var-file=terraform.tfvars -out=prod.tfplan
terraform apply prod.tfplan
terraform output -raw application_url
```

Allow several minutes for EC2 bootstrapping and ALB health checks, then test the URL:

```bash
curl "$(terraform output -raw application_url)"
curl "$(terraform output -raw application_url)/health"
```

Refresh the page several times. The hostname should alternate as the ALB distributes requests between healthy instances.

## Verification in AWS

Use these checks during the walkthrough:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(terraform output -raw autoscaling_group_name)"

aws ec2 describe-instances \
  --filters "Name=tag:project,Values=cloud-engineer-assessment" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}'
```

Expected result: at least two running instances are distributed across two AZs, have private addresses, and show `null` public addresses. In the EC2 console, the target group should show both instances as healthy. The Auto Scaling policy should show `ASGAverageCPUUtilization` with a target of 50.

## Key Decisions and Trade-offs

**ALB plus EC2 Auto Scaling:** This is the clearest AWS-native interpretation of load balancing, multi-AZ compute, and CPU scaling. A container platform would be valid but would add control-plane and operational concepts that the task does not require.

**Two instances at minimum:** A single desired instance could move between AZs but would not be highly available during an instance or AZ failure. A minimum and desired capacity of two gives simultaneous multi-AZ capacity. This has a small hourly cost.

**No NAT Gateway:** NAT Gateway pricing is disproportionately high for a small assessment. The app is self-contained in user data and needs no package download, so private instances need no outbound internet. In a fuller production platform, I would add one NAT Gateway per AZ for resilient egress or use VPC endpoints for the specific AWS services required.

**Visible application plus a user-data template:** The deployable application lives in `app/server.py`, where reviewers can run and inspect it independently. `compute.tf` base64-encodes that source and passes it, along with the port, project, and environment, into `user-data.sh.tftpl`. At boot, cloud-init renders and executes the script, which writes the application to `/opt/assessment-app`, creates a systemd service, enables restart behavior, and starts the server. Every instance created or replaced by the ASG therefore configures itself identically.

The template is used instead of an inline Terraform heredoc to keep three responsibilities clear: Terraform provisions AWS resources, the shell template configures the operating system, and Python implements the application. A plain shell file would work for fixed values, but `.tftpl` allows Terraform to inject deployment-specific values without duplicating the script.

**Why not containers:** ECS with an ECR image would provide stronger artifact versioning and rolling application deployments, but it would also require task definitions, execution roles, an ECS service, image publishing, and either NAT or VPC endpoints for private image pulls. That is a good next-stage production design, but it adds cost and concepts that are not required to demonstrate this task's EC2 Auto Scaling requirement.

**Why not a custom AMI:** A Packer-built immutable AMI would make instance startup faster and less dependent on boot-time scripting. It is the preferred direction for a larger EC2 platform, but it requires an image build pipeline, AMI versioning, and image cleanup. For this small dependency-free application, user data is easier for an evaluator to reproduce from one repository.

**Why not download the app from S3:** A separate artifact bucket would keep user data smaller, but instances would need an IAM instance profile plus either an S3 VPC endpoint or outbound NAT access. Embedding this small application avoids those extra resources. The approach should be reconsidered before the user-data payload approaches EC2's size limit or the application gains dependencies.

**Why not configuration management:** Ansible or a similar tool would introduce inventory, connectivity, and orchestration concerns for private, dynamically replaced instances. Self-bootstrapping instances fit the ASG lifecycle more naturally for this scope.

**HTTP only:** TLS requires a domain and ACM certificate that were not supplied. Production internet traffic should use an HTTPS listener with an ACM certificate, redirect port 80 to 443, and add Route 53 DNS.

**Native S3 state locking:** S3 versioning protects state history, encryption protects data at rest, public access is blocked, and `use_lockfile = true` prevents concurrent state writers without an additional database. The backend lives in a separate root because Terraform cannot use an S3 backend before its bucket exists. The bucket has `prevent_destroy` to protect critical state.

**First two available AZs:** Discovering AZs avoids hard-coding account-specific zone names. For stricter production control, I would pass an approved AZ list as input and consider three AZs.

## Assumptions

- The selected region exposes at least two Availability Zones and supports `t3.micro`.
- Amazon Linux 2023 continues to include `/usr/bin/python3` and the `nobody` user/group.
- The assessment is demonstrated over HTTP because no domain or certificate was provided.
- The evaluator accepts a low-cost implementation that omits NAT and administrative SSH access.
- AWS credentials are supplied through the standard credential chain and never through Terraform variables.

## Cost Considerations

This design avoids NAT Gateway, container registry, orchestration, and database costs. It is still not guaranteed to be free: the Application Load Balancer, EC2 instances, EBS volumes, and public IPv4 usage can incur hourly or usage-based charges. S3 state storage is normally negligible at this scale. Resources should be destroyed promptly after evaluation, and actual pricing should be checked for the chosen AWS region and account free-tier eligibility.

## What I Would Add With More Time

- HTTPS, Route 53, AWS WAF, and stricter security headers.
- CloudWatch alarms, dashboards, ALB access logs, and centralized application logs.
- SSM Session Manager through VPC endpoints for private administration without SSH.
- Automated tests with `terraform test`, Checkov or tfsec, and Terratest.
- A CI workflow that runs format, validation, linting, security scanning, and reviewed plans.
- Separate reusable modules and isolated state per environment once a second environment justifies the abstraction.

## Cleanup

Destroy the application stack first because its state depends on the remote backend:

```bash
cd task-1-iac/environments/prod
terraform destroy -var-file=terraform.tfvars
```

The state bucket is intentionally protected by `prevent_destroy`. After confirming the application stack is gone and deciding that its state history is no longer needed, remove the `prevent_destroy` lifecycle block from `bootstrap/main.tf`, empty all object versions in the bucket, and then run:

```bash
cd ../../bootstrap
terraform destroy
```

Keeping backend deletion deliberate reduces the risk of losing the only record Terraform has of managed infrastructure.

## Walkthrough Talking Points

1. Start at the request path: internet to ALB, then security-group-restricted traffic to private targets.
2. Show that each subnet pair spans two discovered AZs and that only public subnets have an Internet Gateway route.
3. Explain that the ASG maintains two healthy instances and replaces failures; target tracking changes desired capacity around the CPU target.
4. Show the launch template controls: no public IP, IMDSv2, encrypted disk, and repeatable bootstrap script.
5. Explain the state bootstrap sequence, S3 safeguards, and native `.tflock` concurrency control.
6. Close with the deliberate cost/security trade-offs: no NAT, no SSH, and HTTP pending a real domain and certificate.
