# iglu

Deploying an application using AWS ECS Fargate, RDS PostgreSQL, ECR, Terraform,
Jenkins, Nexus, SonarQube, Route 53, Datadog, Prometheus, and Grafana.

This project uses Jenkins, not GitHub Actions, to deploy the Terraform
infrastructure.

## Structure

- `Jenkinsfile` - Jenkins pipeline for Terraform plan/apply/destroy
- `create-remote-state.sh` - creates the Terraform S3 backend and DynamoDB lock table
- `delete-remote-state.sh` - deletes the Terraform remote state backend
- `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf` - development ECS root stack
- `terraform/modules/vpc` - reusable VPC module
- `terraform/modules/ecs_fargate` - reusable ECS Fargate module with optional Datadog sidecar
- `terraform/modules/jenkins_server` - Jenkins EC2 module
- `terraform/modules/monitoring_server` - Prometheus and Grafana EC2 module
- `terraform/modules/bastion_host` - hardened jump host with Session Manager and optional restricted SSH
- `terraform/modules/database` - private encrypted Multi-AZ RDS PostgreSQL
- `terraform/modules/ecr` - immutable, scan-on-push application image repository
- `terraform/modules/devops_tools` - private Nexus and SonarQube servers
- `terraform/environments/jenkins` - Jenkins bootstrap only: CI VPC, public ALB, and one private Jenkins controller
- `terraform/environments/tools` - shared pipeline services: bastion, Nexus, SonarQube/RDS, Prometheus, and Grafana
- `terraform/environments/prod` - production ECS environment

Run development Terraform commands directly from the `IGLU.COM` repository
root. Run Jenkins, tools, and production commands from their respective
directories under `terraform/environments`. The `terraform` directory itself
only contains modules and additional environments, so it is not a runnable
stack.

Before applying, confirm that the AWS credentials point to the intended account
and that these prerequisites exist:

- the S3 state bucket and DynamoDB lock table described below
- the public Route 53 hosted zone for `chijiokedevops.com`
- an x86_64 RHEL AMI in `us-east-1`
- a restricted public admin CIDR, normally your public IP followed by `/32`

## Remote State

Create the Terraform remote state backend first:

```sh
sh create-remote-state.sh
```

The backend uses:

- S3 bucket: `iglu-terraform-state`
- DynamoDB lock table: `iglu-terraform-locks`
- Region: `us-east-1`

## Jenkins

Create the remote-state backend, then bootstrap Jenkins:

```sh
cd terraform/environments/jenkins
terraform init
terraform plan
terraform apply
```

This stack creates only the CI network, a one-controller Auto Scaling Group
spanning both private subnets, encrypted EFS storage for `JENKINS_HOME`, its
two-AZ internet-facing Application Load Balancer, certificate, and DNS record.
The ASG is deliberately capped at one active controller to avoid Jenkins
split-brain, but can replace it in the other Availability Zone. EFS automatic
backups preserve controller configuration across replacement. The stack does
not create bastion, Nexus, SonarQube, RDS, monitoring, dev, or prod resources.
Terraform requests and DNS-validates an ACM certificate for Jenkins using the
existing public Route 53 zone. Public HTTP requests on port `80` redirect
permanently to HTTPS on port `443`.

To use an existing certificate instead, provide an ACM certificate from the
same region that covers the Jenkins hostname:

```sh
terraform apply \
  -var='jenkins_acm_certificate_arn=arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERTIFICATE_ID'
```

The Jenkins EC2 module uses a Red Hat Enterprise Linux AMI passed as a
variable. It does not look up AMIs with Terraform data blocks.

The stack intentionally runs one Jenkins controller. Restrict Jenkins access
to your own public IP:

```sh
terraform apply \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
```

Useful outputs:

```sh
terraform output jenkins_url
terraform output jenkins_dns_url
```

The Jenkins initial admin password is on the instance at:

```sh
/home/ec2-user/jenkins-initial-admin-password.txt
```

EC2 instances do not allow SSH. Resolve the current ASG member by tag and use
AWS Systems Manager Session Manager:

