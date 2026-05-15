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
