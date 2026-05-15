locals {
  # Minutes in a standard 30-day month used for SLO error budget calculations
  month_minutes = 43800

  # Panel width distributes 24 Grafana columns equally across services
  panel_width = 24 / length(var.services)

  # Derived per-service reliability values
  service_reliability = [for s in var.services : {
    name                           = s.name
    port                           = s.port
    health_path                    = s.health_path
    retry_count                    = s.retry_count
    slo_target                     = s.slo_target
    latency_threshold_ms           = s.latency_threshold_ms
    error_rate_threshold_pct       = s.error_rate_threshold_pct
    endpoint                       = "http://${s.name}:${s.port}${s.health_path}"
    error_budget_minutes           = (1 - s.slo_target / 100) * local.month_minutes
    max_allowable_downtime_minutes = (1 - s.slo_target / 100) * local.month_minutes
  }]

  # --------------------------------------------------------------------------
  # Deployment manifest
  # --------------------------------------------------------------------------
  deployment_yaml = yamlencode({
    project = var.project_name
    env     = var.environment
    services = [for s in local.service_reliability : {
      name = s.name
      monitoring = {
        endpoint    = s.endpoint
        retry_count = s.retry_count
        latency_ms  = s.latency_threshold_ms
        error_rate  = s.error_rate_threshold_pct
        slo_uptime  = s.slo_target
      }
    }]
  })

  # --------------------------------------------------------------------------
  # Operational alert rules (one set of three per service)
  # --------------------------------------------------------------------------
  alert_rules = flatten([for s in local.service_reliability : [
    {
      name          = "transaction-drop-${s.name}"
      service       = s.name
      type          = "transaction_drop"
      severity      = "critical"
      condition     = "${s.name} transaction rate falls below 80% of expected baseline TPS"
      threshold_pct = 80
      channels      = var.alert_channels
      runbook       = "https://runbooks.internal/${var.project_name}/${s.name}/transaction-drop"
    },
    {
      name                 = "uptime-drop-${s.name}"
      service              = s.name
      type                 = "uptime_drop"
      severity             = "critical"
      condition            = "${s.name} health probe fails ${s.retry_count} consecutive checks (${s.endpoint})"
      consecutive_failures = s.retry_count
      channels             = var.alert_channels
      runbook              = "https://runbooks.internal/${var.project_name}/${s.name}/uptime-drop"
    },
    {
      name                       = "deployment-anomaly-${s.name}"
      service                    = s.name
      type                       = "deployment_anomaly"
      severity                   = "warning"
      condition                  = "${s.name} error rate > ${s.error_rate_threshold_pct}% within 5 min post-deploy window"
      threshold_pct              = s.error_rate_threshold_pct
      post_deploy_window_minutes = 5
      channels                   = var.alert_channels
      runbook                    = "https://runbooks.internal/${var.project_name}/${s.name}/deployment-anomaly"
    }
  ]])

  # --------------------------------------------------------------------------
  # Grafana dashboard — panels built as individual JSON strings so that
  # heterogeneous panel types (gauge, stat, row, text) can coexist in one list
  # without Terraform's type system requiring a uniform object schema.
  # --------------------------------------------------------------------------

  # Row dividers
  _row_slo_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 0 }
    id        = 1
    title     = "Service SLO and Error Budget"
    type      = "row"
  })

  _row_latency_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 11 }
    id        = 2
    title     = "Latency and Error Rate Thresholds"
    type      = "row"
  })

  _row_alerts_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 21 }
    id        = 3
    title     = "Generated Alert Rules"
    type      = "row"
  })

  # SLO gauge panels (one per service, row y=1)
  _slo_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        max   = 100
        min   = floor(s.slo_target) - 1
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "red", value = null },
            { color = "yellow", value = s.slo_target - 0.5 },
            { color = "green", value = s.slo_target }
          ]
        }
        unit = "percent"
      }
      overrides = []
    }
    gridPos = { h = 6, w = local.panel_width, x = idx * local.panel_width, y = 1 }
    id      = 100 + idx
    options = {
      orientation          = "auto"
      reduceOptions        = { calcs = ["lastNotNull"], fields = "", values = false }
      showThresholdLabels  = false
      showThresholdMarkers = true
    }
    targets = [{
      alias      = "SLO %"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.slo_target}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - SLO Target"
    type  = "gauge"
  })]

  # Error budget stat panels (one per service, row y=7)
  _budget_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "red", value = null },
            { color = "yellow", value = 30 },
            { color = "green", value = 120 }
          ]
        }
        unit = "short"
      }
      overrides = []
    }
    gridPos = { h = 4, w = local.panel_width, x = idx * local.panel_width, y = 7 }
    id      = 200 + idx
    options = {
      colorMode     = "background"
      graphMode     = "none"
      justifyMode   = "auto"
      orientation   = "auto"
      reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }
      textMode      = "auto"
    }
    targets = [{
      alias      = "mins/month"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.error_budget_minutes}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Error Budget (mins/month)"
    type  = "stat"
  })]

  # Latency gauge panels (one per service, row y=12)
  _latency_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        max   = 3000
        min   = 0
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "green", value = null },
            { color = "yellow", value = 500 },
            { color = "red", value = 1500 }
          ]
        }
        unit = "ms"
      }
      overrides = []
    }
    gridPos = { h = 5, w = local.panel_width, x = idx * local.panel_width, y = 12 }
    id      = 300 + idx
    options = {
      orientation          = "auto"
      reduceOptions        = { calcs = ["lastNotNull"], fields = "", values = false }
      showThresholdLabels  = false
      showThresholdMarkers = true
    }
    targets = [{
      alias      = "ms"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.latency_threshold_ms}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Latency Threshold"
    type  = "gauge"
  })]

  # Error rate stat panels (one per service, row y=17)
  _errorrate_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "green", value = null },
            { color = "yellow", value = 1 },
            { color = "red", value = 3 }
          ]
        }
        unit = "percent"
      }
      overrides = []
    }
    gridPos = { h = 4, w = local.panel_width, x = idx * local.panel_width, y = 17 }
    id      = 400 + idx
    options = {
      colorMode     = "background"
      graphMode     = "none"
      justifyMode   = "auto"
      orientation   = "auto"
      reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }
      textMode      = "auto"
    }
    targets = [{
      alias      = "error %"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.error_rate_threshold_pct}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Error Rate Threshold"
    type  = "stat"
  })]

  # Alert rules markdown summary for text panel
  _alert_summary_md = join("\n\n", [for r in local.alert_rules :
    "**${r.name}** `${r.severity}`  \n${r.condition}  \nChannels: `${join("`, `", r.channels)}`  \nRunbook: `${r.runbook}`"
  ])

  _alerts_text_panel_json = jsonencode({
    gridPos = { h = 10, w = 24, x = 0, y = 22 }
    id      = 500
    options = {
      content = "## Alert Configuration (Terraform-generated)\n\n${local._alert_summary_md}"
      mode    = "markdown"
    }
    title = "Alert Configuration"
    type  = "text"
  })

  # Ordered list of all panel JSON strings
  _all_panel_jsons = concat(
    [local._row_slo_json],
    local._slo_panel_jsons,
    local._budget_panel_jsons,
    [local._row_latency_json],
    local._latency_panel_jsons,
    local._errorrate_panel_jsons,
    [local._row_alerts_json],
    [local._alerts_text_panel_json]
  )

  # Assemble full Grafana dashboard JSON.
  # panels is set to [] as a placeholder then replaced with the assembled
  # panel JSON string — required because panels use heterogeneous schemas.
  grafana_dashboard_json = replace(
    jsonencode({
      __inputs = [{
        description = "Built-in Grafana TestData datasource - no configuration required"
        label       = "TestData DB"
        name        = "DS_TESTDATA"
        pluginId    = "testdata"
        pluginName  = "TestData DB"
        type        = "datasource"
      }]
      __elements = {}
      __requires = [
        { id = "grafana", name = "Grafana", type = "grafana", version = "10.0.0" },
        { id = "testdata", name = "TestData DB", type = "datasource", version = "1.0.0" },
        { id = "gauge", name = "Gauge", type = "panel", version = "" },
        { id = "stat", name = "Stat", type = "panel", version = "" },
        { id = "text", name = "Text", type = "panel", version = "" }
      ]
      annotations = {
        list = [{
          builtIn    = 1
          datasource = { type = "grafana", uid = "-- Grafana --" }
          enable     = true
          hide       = true
          iconColor  = "rgba(0, 211, 255, 1)"
          name       = "Annotations and Alerts"
          type       = "dashboard"
        }]
      }
      description   = "Reliability dashboard for ${var.project_name} (${var.environment}) - generated by Terraform"
      editable      = true
      graphTooltip  = 0
      id            = null
      links         = []
      panels        = []
      refresh       = "30s"
      schemaVersion = 38
      tags          = ["sre", "reliability", "terraform-generated", var.environment]
      templating    = { list = [] }
      time          = { from = "now-6h", to = "now" }
      timepicker    = {}
      timezone      = "browser"
      title         = "${var.project_name}-${var.environment}-reliability"
      uid           = "${var.project_name}-${var.environment}"
      version       = 0
    }),
    "\"panels\":[]",
    "\"panels\":[${join(",", local._all_panel_jsons)}]"
  )
}
