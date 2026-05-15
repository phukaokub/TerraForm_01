output "generated_files" {
  description = "Generated deployment and monitoring assets"
  value = {
    deployment_manifest = local_file.deployment_manifest.filename
    alerts_config       = local_file.alerts_config.filename
    grafana_dashboard   = local_file.grafana_dashboard.filename
  }
}

output "service_endpoints" {
  description = "Health-check endpoints derived from service configuration"
  value       = module.service_monitoring.service_endpoints
}

output "service_reliability" {
  description = "Per-service reliability metrics: SLO target, error budget, and max allowable downtime"
  value       = module.service_monitoring.service_reliability
}
