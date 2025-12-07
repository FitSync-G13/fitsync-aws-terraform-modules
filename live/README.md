# FitSync Live Infrastructure

## Directory Structure

```
live/
├── shared/                    # Shared ECR repository (common to all environments)
├── prod/                      # Production environment
│   ├── hub/                   # Production hub (10.0.0.0/16)
│   └── spoke/                 # Production spoke (10.1.0.0/16)
└── non-prod/                  # Non-production environment
    ├── hub/                   # Non-prod hub (10.10.0.0/16)
    ├── spoke-dev/             # Development spoke (10.11.0.0/16)
    └── spoke-stage/           # Staging spoke (10.12.0.0/16)
```

## Network Architecture

### Shared Layer
- **ECR Repository**: Common across all environments
- **Region**: us-east-2

### Production Environment
- **Hub VPC**: 10.0.0.0/16 (prod-hub)
- **Spoke VPC**: 10.1.0.0/16 (prod-spoke)
- **Domain**: fitsync.online (root)

### Non-Production Environment
- **Hub VPC**: 10.10.0.0/16 (non-prod-hub)
- **Dev Spoke VPC**: 10.11.0.0/16 (dev-spoke)
- **Stage Spoke VPC**: 10.12.0.0/16 (stage-spoke)
- **Domains**: 
  - dev.fitsync.online
  - stage.fitsync.online

## Deployment Order

### Initial Setup (One-time)
```bash
# 1. Deploy shared ECR
cd shared
terraform init
terraform plan
terraform apply
```

### Production Environment
```bash
# 2. Deploy production hub
cd prod/hub
terraform init
terraform plan
terraform apply

# 3. Deploy production spoke
cd prod/spoke
terraform init
terraform plan
terraform apply
```

### Non-Production Environment
```bash
# 4. Deploy non-prod hub
cd non-prod/hub
terraform init
terraform plan
terraform apply

# 5. Deploy dev spoke
cd non-prod/spoke-dev
terraform init
terraform plan
terraform apply

# 6. Deploy stage spoke
cd non-prod/spoke-stage
terraform init
terraform plan
terraform apply
```

## Configuration Summary

| Environment | Layer | VPC CIDR | Env Name | Deployment Env | Domain |
|-------------|-------|----------|----------|----------------|--------|
| Shared | ECR | N/A | shared | N/A | N/A |
| Production | Hub | 10.0.0.0/16 | prod-hub | production | N/A |
| Production | Spoke | 10.1.0.0/16 | prod-spoke | production | fitsync.online |
| Non-Prod | Hub | 10.10.0.0/16 | non-prod-hub | staging | N/A |
| Non-Prod | Dev Spoke | 10.11.0.0/16 | dev-spoke | development | dev.fitsync.online |
| Non-Prod | Stage Spoke | 10.12.0.0/16 | stage-spoke | staging | stage.fitsync.online |

## Instance Configuration

All environments use the same instance configuration:
- **Master Nodes**: 1x t3.medium
- **Worker Nodes**: 1x t3.medium
- **Database Nodes**: 1x t3.medium
- **DB Volume**: 50 GB gp3
- **Region**: us-east-2

## Secret Files

Each spoke directory should have a `conf.secret.auto.tfvars` file containing:
**Spoke directories** (prod/spoke, non-prod/spoke-dev, non-prod/spoke-stage):
```hcl
github_token           = "your-github-token"
cloudflare_api_token   = "your-cloudflare-token"
```

## Quick Commands

```bash
# Plan all environments
for env in shared prod/hub prod/spoke non-prod/hub non-prod/spoke-dev non-prod/spoke-stage; do
  echo "=== Planning $env ==="
  (cd $env && terraform plan)
done

# Apply specific environment
cd <environment-path>
terraform apply

# Destroy specific environment (reverse order)
cd <environment-path>
terraform destroy
```

## Notes

- Shared ECR is deployed once and used by all environments
- Production and non-production have separate hub-spoke architectures
- All spokes connect to their respective hub via Transit Gateway
- SSH keys are shared across all environments (../../../ssh-keys/aws-key.pub)