```sh
JENKINS_INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters Name=tag:Name,Values=iglu-jenkins-jenkins Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)
aws ssm start-session --target "$JENKINS_INSTANCE_ID" --region us-east-1
sudo cat /home/ec2-user/jenkins-initial-admin-password.txt
```

Create a Jenkins Pipeline job that uses `Jenkinsfile`.

Pipeline parameters:

- `ENVIRONMENT`: `dev` or `prod`; the shared tools stack is an automatic pipeline stage
- `ACTION`: `plan`, `apply`, or `destroy`
- `DESTROY_SHARED_TOOLS`: with `ACTION=destroy`, also destroy Nexus, SonarQube/RDS, Prometheus, Grafana, and the tools bastion; Jenkins is always retained
- `PRODUCTION_CONFIRMATION`: must be exactly `DEPLOY_PROD` for production apply or destroy
- `ENABLE_DATADOG`: enable the Datadog ECS Fargate sidecar
- `DATADOG_API_KEY_SECRET_ARN`: Secrets Manager ARN for the Datadog API key
- `DATADOG_API_KEY_SECRET_NAME`: optional API-key secret name override
- `DATADOG_APP_KEY_SECRET_NAME`: optional application-key secret name override
- `DATADOG_SITE`: Datadog site, for example `datadoghq.com`
- `MONITORING_AMI_ID`: optional Red Hat Enterprise Linux AMI ID override for the monitoring server; blank uses the Terraform environment default
- `ALLOWED_ADMIN_CIDR`: optional restricted public CIDR override for Grafana and Prometheus; blank uses the Terraform environment default

Bootstrapping Jenkins does not execute this pipeline, and the `Jenkinsfile`
declares no automatic trigger. Its safe defaults are `ENVIRONMENT=dev` and
`ACTION=plan`. Production apply or destroy additionally requires both Jenkins'
manual approval and the exact `PRODUCTION_CONFIRMATION=DEPLOY_PROD` value.
For `plan` and `apply`, the pipeline processes the shared tools stack first and
then the selected application environment. A selected-environment `destroy`
retains shared tools by default so deleting dev cannot disrupt tools also used
by prod. Select `DESTROY_SHARED_TOOLS` when those shared resources must also be
removed. The destroy flow disables RDS deletion protection before generating
fresh application and tools destroy plans. It deliberately retains the Jenkins
stack because the controller cannot reliably destroy the instance executing its
own pipeline; destroy `terraform/environments/jenkins` from an external
workstation or runner.
Concurrent builds of this pipeline job are disabled because dev and prod both
plan against the same locked tools state.

## Route 53 DNS

Route 53 records are enabled by default and use the following existing public
hosted zone:

```sh
chijiokedevops.com
```

Terraform creates:

- `jenkins.chijiokedevops.com` -> Jenkins application load balancer
- `grafana.chijiokedevops.com` -> shared Grafana service through the CI load balancer
- `prometheus.chijiokedevops.com` -> shared Prometheus service through the CI load balancer
- `nexus.chijiokedevops.com` -> shared Nexus service through the CI load balancer
- `sonar.chijiokedevops.com` -> shared SonarQube service through the CI load balancer
- `dev.chijiokedevops.com` -> dev application load balancer
- `grafana.dev.chijiokedevops.com` -> dev monitoring server
- `prometheus.dev.chijiokedevops.com` -> dev monitoring server
- `prod.chijiokedevops.com` -> prod application load balancer
- `grafana.prod.chijiokedevops.com` -> prod monitoring server
- `prometheus.prod.chijiokedevops.com` -> prod monitoring server

Each independent stack requests only the certificates it owns. The tools stack
adds its certificate and host rules to the Jenkins ALB after Jenkins exists.
Administrative host rules are restricted to the configured admin CIDR.
Backend traffic from load balancers to ECS or EC2 remains private HTTP.

Useful outputs:

```sh
terraform output jenkins_dns_url
terraform output dev_url
terraform output prod_url
```

Set `create_route53_record = false` only when DNS is managed externally, and
provide an existing `acm_certificate_arn` (or
`jenkins_acm_certificate_arn`) covering the configured hostnames.

