# TerraForm_01 — SRE Reliability Demo

A Terraform project demonstrating SRE/DevOps/IaC patterns for transaction services, including
multi-environment configuration, operational alert generation, reliability metric computation,
and a Grafana dashboard ready for import.

---

## What this project demonstrates

| Concept | Implementation |
|---|---|
| Reusable module design | `modules/service-monitoring/` encapsulates all reliability logic |
| Environment lifecycle | `envs/dev.tfvars` → `staging.tfvars` → `prod.tfvars` with progressive thresholds |
| SLO-based alerting | Three alert types per service, generated from variables |
| Error budget math | Computed outputs: `error_budget_minutes`, `max_allowable_downtime_minutes` |
| Live Grafana dashboard | `grafana-dashboard.generated.json` — import directly to Grafana Cloud |
| CI/CD best practices | Format check, validate, plan with GitHub Actions step summary |

---

## Project structure

```
.
├── main.tf                          # Root: calls module, creates generated files
├── variables.tf                     # Root inputs (project, environment, services, alerts)
├── outputs.tf                       # Root outputs (endpoints, reliability metrics, file paths)
├── envs/
│   ├── dev.tfvars                   # Dev: lenient thresholds, fast iteration
│   ├── staging.tfvars               # Staging: tighter thresholds, pre-prod validation
│   └── prod.tfvars                  # Prod: near-five-nines SLO, PagerDuty escalation
└── modules/
    └── service-monitoring/
        ├── variables.tf             # Module inputs
        ├── main.tf                  # All reliability logic and dashboard generation
        └── outputs.tf               # Computed values exposed to root module
```

---

## Quick start

```bash
terraform init

# Choose an environment:
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars -auto-approve
```

After apply, Terraform generates three artifacts in the root directory:

| File | Description |
|---|---|
| `deployment.generated.yaml` | Deployment manifest with service endpoints and SLO config |
| `alerts.generated.json` | 3 alert rules per service (transaction drop, uptime drop, deployment anomaly) |
| `grafana-dashboard.generated.json` | Grafana dashboard JSON — import directly to Grafana Cloud |

---

## Multi-environment promotion

Each environment has progressively stricter reliability thresholds:

| Setting | dev | staging | prod |
|---|---|---|---|
| SLO target | 99.0% | 99.5% | 99.95% |
| Latency threshold | 1000 ms | 600 ms | 400 ms |
| Error rate threshold | 5.0% | 2.0% | 0.5% |
| Retry count | 5 | 3 | 2 |
| Alert channel | `#sre-dev` | `#sre-staging` | `#sre-prod` + PagerDuty |

```bash
# Promote through environments:
terraform apply -var-file=envs/dev.tfvars     -auto-approve
terraform apply -var-file=envs/staging.tfvars -auto-approve
terraform apply -var-file=envs/prod.tfvars    -auto-approve
```

---

## Grafana dashboard import

The generated `grafana-dashboard.generated.json` uses Grafana's built-in **TestData** datasource —
no datasource configuration required.

**Steps:**

1. Sign up at [grafana.com](https://grafana.com) (free tier, no credit card needed)
2. In your Grafana instance, go to **Dashboards → Import**
3. Upload `grafana-dashboard.generated.json`
4. When prompted, select **TestData DB** as the datasource
5. Click **Import**

The dashboard contains 12 panels across three rows:

- **Service SLO and Error Budget** — gauge (SLO %) + stat (error budget mins/month) per service
- **Latency and Error Rate Thresholds** — gauge (ms) + stat (error %) per service
- **Generated Alert Rules** — markdown summary of all alert rules with runbook links

> **Tip:** Change the environment and re-apply to regenerate the dashboard with different thresholds, then re-import to Grafana to see the values update.

---

## Reliability outputs

After `terraform apply`, the `service_reliability` output shows computed SLO math:

```
service_reliability = {
  "payment-api" = {
    "slo_target"                     = 99.95
    "error_budget_minutes"           = 21.9       # ← (1 - 0.9995) × 43800
    "max_allowable_downtime_minutes" = 21.9
  }
  "transaction-worker" = {
    "slo_target"                     = 99.9
    "error_budget_minutes"           = 43.8       # ← (1 - 0.999) × 43800
    "max_allowable_downtime_minutes" = 43.8
  }
}
```

These figures answer the interview question *"what did you commit to, and how much runway do you have?"*

---

## Alert rules

Three alert types are generated for every service in `alerts.generated.json`:

| Type | Trigger | Severity |
|---|---|---|
| `transaction_drop` | Transaction rate < 80% of expected baseline TPS | critical |
| `uptime_drop` | Health probe fails N consecutive times (N = `retry_count`) | critical |
| `deployment_anomaly` | Error rate exceeds threshold within 5 min post-deploy window | warning |

Each rule includes `severity`, `channels`, and a `runbook` URL — matching the structure of
real Prometheus/Alertmanager or Grafana Alerting rule groups.

---

## CI/CD

GitHub Actions workflow at `.github/workflows/terraform-ci.yml`:

1. **Terraform Fmt Check** — enforces consistent formatting
2. **Terraform Init** — initialises providers without a backend
3. **Terraform Validate** — validates all modules and root config
4. **Terraform Plan (dev)** — runs a full plan against `envs/dev.tfvars`
5. **Post Plan to Step Summary** — appends the plan diff to the GitHub Actions run summary, mirroring how teams use Atlantis or Terraform Cloud

---

## 🎙️ Interview walkthrough

> Use this script to narrate a live demo.

**"Walk me through your Terraform setup."**

> "I'll start from the service definitions and trace through to the live Grafana dashboard."

**Step 1 — Define services once, reuse everywhere**

Open `variables.tf`. Every service has: name, port, health path, retry count, SLO target,
latency threshold, and error rate threshold. These drive everything downstream — no duplication.

**Step 2 — Choose your environment**

```bash
terraform plan -var-file=envs/prod.tfvars
```

Point out `envs/prod.tfvars`: retry count drops to 2, SLO goes to 99.95%, latency tightens to
400 ms, and PagerDuty joins the alert channels. One file flip — all generated artifacts reflect prod standards.

**Step 3 — Apply and see what Terraform produces**

```bash
terraform apply -var-file=envs/prod.tfvars -auto-approve
```

Three files are created:
- `deployment.generated.yaml` — handed to the deploy pipeline
- `alerts.generated.json` — 6 alert rules (3 per service), ready to feed into Alertmanager
- `grafana-dashboard.generated.json` — import this into Grafana Cloud right now

**Step 4 — Show the Grafana dashboard**

Import the JSON. The SLO gauges show 99.95% with a green threshold, error budget stats show
21.9 mins/month, and the latency gauges show 400 ms. All values trace back to a single `tfvars` file.

**Step 5 — Explain the error budget math**

> "The `error_budget_minutes` output is `(1 - SLO) × 43800`. For 99.95%, that's 21.9 minutes per
> month of allowable downtime. That's the number I'd use to have a conversation with product about
> deployment risk and change freeze windows."

**Step 6 — Show the CI plan in GitHub Actions**

Every PR runs a `terraform plan` against dev and posts the diff to the Actions run summary —
the same visibility pattern teams use with Atlantis. No cloud credentials required.

---

## Cleanup

```bash
terraform destroy -var-file=envs/dev.tfvars -auto-approve
```

