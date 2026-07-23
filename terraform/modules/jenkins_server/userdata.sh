#!/bin/bash
set -euxo pipefail

# AWS-provided RHEL 8/9 AMIs do not include SSM Agent by default. Install and
# start it before the longer Jenkins bootstrap so Session Manager becomes
# available even if a later application-install step fails.
for attempt in $(seq 1 10); do
  if dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm; then
    break
  fi
  sleep 15
done
rpm -q amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

# Keep the controller launch path short. Patch the approved AMI before release
# instead of upgrading the entire operating system while the ALB is waiting for
# Jenkins to become ready.
dnf install -y wget fontconfig java-21-openjdk dnf-plugins-core nfs-utils

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# Jenkins is the shared image builder for dev and prod. Fargate itself is a
# managed runtime and does not require (or expose) a host Docker daemon.
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ec2-user
usermod -aG docker jenkins

# JENKINS_HOME is kept on encrypted, backed-up EFS so an Auto Scaling
# replacement in either Availability Zone starts with the same controller
# configuration. The ASG is deliberately capped at one active controller.
mkdir -p /var/lib/jenkins
for attempt in $(seq 1 20); do
  if mount -t nfs4 -o nfsvers=4.1 "${efs_file_system_id}.efs.${aws_region}.amazonaws.com:/" /var/lib/jenkins; then
    break
  fi
  sleep 15
done
mountpoint -q /var/lib/jenkins
grep -q "${efs_file_system_id}.efs.${aws_region}.amazonaws.com" /etc/fstab || \
  echo "${efs_file_system_id}.efs.${aws_region}.amazonaws.com:/ /var/lib/jenkins nfs4 defaults,_netdev,nofail,nfsvers=4.1 0 0" >>/etc/fstab
chown jenkins:jenkins /var/lib/jenkins

# Start the user-facing service before installing noncritical build and
# monitoring utilities. The ALB health check will register it only after
# /login responds successfully.
systemctl daemon-reload
systemctl enable --now jenkins

dnf install -y git unzip maven podman jq awscli python3 python3-pip

python3 -m venv /opt/checkov
/opt/checkov/bin/pip install --upgrade pip
/opt/checkov/bin/pip install "checkov==${checkov_version}"
ln -sf /opt/checkov/bin/checkov /usr/local/bin/checkov

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

dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
dnf install -y terraform

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

sleep 30
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
  cp /var/lib/jenkins/secrets/initialAdminPassword /home/ec2-user/jenkins-initial-admin-password.txt
  chown ec2-user:ec2-user /home/ec2-user/jenkins-initial-admin-password.txt
  chmod 600 /home/ec2-user/jenkins-initial-admin-password.txt
fi
