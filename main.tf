terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

locals {
  deployment_yaml = yamlencode({
    project = var.project_name
    env     = var.environment
    services = [for service in var.services : {
      name      = service.name
      monitoring = {
        endpoint     = "http://${service.name}:${service.port}${service.health_path}"
        retry_count  = service.retry_count
        latency_ms   = service.latency_threshold_ms
        error_rate   = service.error_rate_threshold_pct
        slo_uptime   = service.slo_target
      }
    }]
  })

  dashboard_json = jsonencode({
    dashboard = {
      title   = "${var.project_name}-${var.environment}-reliability"
      metrics = [
        "mttd_minutes",
        "mttr_minutes",
        "mtbf_hours",
        "availability_percent"
      ]
      alerts = {
        channels = var.alert_channels
      }
      probes = [for service in var.services : {
        service               = service.name
        endpoint              = "http://${service.name}:${service.port}${service.health_path}"
        latency_threshold_ms  = service.latency_threshold_ms
        error_rate_threshold  = service.error_rate_threshold_pct
      }]
    }
  })
}

resource "local_file" "deployment_manifest" {
  filename = "${path.module}/deployment.generated.yaml"
  content  = local.deployment_yaml
}

resource "local_file" "monitoring_dashboard" {
  filename = "${path.module}/dashboard.generated.json"
  content  = local.dashboard_json
}
