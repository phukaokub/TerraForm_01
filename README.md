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

## Grafana Cloud setup (for live dashboard push)

The CI workflow pushes `grafana-dashboard.generated.json` directly to your Grafana Cloud instance on every apply. Three GitHub Actions secrets are required:

| Secret | Value |
|---|---|
| `GRAFANA_URL` | Your Grafana Cloud stack URL, e.g. `https://yourorg.grafana.net` |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Service account token with **Editor** role (see steps below) |
| `GRAFANA_FOLDER_UID` | *(optional)* Folder UID to import into; leave empty for the General folder |

**Create a service account token in Grafana Cloud:**

1. Open your Grafana instance → **Administration → Service accounts → Add service account**
2. Name it `terraform-ci`, role **Editor** → **Create**
3. Click **Add service account token** → copy the token
4. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**
   - `GRAFANA_SERVICE_ACCOUNT_TOKEN` = the copied token
   - `GRAFANA_URL` = `https://yourorg.grafana.net`

Once these secrets are set, every push/PR will:
1. Run `terraform apply` with a new `run_seed` (`$GITHUB_RUN_NUMBER`)
2. Generate a fresh `grafana-dashboard.generated.json` with randomised Live Snapshot values
3. Push the dashboard directly to Grafana — just **refresh your browser** to see updated metrics

> **No secrets set?** The push step exits cleanly with a skip message — the rest of the CI pipeline is unaffected.

---

## Grafana dashboard — panels

The dashboard has four rows:

| Row | Panels | Data |
|---|---|---|
| **Service SLO and Error Budget** | SLO gauge + error budget stat | Configured targets (static) |
| **Live Snapshot** | Current latency gauge + error rate stat + TPS stat | Randomised each deploy via `run_seed` |
| **Configured Thresholds** | Latency threshold gauge + error rate threshold stat | Configured thresholds (static) |
| **Generated Alert Rules** | Alert rules markdown | Generated from variables |

The "Live Snapshot" row is the key demo row — its values change on every CI run. Panels go **green** when within threshold, **yellow** when approaching the limit, and **red** when breached.

**Import manually (no Grafana secrets needed):**

1. Download the `grafana-dashboard-dev` artifact from the latest Actions run
2. In Grafana: **Dashboards → Import → Upload JSON file**
3. Select **TestData DB** as the datasource → **Import**

---

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
4. **Terraform Plan (dev)** — runs a full plan against `envs/dev.tfvars` and posts diff to the Actions step summary
5. **Terraform Apply (dev)** — applies with `run_seed=$GITHUB_RUN_NUMBER`; every run produces a different random Live Snapshot
6. **Push Dashboard to Grafana Cloud** — uses `curl` + the Grafana import API to push the generated dashboard; skips gracefully if `GRAFANA_URL` / `GRAFANA_SERVICE_ACCOUNT_TOKEN` secrets are not set
7. **Upload Grafana Dashboard Artifact** — uploads `grafana-dashboard.generated.json` as a fallback for manual import

**Presentation demo flow:**

1. Open your Grafana dashboard in one browser tab
2. Create or push to this PR — watch the Actions run
3. When the run completes, refresh Grafana — the Live Snapshot row shows new metric values
4. Repeat to show different random states (some green, some yellow/red)

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

