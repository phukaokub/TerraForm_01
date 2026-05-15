terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

module "service_monitoring" {
  source = "./modules/service-monitoring"

  project_name   = var.project_name
  environment    = var.environment
  services       = var.services
  alert_channels = var.alert_channels
}

resource "local_file" "deployment_manifest" {
  filename = "${path.module}/deployment.generated.yaml"
  content  = module.service_monitoring.deployment_yaml
}

resource "local_file" "alerts_config" {
  filename = "${path.module}/alerts.generated.json"
  content  = module.service_monitoring.alerts_json
}

resource "local_file" "grafana_dashboard" {
  filename = "${path.module}/grafana-dashboard.generated.json"
  content  = module.service_monitoring.grafana_dashboard_json
}
