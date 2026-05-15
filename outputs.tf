output "generated_files" {
  description = "Generated deployment and monitoring assets"
  value = {
    deployment_manifest = local_file.deployment_manifest.filename
    monitoring_dashboard = local_file.monitoring_dashboard.filename
  }
}

output "service_endpoints" {
  description = "Health-check endpoints derived from service configuration"
  value       = [for service in var.services : "http://${service.name}:${service.port}${service.health_path}"]
}
