project_name = "transaction-services"
environment  = "prod"

# Prod: strictest thresholds — near-five-nines SLO, tight latency, PagerDuty escalation
services = [
  {
    name                     = "payment-api"
    port                     = 8080
    health_path              = "/health"
    retry_count              = 2
    slo_target               = 99.95
    latency_threshold_ms     = 400
    error_rate_threshold_pct = 0.5
  },
  {
    name                     = "transaction-worker"
    port                     = 9090
    health_path              = "/ready"
    retry_count              = 2
    slo_target               = 99.9
    latency_threshold_ms     = 800
    error_rate_threshold_pct = 1.0
  }
]

alert_channels = ["slack://sre-prod", "pagerduty://transaction-oncall"]