The CI stack intentionally keeps one active Jenkins controller. Auto Scaling
provides host/AZ recovery rather than active-active Jenkins. Encrypted,
backed-up EFS keeps controller state durable; restoration and plugin upgrades
must still be tested regularly.

## Dev And Prod

Deploy dev:

```sh
# Run these commands from the IGLU.COM repository root.
terraform init
terraform plan \
  -var='monitoring_ami_id=ami-REPLACE_WITH_RHEL_AMI_ID' \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
terraform apply \
  -var='monitoring_ami_id=ami-REPLACE_WITH_RHEL_AMI_ID' \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
```

Deploy prod:

```sh
cd terraform/environments/prod
terraform init
terraform plan \
  -var='monitoring_ami_id=ami-REPLACE_WITH_RHEL_AMI_ID' \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
terraform apply \
  -var='monitoring_ami_id=ami-REPLACE_WITH_RHEL_AMI_ID' \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
```

Production additionally creates two isolated database subnets, one NAT gateway
per availability zone, a Session-Manager-enabled bastion host, an encrypted
Multi-AZ RDS PostgreSQL database, and an ECR repository. ECS tasks receive the
database endpoint plus credentials from Secrets Manager; credentials are not
stored in Terraform variables or container definitions.

Build and push each application image with an immutable release tag, then pass
the complete image URI to Terraform:

```sh
ECR_URL=$(terraform output -raw prod_ecr_repository_url)
aws ecr get-login-password --region us-east-1 | podman login --username AWS --password-stdin "${ECR_URL%%/*}"
podman build -t "$ECR_URL:release-GIT_SHA" .
podman push "$ECR_URL:release-GIT_SHA"
terraform apply -var="container_image=$ECR_URL:release-GIT_SHA"
```

## Shared Private CI/CD Services

After Jenkins is running, selecting either `dev` or `prod` in the pipeline
plans the tools stack first. `ACTION=apply` applies tools before it applies the
selected application environment:

```sh
terraform -chdir=terraform/environments/tools init
terraform -chdir=terraform/environments/tools plan
terraform -chdir=terraform/environments/tools apply
```

The tools stack reads network and load-balancer outputs from the Jenkins remote
state. It creates the bastion, Prometheus/Grafana, Nexus, SonarQube, and the
SonarQube PostgreSQL database. These shared resources continue to use
`tools/terraform.tfstate`; keeping a separate state prevents either dev or prod
from claiming ownership of them. The pipeline does not destroy shared tools
when one application environment is destroyed. Use the manual tools commands
only for an intentional shared-tools teardown or maintenance operation.

Docker Engine, Buildx, Compose, Maven, Podman, AWS CLI, Java, and pinned Checkov
remain installed on Jenkins because they are build executables, not additional
servers. The pipeline audits this toolchain before it plans shared tools and
the selected `dev` or `prod` environment.
An idempotent Systems Manager association installs or repairs this toolchain on
existing controllers and briefly restarts Jenkins to activate Docker group
membership; the EC2 controller is not replaced for this bootstrap change.
SonarQube uses a dedicated Multi-AZ PostgreSQL database; Nexus and SonarQube
data volumes are encrypted and retained when their instances are terminated.

Dev and prod run on ECS Fargate, so Docker is intentionally not installed on
application hosts: AWS manages the host container runtime. Docker is installed
only on Jenkins, where application images are built and pushed to ECR.

After the production stack creates ECR, allow Jenkins to push only to that
repository:

```sh
cd terraform/environments/jenkins
terraform apply \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32' \
  -var='ecr_repository_arns=["arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/iglu/prod/app"]'
```

The Jenkins environment currently sets `jenkins_attach_admin_policy = true`, so
its instance role receives AWS `AdministratorAccess` for Terraform deployments.
Any pipeline script or Jenkins administrator can therefore make account-wide
changes. Replace this with a scoped deployment role before treating the
environment as production-grade.
The instance role does receive least-privilege backend access: read-only access
to the Jenkins bootstrap state, read/write access to the dev, tools, and prod
state objects, and locking access to the Terraform DynamoDB table. Its pipeline
DNS policy permits hosted-zone discovery but restricts record changes to the
configured Route 53 hosted zone; ACM certificate lifecycle permissions are
separated from DNS permissions.

