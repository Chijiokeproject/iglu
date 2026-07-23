output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "devops_tool_instance_ids" {
  value = module.devops_tools.instance_ids
}

output "monitoring_instance_id" {
  value = module.monitoring_server.instance_id
}

output "nexus_url" {
  value = "https://${local.nexus_fqdn}"
}

output "sonarqube_url" {
  value = "https://${local.sonarqube_fqdn}"
}

output "grafana_url" {
  value = "https://${local.grafana_fqdn}"
}

output "prometheus_url" {
  value = "https://${local.prometheus_fqdn}"
}
