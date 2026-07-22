#!/bin/bash
set -euxo pipefail

# AWS-provided RHEL 8/9 AMIs do not include SSM Agent by default. Install and
# start it before the longer monitoring bootstrap so Session Manager becomes
# available even if a later application-install step fails.
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable --now amazon-ssm-agent

dnf update -y
dnf install -y wget tar gzip

useradd --no-create-home --shell /bin/false prometheus || true
useradd --no-create-home --shell /bin/false node_exporter || true
mkdir -p /etc/prometheus /var/lib/prometheus

cd /tmp
wget "https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.linux-amd64.tar.gz"
tar xzf "prometheus-${prometheus_version}.linux-amd64.tar.gz"
cp "prometheus-${prometheus_version}.linux-amd64/prometheus" /usr/local/bin/
cp "prometheus-${prometheus_version}.linux-amd64/promtool" /usr/local/bin/

wget "https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
tar xzf "node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
cp "node_exporter-${node_exporter_version}.linux-amd64/node_exporter" /usr/local/bin/

wget "https://github.com/prometheus/blackbox_exporter/releases/download/v${blackbox_exporter_version}/blackbox_exporter-${blackbox_exporter_version}.linux-amd64.tar.gz"
tar xzf "blackbox_exporter-${blackbox_exporter_version}.linux-amd64.tar.gz"
cp "blackbox_exporter-${blackbox_exporter_version}.linux-amd64/blackbox_exporter" /usr/local/bin/
mkdir -p /etc/blackbox_exporter
cp "blackbox_exporter-${blackbox_exporter_version}.linux-amd64/blackbox.yml" /etc/blackbox_exporter/blackbox.yml

cat >/etc/prometheus/prometheus.yml <<PROMETHEUS_CONFIG
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets: [${prometheus_targets_yaml}]

  - job_name: http-endpoints
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets: [${http_probe_targets_yaml}]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
PROMETHEUS_CONFIG

chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
chown node_exporter:node_exporter /usr/local/bin/node_exporter
chown -R prometheus:prometheus /etc/blackbox_exporter
chown prometheus:prometheus /usr/local/bin/blackbox_exporter

cat >/etc/systemd/system/prometheus.service <<'PROMETHEUS_SERVICE'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.external-url=https://${prometheus_hostname}

[Install]
WantedBy=multi-user.target
PROMETHEUS_SERVICE

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

cat >/etc/systemd/system/blackbox_exporter.service <<'BLACKBOX_EXPORTER_SERVICE'
[Unit]
Description=Prometheus Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/blackbox.yml

[Install]
WantedBy=multi-user.target
BLACKBOX_EXPORTER_SERVICE

wget -q -O /tmp/grafana-gpg.key https://rpm.grafana.com/gpg.key
rpm --import /tmp/grafana-gpg.key
cat >/etc/yum.repos.d/grafana.repo <<'GRAFANA_REPO'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
GRAFANA_REPO

dnf install -y grafana
sed -i 's|^;domain =.*|domain = ${grafana_hostname}|' /etc/grafana/grafana.ini
sed -i 's|^;root_url =.*|root_url = https://${grafana_hostname}/|' /etc/grafana/grafana.ini
mkdir -p /etc/grafana/provisioning/datasources
cat >/etc/grafana/provisioning/datasources/prometheus.yml <<'GRAFANA_DATASOURCE'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
GRAFANA_DATASOURCE

systemctl daemon-reload
systemctl enable node_exporter blackbox_exporter prometheus grafana-server
systemctl start node_exporter blackbox_exporter prometheus grafana-server
