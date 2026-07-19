# iglu

Deploying an application using AWS ECS Fargate, Terraform, Jenkins, Route 53,
Datadog, Prometheus, and Grafana.

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
- `terraform/environments/jenkins` - Jenkins and monitoring environment
- `terraform/environments/prod` - production ECS environment

Run development Terraform commands directly from the `IGLU.COM` repository
root. Run Jenkins and production commands from their respective directories
under `terraform/environments`. The `terraform` directory itself only contains
modules and additional environments, so it is not a runnable stack.

Before applying, confirm that the AWS credentials point to the intended account
and that these prerequisites exist:

- the S3 state bucket and DynamoDB lock table described below
- the public Route 53 hosted zone for `chijiokedevops.com`
- an issued ACM certificate in `us-east-1` only when enabling Jenkins HTTPS
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

Create the Jenkins servers:

```sh
cd terraform/environments/jenkins
terraform init
terraform plan
terraform apply
```

The Jenkins environment creates two Jenkins EC2 instances by default, places them
across the two public subnets/AZs, and fronts them with an Application Load
Balancer. For testing, the certificate defaults to `null` and the ALB uses HTTP
on port `80`. To use HTTPS on port `443`, supply an ACM certificate from the same
region that covers `jenkins.chijiokedevops.com` or `*.chijiokedevops.com`:

```sh
terraform apply \
  -var='jenkins_acm_certificate_arn=arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERTIFICATE_ID'
```

The Jenkins and monitoring EC2 modules use Red Hat Enterprise Linux AMIs passed
as variables. The modules do not look up AMIs with Terraform data blocks.

To change the number of instances:

```sh
terraform apply \
  -var='jenkins_instance_count=2'
```

To restrict Jenkins, Grafana, and Prometheus access to your own public IP:

```sh
terraform apply \
  -var='allowed_admin_cidr=YOUR_PUBLIC_IP/32'
```

Useful outputs:

```sh
terraform output jenkins_url
terraform output jenkins_dns_url
terraform output grafana_url
terraform output prometheus_url
```

The Jenkins initial admin password is on the instance at:

```sh
/home/ec2-user/jenkins-initial-admin-password.txt
```

EC2 instances do not allow SSH. Use AWS Systems Manager Session Manager instead:

```sh
aws ssm start-session --target JENKINS_INSTANCE_ID --region us-east-1
sudo cat /home/ec2-user/jenkins-initial-admin-password.txt
```

Create a Jenkins Pipeline job that uses `Jenkinsfile`.

Pipeline parameters:

- `ENVIRONMENT`: `dev` or `prod`
- `ACTION`: `plan`, `apply`, or `destroy`
- `ENABLE_DATADOG`: enable the Datadog ECS Fargate sidecar
- `DATADOG_API_KEY_SECRET_ARN`: Secrets Manager ARN for the Datadog API key
- `DATADOG_SITE`: Datadog site, for example `datadoghq.com`
- `MONITORING_AMI_ID`: optional Red Hat Enterprise Linux AMI ID override for the monitoring server; blank uses the Terraform environment default
- `ALLOWED_ADMIN_CIDR`: optional restricted public CIDR override for Grafana and Prometheus; blank uses the Terraform environment default

## Route 53 DNS

Route 53 records are enabled by default and use the following existing public
hosted zone:

```sh
chijiokedevops.com
```

Terraform creates:

- `jenkins.chijiokedevops.com` -> Jenkins application load balancer
- `grafana.jenkins.chijiokedevops.com` -> Jenkins monitoring server
- `prometheus.jenkins.chijiokedevops.com` -> Jenkins monitoring server
- `dev.chijiokedevops.com` -> dev application load balancer
- `grafana.dev.chijiokedevops.com` -> dev monitoring server
- `prometheus.dev.chijiokedevops.com` -> dev monitoring server
- `prod.chijiokedevops.com` -> prod application load balancer
- `grafana.prod.chijiokedevops.com` -> prod monitoring server
- `prometheus.prod.chijiokedevops.com` -> prod monitoring server

Useful outputs:

```sh
terraform output jenkins_dns_url
terraform output dev_url
terraform output prod_url
```

Set `create_route53_record = false` only when deploying into an account without
the hosted zone.

Note: this creates multiple Jenkins controllers behind one ALB for lab-level
availability. Production Jenkins HA needs a deeper controller state and plugin
strategy before active/active use.

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

## ECS Fargate Networking And Logs

The ECS Fargate module creates:

- an ALB target group with `target_type = "ip"` for Fargate tasks
- a CloudWatch log group at `/ecs/<project>-<environment>`
- ECS task logging through the `awslogs` driver
- environment-safe resource names using `<project>-<environment>`

The VPC module creates a NAT Gateway and routes private subnets through it. This
allows Fargate tasks with `assign_public_ip = false` to pull container images,
send CloudWatch logs, read Secrets Manager values, and communicate with Datadog.

## Datadog For ECS Fargate

Datadog is integrated into the ECS Fargate module as an optional sidecar
container and is disabled by default. When enabled, Terraform automatically
looks up the `iglu/datadog/api-key` secret in AWS Secrets Manager.

Before the first Terraform plan or apply, store the API key issued by your
Datadog account. The helper prompts for the value without writing it to the
repository or Terraform state:

```sh
./create-datadog-secret.sh
```

Then plan and apply normally:

```sh
terraform plan -out=tfplan
terraform apply tfplan
```

After apply, print the Datadog login URL with `terraform output
dev_datadog_url` (or `terraform output prod_datadog_url` from the prod
directory). Sign in and filter containers or services by `env:dev` or
`env:prod`.

To enable it later, set `enable_datadog=true` after creating the secret.
`datadog_api_key_secret_arn` remains available as an optional override when the
secret has a different name or lives outside the default setup.

When deploying through Jenkins, set:

- `ENABLE_DATADOG`: `true`
- `DATADOG_API_KEY_SECRET_NAME`: `iglu/datadog/api-key` by default
- `DATADOG_API_KEY_SECRET_ARN`: optional Secrets Manager ARN override
- `DATADOG_SITE`: your Datadog site

The Datadog sidecar is configured for ECS Fargate metrics and can receive APM
traffic from instrumented application containers. Log collection variables are
included, but production Fargate log routing may also require FireLens depending
on the logging design you choose.

You can change the Datadog site if needed:

```sh
terraform apply \
  -var='datadog_site=datadoghq.eu'
```

## Prometheus And Grafana

Each environment includes monitoring with:

- Prometheus on port `9090`
- Grafana on port `3000`
- Node Exporter for host metrics
- Blackbox Exporter for HTTP health checks

Prometheus monitors:

- Jenkins host metrics on port `9100`
- Monitoring host metrics on port `9100`
- Jenkins web health on port `8080`
- Jenkins public HTTPS health at `https://jenkins.chijiokedevops.com/login`
- Dev ECS application health through the dev ALB
- Prod ECS application health through the prod ALB
- Grafana web health on port `3000`
- Prometheus health on port `9090`

Grafana default login:

- Username: `admin`
- Password: `admin`

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

terraform -chdir=terraform/environments/jenkins init
terraform -chdir=terraform/environments/jenkins destroy
```

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
- The Jenkins EC2 role currently attaches `AdministratorAccess` so Terraform can deploy this lab infrastructure. Replace it with least-privilege IAM before production use.
# iglu
Deploying Application Using AWS ECS and fargate 
