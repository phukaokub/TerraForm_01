output "deployment_yaml" {
  description = "Rendered deployment manifest content"
  value       = local.deployment_yaml
}

output "alerts_json" {
  description = "Rendered alert rules as JSON"
  value = jsonencode({
    generated_at = "terraform-apply"
    project      = var.project_name
    environment  = var.environment
    alert_rules  = local.alert_rules
  })
}

output "grafana_dashboard_json" {
  description = "Grafana dashboard JSON ready for import"
  value       = local.grafana_dashboard_json
}

output "service_endpoints" {
  description = "Health-check endpoints derived from service configuration"
  value       = [for s in local.service_reliability : s.endpoint]
}

output "service_reliability" {
  description = "Per-service computed reliability metrics"
  value = { for s in local.service_reliability : s.name => {
    slo_target                     = s.slo_target
    error_budget_minutes           = s.error_budget_minutes
    max_allowable_downtime_minutes = s.max_allowable_downtime_minutes
  } }
}
