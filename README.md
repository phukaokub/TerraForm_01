# TerraForm_01

A starter Terraform project to demonstrate SRE/DevOps/CI-CD concepts for transaction services.

## What this project demonstrates

This Terraform setup models a basic reliability workflow similar to real-world platform operations:
- Service configuration (name, port, health path, retry count, SLO/threshold values)
- Generated deployment manifest (`deployment.generated.yaml`)
- Generated monitoring dashboard config (`dashboard.generated.json`)
- Alert channels configuration (e.g., Slack channel alias)

It is intentionally cloud-agnostic, so you can run and explain it in interviews without cloud credentials.

## Files

- `main.tf` - core Terraform logic and generated monitoring/deployment artifacts
- `variables.tf` - configurable project/service/alert inputs
- `outputs.tf` - exported endpoints and generated file paths
- `terraform.tfvars.example` - sample override values

## Quick start

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

After apply, Terraform will generate:
- `deployment.generated.yaml`
- `dashboard.generated.json`

## Customize

1. Copy and edit variables:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Update service definitions and alert channels in `terraform.tfvars`
3. Re-run:
   ```bash
   terraform plan
   terraform apply -auto-approve
   ```

## Cleanup

```bash
terraform destroy -auto-approve
```

## CI/CD

This repository includes a GitHub Actions workflow at `.github/workflows/terraform-ci.yml` that runs:
- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
