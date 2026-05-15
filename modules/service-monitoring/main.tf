locals {
  # Minutes in a standard 30-day month used for SLO error budget calculations
  month_minutes = 43800

  # Panel width distributes 24 Grafana columns equally across services
  panel_width = 24 / length(var.services)

  # Index simulated metrics by service name for easy lookup
  _sim_lookup = { for m in var.simulated_metrics : m.service_name => m }

  # Derived per-service reliability values — includes simulated current metrics
  # for the live-snapshot dashboard row; falls back to threshold values when no
  # simulated data is provided.
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
    current_latency_ms             = contains(keys(local._sim_lookup), s.name) ? local._sim_lookup[s.name].current_latency_ms : s.latency_threshold_ms
    current_error_pct              = contains(keys(local._sim_lookup), s.name) ? local._sim_lookup[s.name].current_error_pct : s.error_rate_threshold_pct
    current_tps                    = contains(keys(local._sim_lookup), s.name) ? local._sim_lookup[s.name].current_tps : 3000
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
  #
  # Layout (y positions):
  #   y= 0  Row: Service SLO and Error Budget
  #   y= 1  SLO gauges               (h=6)
  #   y= 7  Error budget stats        (h=4)
  #   y=11  Row: Live Snapshot (changes each deploy)
  #   y=12  Current latency gauges    (h=5)
  #   y=17  Current error rate stats  (h=4)
  #   y=21  Current TPS stats         (h=4)
  #   y=25  Row: Configured Thresholds
  #   y=26  Latency threshold gauges  (h=5)
  #   y=31  Error rate threshold stats(h=4)
  #   y=35  Row: Generated Alert Rules
  #   y=36  Alert rules text          (h=10)
  # --------------------------------------------------------------------------

  # ── Row separators ──────────────────────────────────────────────────────────

  _row_slo_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 0 }
    id        = 1
    title     = "Service SLO and Error Budget"
    type      = "row"
  })

  _row_live_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 11 }
    id        = 2
    title     = "Live Snapshot (randomised each deploy)"
    type      = "row"
  })

  _row_thresholds_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 25 }
    id        = 3
    title     = "Configured Thresholds"
    type      = "row"
  })

  _row_alerts_json = jsonencode({
    collapsed = false
    gridPos   = { h = 1, w = 24, x = 0, y = 35 }
    id        = 4
    title     = "Generated Alert Rules"
    type      = "row"
  })

  # ── Row 1: SLO gauges and error budget ─────────────────────────────────────

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

  # ── Row 2: Live Snapshot — values change on every deploy ───────────────────
  # Thresholds on these panels match the configured limits so green/yellow/red
  # status reflects whether the current snapshot is within SLO.

  _live_latency_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        max   = s.latency_threshold_ms * 2
        min   = 0
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "green", value = null },
            { color = "yellow", value = floor(s.latency_threshold_ms * 0.8) },
            { color = "red", value = s.latency_threshold_ms }
          ]
        }
        unit = "ms"
      }
      overrides = []
    }
    gridPos = { h = 5, w = local.panel_width, x = idx * local.panel_width, y = 12 }
    id      = 310 + idx
    options = {
      orientation          = "auto"
      reduceOptions        = { calcs = ["lastNotNull"], fields = "", values = false }
      showThresholdLabels  = false
      showThresholdMarkers = true
    }
    targets = [{
      alias      = "current ms"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.current_latency_ms}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Current Latency"
    type  = "gauge"
  })]

  _live_errorrate_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "green", value = null },
            { color = "yellow", value = s.error_rate_threshold_pct * 0.7 },
            { color = "red", value = s.error_rate_threshold_pct }
          ]
        }
        unit = "percent"
      }
      overrides = []
    }
    gridPos = { h = 4, w = local.panel_width, x = idx * local.panel_width, y = 17 }
    id      = 410 + idx
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
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.current_error_pct}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Current Error Rate"
    type  = "stat"
  })]

  _live_tps_panel_jsons = [for idx, s in local.service_reliability : jsonencode({
    datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
    fieldConfig = {
      defaults = {
        color = { mode = "thresholds" }
        thresholds = {
          mode = "absolute"
          steps = [
            { color = "red", value = null },
            { color = "yellow", value = 2500 },
            { color = "green", value = 4000 }
          ]
        }
        unit = "short"
      }
      overrides = []
    }
    gridPos = { h = 4, w = local.panel_width, x = idx * local.panel_width, y = 21 }
    id      = 510 + idx
    options = {
      colorMode     = "background"
      graphMode     = "none"
      justifyMode   = "auto"
      orientation   = "auto"
      reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }
      textMode      = "auto"
    }
    targets = [{
      alias      = "TPS"
      csvContent = "Time,Value\n2024-01-01T00:00:00Z,${s.current_tps}"
      datasource = { type = "testdata", uid = "$${DS_TESTDATA}" }
      refId      = "A"
      scenarioId = "csv_content"
    }]
    title = "${s.name} - Current TPS"
    type  = "stat"
  })]

  # ── Row 3: Configured Thresholds ───────────────────────────────────────────

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
    gridPos = { h = 5, w = local.panel_width, x = idx * local.panel_width, y = 26 }
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
    gridPos = { h = 4, w = local.panel_width, x = idx * local.panel_width, y = 31 }
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

  # ── Alert rules summary text panel ─────────────────────────────────────────

  _alert_summary_md = join("\n\n", [for r in local.alert_rules :
    "**${r.name}** `${r.severity}`  \n${r.condition}  \nChannels: `${join("`, `", r.channels)}`  \nRunbook: `${r.runbook}`"
  ])

  _alerts_text_panel_json = jsonencode({
    gridPos = { h = 10, w = 24, x = 0, y = 36 }
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
    [local._row_live_json],
    local._live_latency_panel_jsons,
    local._live_errorrate_panel_jsons,
    local._live_tps_panel_jsons,
    [local._row_thresholds_json],
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
