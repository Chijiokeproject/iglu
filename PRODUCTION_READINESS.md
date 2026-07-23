# Production readiness audit

## Findings corrected

- ECS was already private, but had no autoscaling, deployment rollback, execute-command support, or Container Insights. These controls are now enabled, including enhanced Container Insights exported into Prometheus/Grafana.
- Production private subnets shared one NAT gateway. Production and CI now use one NAT gateway per availability zone.
- There was no isolated data tier. Production now uses route-isolated database subnets and encrypted Multi-AZ RDS PostgreSQL with Secrets Manager-managed credentials, backups, Performance Insights, log exports, and deletion protection.
- Container images used a public mutable tag. ECR now provides immutable tags, scan-on-push, encryption, and lifecycle retention. The initial nginx image remains a bootstrap default until an application release image is pushed.
- Jenkins and the shared CI tools run without public addresses in private subnets. Jenkins uses a one-controller ASG across two AZs with encrypted, backed-up EFS state; the Jenkins bootstrap and shared tools use independent Terraform states.
- Jenkins had `AdministratorAccess` by default. It is now disabled by default; ECR push permissions are repository-scoped. A separately scoped Terraform deployment role is still required.
- There was no controlled jump path. Bastions enforce IMDSv2, encryption, detailed monitoring, Session Manager, and optional CIDR-restricted SSH.
- Maven and image-build tooling were absent from Jenkins. Docker Engine, Buildx, Compose, Maven, Java, Podman, AWS CLI, and `jq` are installed, and the pipeline audits them before tools/dev/prod work.
- Checkov is pinned and executed before Terraform planning. The checked-in baseline contains the 63 pre-existing findings; new findings fail the pipeline.
- Nexus and SonarQube were absent. Both are private, exposed only by CIDR-restricted HTTPS host rules; SonarQube uses a dedicated Multi-AZ PostgreSQL database.

## Required before first apply

- Replace the default AMI IDs with currently approved, patched AMIs for the target account and region.
- Keep RHEL bastions on `t3.micro` or larger; the RHEL platform is not available on `t3.nano`.
- Create the remote-state S3 bucket and lock table before initializing the stacks.
- Apply the Jenkins bootstrap first. The dev/prod pipeline then runs the shared tools stage because tools consumes the Jenkins network and load-balancer outputs.
- Confirm the ACM certificate covers Nexus and SonarQube when supplying an existing certificate.
- Push an application image to the ECR output and set `container_image` to its immutable release URI.
- Configure a least-privilege Jenkins deployment role and credentials; do not enable the administrator compatibility switch in production.
- Review RDS sizing, backup retention, maintenance windows, and expected monthly cost.
- Store initial Nexus/SonarQube administrator credentials in an approved secret store and rotate them at first login.

## Remaining hardening decisions

- Add AWS WAF and ALB access-log buckets if the public application requires internet exposure.
- Add VPC endpoints for ECR, S3, CloudWatch Logs, Secrets Manager, and SSM to reduce NAT dependency and cost.
- Centralize CloudTrail, Config, GuardDuty, Security Hub, alarms, and log archival at the account/organization layer.
- Replace single EC2 CI tool nodes with a tested backup/restore or high-availability design according to recovery objectives.
- Pin container images by digest after validating the desired Nexus and SonarQube releases.
