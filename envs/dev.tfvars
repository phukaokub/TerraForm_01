project_name = "transaction-services"
environment  = "dev"

# Dev: lenient thresholds for fast iteration
services = [
  {
    name                     = "payment-api"
    port                     = 8080
    health_path              = "/health"
    retry_count              = 5
    slo_target               = 99.0
    latency_threshold_ms     = 1000
    error_rate_threshold_pct = 5.0
  },
  {
    name                     = "transaction-worker"
    port                     = 9090
    health_path              = "/ready"
    retry_count              = 4
    slo_target               = 99.0
    latency_threshold_ms     = 2500
    error_rate_threshold_pct = 5.0
  }
]

alert_channels = ["slack://sre-dev"]
