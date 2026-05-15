terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ---------------------------------------------------------------------------
# Simulated live metrics — one random snapshot per service per apply.
# keepers tie the value to run_seed: changing the seed (e.g. to the CI run
# number) forces new values; keeping it stable gives reproducible local demos.
# ---------------------------------------------------------------------------

resource "random_integer" "current_latency_ms" {
  for_each = { for s in var.services : s.name => s }
  min      = max(50, floor(each.value.latency_threshold_ms * 0.5))
  max      = ceil(each.value.latency_threshold_ms * 1.5)
  keepers  = { run_seed = var.run_seed }
}

resource "random_integer" "current_error_pct_x10" {
  for_each = { for s in var.services : s.name => s }
  min      = 0
  max      = max(1, ceil(each.value.error_rate_threshold_pct * 2.0 * 10))
  keepers  = { run_seed = var.run_seed }
}

resource "random_integer" "current_tps" {
  for_each = { for s in var.services : s.name => s }
  min      = 1500
  max      = 8000
  keepers  = { run_seed = var.run_seed }
}

locals {
  simulated_metrics = [for s in var.services : {
    service_name       = s.name
    current_latency_ms = random_integer.current_latency_ms[s.name].result
    current_error_pct  = random_integer.current_error_pct_x10[s.name].result / 10.0
    current_tps        = random_integer.current_tps[s.name].result
  }]
}

module "service_monitoring" {
  source = "./modules/service-monitoring"

  project_name      = var.project_name
  environment       = var.environment
  services          = var.services
  alert_channels    = var.alert_channels
  simulated_metrics = local.simulated_metrics
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
