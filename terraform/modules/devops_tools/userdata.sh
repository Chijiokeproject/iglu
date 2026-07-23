#!/bin/bash
set -euxo pipefail

for attempt in $(seq 1 10); do
  if dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm; then
    break
  fi
  sleep 15
done
rpm -q amazon-ssm-agent
systemctl enable --now amazon-ssm-agent
dnf install -y podman jq awscli

if [ "${service}" = "nexus" ]; then
  podman volume create nexus-data
  podman create --name nexus --restart=always -p 8081:8081 -v nexus-data:/nexus-data docker.io/sonatype/nexus3:3.82.0
  podman generate systemd --new --name nexus >/etc/systemd/system/nexus.service
  systemctl daemon-reload
  systemctl enable --now nexus
else
  sysctl -w vm.max_map_count=524288
  printf 'vm.max_map_count=524288\n' >/etc/sysctl.d/99-sonarqube.conf
  secret_json=$(aws secretsmanager get-secret-value --region "${aws_region}" --secret-id "${database_secret_arn}" --query SecretString --output text)
  db_user=$(printf '%s' "$secret_json" | jq -r .username)
  db_password=$(printf '%s' "$secret_json" | jq -r .password)
  podman volume create sonarqube-data
  podman volume create sonarqube-extensions
  podman volume create sonarqube-logs
  podman create --name sonarqube --restart=always -p 9000:9000 \
    -e "SONAR_JDBC_URL=jdbc:postgresql://${database_endpoint}:5432/${database_name}" \
    -e "SONAR_JDBC_USERNAME=$db_user" -e "SONAR_JDBC_PASSWORD=$db_password" \
    -v sonarqube-data:/opt/sonarqube/data -v sonarqube-extensions:/opt/sonarqube/extensions \
    -v sonarqube-logs:/opt/sonarqube/logs docker.io/sonarqube:25.7.0.110598-community
  podman generate systemd --new --name sonarqube >/etc/systemd/system/sonarqube.service
  systemctl daemon-reload
  systemctl enable --now sonarqube
fi
