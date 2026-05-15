project_name = "transaction-services"
environment  = "staging"

# Staging: tighter thresholds, mirrors prod-like conditions
services = [
  {
    name                     = "payment-api"
    port                     = 8080
    health_path              = "/health"
    retry_count              = 3
    slo_target               = 99.5
    latency_threshold_ms     = 600
    error_rate_threshold_pct = 2.0
  },
  {
    name                     = "transaction-worker"
    port                     = 9090
    health_path              = "/ready"
    retry_count              = 3
    slo_target               = 99.5
    latency_threshold_ms     = 1200
    error_rate_threshold_pct = 2.5
  }
]

alert_channels = ["slack://sre-staging"]
