variable "project_name" {
  description = "Project name used in generated deployment and monitoring files"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
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
}

variable "alert_channels" {
  description = "Channels used by alert notifications (e.g. Slack webhook aliases)"
  type        = list(string)
}
