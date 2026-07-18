#!/bin/bash
set -euxo pipefail

# AWS-provided RHEL 8/9 AMIs do not include SSM Agent by default. Install and
# start it before the longer Jenkins bootstrap so Session Manager becomes
# available even if a later application-install step fails.
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable --now amazon-ssm-agent

dnf update -y
dnf install -y wget git unzip fontconfig java-21-openjdk dnf-plugins-core

useradd --no-create-home --shell /bin/false node_exporter || true
cd /tmp
wget "https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
tar xzf "node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
cp "node_exporter-${node_exporter_version}.linux-amd64/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat >/etc/systemd/system/node_exporter.service <<'NODE_EXPORTER_SERVICE'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
NODE_EXPORTER_SERVICE

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
dnf install -y terraform

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
systemctl enable jenkins
systemctl start jenkins

sleep 30
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
  cp /var/lib/jenkins/secrets/initialAdminPassword /home/ec2-user/jenkins-initial-admin-password.txt
  chown ec2-user:ec2-user /home/ec2-user/jenkins-initial-admin-password.txt
  chmod 600 /home/ec2-user/jenkins-initial-admin-password.txt
fi
