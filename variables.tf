variable "project_name" {
  description = "Project name used in generated deployment and monitoring files"
  type        = string
  default     = "transaction-services"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "services" {
  description = "Service definitions used to build monitoring probes and SLO thresholds"
  type = list(object({
    name                     = string
    port                     = number
    health_path              = string
    retry_count              = number
    slo_target               = number
    latency_threshold_ms     = number
    error_rate_threshold_pct = number
  }))

  default = [
    {
      name                     = "payment-api"
      port                     = 8080
      health_path              = "/health"
      retry_count              = 3
      slo_target               = 99.9
      latency_threshold_ms     = 500
      error_rate_threshold_pct = 1.0
    },
    {
      name                     = "transaction-worker"
      port                     = 9090
      health_path              = "/ready"
      retry_count              = 2
      slo_target               = 99.5
      latency_threshold_ms     = 1000
      error_rate_threshold_pct = 2.0
    }
  ]
}

variable "alert_channels" {
  description = "Channels used by alert notifications (for example Slack webhook aliases)"
  type        = list(string)
  default     = ["slack://sre-alerts"]
}

variable "run_seed" {
  description = "Seed string for simulated live metrics. Change this to regenerate random metric values. In CI this is automatically set to the GitHub Actions run number so every pipeline run produces a fresh snapshot."
  type        = string
  default     = "default"
}

variable "grafana_url" {
  description = "Grafana Cloud stack URL (e.g. https://yourorg.grafana.net). Leave empty to skip pushing the dashboard via CI."
  type        = string
  default     = ""
}

variable "grafana_service_account_token" {
  description = "Grafana service account token with Editor permissions. Never commit this value — pass it via the GRAFANA_SERVICE_ACCOUNT_TOKEN GitHub Actions secret or TF_VAR_grafana_service_account_token env var."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_folder_uid" {
  description = "Grafana folder UID to import the dashboard into. Leave empty to use the General folder."
  type        = string
  default     = ""
}