Administrative shell access uses Session Manager by default:

```sh
aws ssm start-session \
  --target "$(terraform -chdir=terraform/environments/tools output -raw bastion_instance_id)" \
  --region us-east-1
```

Setting `bastion_key_name` enables SSH only from `allowed_admin_cidr`.

## ECS Fargate Networking And Logs

The ECS Fargate module creates:

- an ALB target group with `target_type = "ip"` for Fargate tasks
- a CloudWatch log group at `/ecs/<project>-<environment>`
- ECS task logging through `awslogs`, or FireLens direct delivery when Datadog logs are enabled
- environment-safe resource names using `<project>-<environment>`

The VPC module creates a NAT Gateway and routes private subnets through it. This
allows Fargate tasks with `assign_public_ip = false` to pull container images,
send CloudWatch logs, read Secrets Manager values, and communicate with Datadog.

## Datadog For ECS Fargate

Datadog is integrated into the ECS Fargate task as an optional Agent sidecar.
Terraform creates environment-specific AWS Secrets Manager containers for both
Datadog credentials without putting their values in Terraform configuration or
state:

- `iglu/dev/datadog/api-key` and `iglu/dev/datadog/app-key`
- `iglu/prod/datadog/api-key` and `iglu/prod/datadog/app-key`

The Agent receives only the API key. The application key is retained for
Datadog API automation and is not exposed to ECS containers.

Bootstrap each environment in two safe steps. First create the infrastructure
and empty secret containers with the Agent disabled:

```sh
terraform apply -var='enable_datadog=false'
```

Populate the secret values outside Terraform. The helper prompts without
echoing the keys and avoids putting either value in Terraform state:

```sh
./set-datadog-secrets.sh dev
```

If a previous `terraform destroy` scheduled the Datadog secrets for deletion,
AWS reserves their names during the seven-day recovery window. Restore the
existing secrets and import them back into the correct Terraform state before
planning again:

```sh
./recover-datadog-secrets.sh dev
```

Use `prod` instead of `dev` for the production state. The recovery helper
cancels deletion only when necessary and skips imports for resources that are
already present in state.

Then enable and deploy the Agent sidecar and FireLens log router:

```sh
terraform plan -var='enable_datadog=true' -out=tfplan
terraform apply tfplan
```

After apply, print the Datadog login URL with `terraform output
dev_datadog_url` (or `terraform output prod_datadog_url` from the prod
directory). Sign in and filter containers or services by `env:dev` or
`env:prod`.

For production, run Terraform from `terraform/environments/prod` and invoke
`./set-datadog-secrets.sh prod` from the repository root between the two
applies. `datadog_api_key_secret_arn` remains available when an existing secret
is managed outside this stack; set `manage_datadog_secrets=false` when all
Datadog secret metadata is externally managed.

When deploying through Jenkins, set:

- `ENABLE_DATADOG`: `true`
- `DATADOG_API_KEY_SECRET_NAME`: blank for the environment-specific default
- `DATADOG_APP_KEY_SECRET_NAME`: blank for the environment-specific default
- `DATADOG_API_KEY_SECRET_ARN`: optional Secrets Manager ARN override
- `DATADOG_SITE`: your Datadog site

The Datadog sidecar is configured for ECS Fargate metrics and can receive APM
traffic from instrumented application containers. When log collection is
enabled, an AWS for Fluent Bit FireLens sidecar sends application logs directly
to Datadog using the API key from Secrets Manager. The Agent and log router send
their own operational logs to CloudWatch Logs.

You can change the Datadog site if needed:

```sh
terraform apply \
  -var='datadog_site=datadoghq.eu'
```

## Prometheus And Grafana

Each environment includes monitoring with:

- Prometheus behind an HTTPS ALB, with private backend port `9090`
- Grafana behind an HTTPS ALB, with private backend port `3000`
- Node Exporter for host metrics
- Blackbox Exporter for HTTP health checks
- Prometheus CloudWatch Exporter for ECS cluster/service metrics

Prometheus monitors:

- Jenkins ASG host metrics on port `9100`, discovered dynamically from EC2 tags
- Monitoring host metrics on port `9100`
- Jenkins public HTTPS health at `https://jenkins.chijiokedevops.com/login`
- ECS CPU, memory, and running-task metrics from CloudWatch/Container Insights
- Dev ECS application health through the dev ALB
- Prod ECS application health through the prod ALB
- Grafana web health on port `3000`
- Prometheus health on port `9090`

Grafana default login:

- Username: `admin`
- Password: `admin`

The ECS clusters enable Container Insights with enhanced observability.
Prometheus reads their CloudWatch metrics through the CloudWatch Exporter and
Grafana uses Prometheus as its default datasource. Datadog remains the
application/container telemetry path when `ENABLE_DATADOG=true`.

## Checkov Infrastructure Scanning

Jenkins installs Checkov `3.3.8` in an isolated Python virtual environment.
Every pipeline run scans all Terraform before planning. The initial audit found
338 passing checks and 63 pre-existing failures. Those findings are recorded in
`.checkov.baseline`; they remain technical debt, while any newly introduced
failure blocks the pipeline. Update the baseline only after deliberately
reviewing the complete scan, never merely to make a build green.

Dev monitoring outputs:

```sh
terraform output dev_grafana_url
terraform output dev_prometheus_url
```

Prod monitoring outputs:

```sh
terraform output prod_grafana_url
terraform output prod_prometheus_url
```

To monitor more HTTP endpoints:

```sh
terraform apply -var='additional_http_probe_targets=["http://example.com"]'
```

## EC2 Bootstrap Scripts

Jenkins EC2 user data:

```sh
terraform/modules/jenkins_server/userdata.sh
```

Monitoring EC2 user data:

```sh
terraform/modules/monitoring_server/userdata.sh
```

Terraform attaches both scripts with `templatefile()`.

## Cleanup

Destroy Terraform-managed infrastructure before deleting the remote state
backend:

```sh
# From the IGLU.COM repository root:
terraform init
terraform destroy

terraform -chdir=terraform/environments/prod init
terraform -chdir=terraform/environments/prod destroy

terraform -chdir=terraform/environments/tools init
terraform -chdir=terraform/environments/tools destroy

terraform -chdir=terraform/environments/jenkins init
terraform -chdir=terraform/environments/jenkins destroy
```

The tools stack's SonarQube database has deletion protection enabled by default. Teardown is
therefore intentionally two-phase: first disable protection in-place while
retaining the final snapshot, then run destroy with the same variable value:

```sh
terraform -chdir=terraform/environments/tools apply \
  -target=module.sonarqube_database.aws_db_instance.this \
  -var='sonarqube_database_deletion_protection=false'

terraform -chdir=terraform/environments/tools destroy \
  -var='sonarqube_database_deletion_protection=false'
```

When no explicit final snapshot name is supplied, Terraform generates and
retains a stable random suffix for the database lifecycle, preventing a final
snapshot from colliding with one created by an earlier teardown. You can still
override it in both commands with
`-var='sonarqube_database_final_snapshot_identifier=UNIQUE_NAME'`. Set
`sonarqube_database_skip_final_snapshot=true` only when permanent data loss is
explicitly intended.

After the infrastructure is destroyed, delete the remote state S3 bucket and
DynamoDB lock table from the repository root:

```sh
cd /Users/chijiokealaukwu/Desktop/iglu.com
sh delete-remote-state.sh
```

Type `DELETE` when prompted.

## Notes

- Do not commit generated `terraform.tfstate` files.
- Replace backend bucket and lock table names with production-safe values before production use.
- Store the Datadog API key only in AWS Secrets Manager or another secret manager.
- The Jenkins EC2 role currently attaches `AdministratorAccess`; replace it with a scoped deployment role before production use.
# iglu
Deploying Application Using AWS ECS and fargate 
