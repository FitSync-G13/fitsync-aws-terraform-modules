# FitSync Complete Setup Guide

## Project Overview

**FitSync** is a self-managed Kubernetes infrastructure on AWS using:
- **Terraform**: Infrastructure as Code (Hub-Spoke VPC architecture)
- **K3s**: Lightweight Kubernetes distribution with ECR integration
- **Istio**: Service mesh with mTLS
- **Cilium**: CNI for networking
- **cert-manager**: Automated TLS certificate management
- **Helm**: Package manager for Kubernetes applications
- **GitHub Actions**: CI/CD pipeline for automated deployments
- **AWS Secrets Manager**: Secure secret storage and management

## Repository Structure

```
fitsync-aws-terraform-modules/          # Infrastructure (Terraform)
├── modules/
│   ├── shared/                         # ECR repository
│   ├── hub/                            # Hub VPC (NAT, TGW, Bastion) - No GitHub integration
│   └── spoke/                          # Spoke VPC (K3s, ALB, NLB, IAM, GitHub, Secrets)
├── live/
│   ├── shared/                         # Shared ECR (common to all)
│   ├── prod/
│   │   ├── hub/                        # Production hub
│   │   └── spoke/                      # Production spoke
│   └── non-prod/
│       ├── hub/                        # Non-prod hub
│       ├── spoke-dev/                  # Development spoke
│       └── spoke-stage/                # Staging spoke
├── ssh-keys/                           # SSH keys for EC2 access
├── ssh-config                          # SSH configuration
└── README.md                           # Architecture documentation

fitsync-cd-templates/                   # Reusable workflow templates
└── .github/workflows/
    ├── k3s-install-modular.yml         # K3s installation with ECR integration
    ├── cilium-install.yml              # Cilium CNI
    ├── istio-install.yml               # Istio service mesh
    ├── cert-manager-install.yml        # cert-manager
    ├── wildcard-cert.yml               # TLS certificate creation
    ├── istio-gateway-https.yml         # Istio Gateway with HTTPS
    ├── istio-sample-app.yml            # Sample app deployment
    ├── database-setup-enhanced.yml     # PostgreSQL + Redis with TLS
    └── fitsync-helm-deploy.yml         # FitSync Helm chart deployment

fitsync-cd/                             # Main deployment workflow
└── .github/workflows/
    └── k3s-deploy.yml                  # Orchestrates all deployments

fitsync-helm-chart/                     # FitSync application Helm chart
└── fitsync/                            # Main chart directory
    ├── Chart.yaml                     # Chart metadata
    ├── values.yaml                    # Default values
    └── templates/                     # Kubernetes manifests
```

## Architecture

### Multi-Environment Hub-Spoke Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARED LAYER                             │
│  ECR Repository: fitsync-ecr (common to all environments)  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              PRODUCTION ENVIRONMENT                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HUB VPC (10.0.0.0/16) - prod-hub                  │   │
│  │  NAT Gateway | Transit Gateway | Bastion           │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  SPOKE VPC (10.1.0.0/16) - prod-spoke              │   │
│  │  K3s Cluster | ALB | IAM OIDC | GitHub Integration │   │
│  │  Domain: *.fitsync.online                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              NON-PRODUCTION ENVIRONMENT                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HUB VPC (10.10.0.0/16) - non-prod-hub             │   │
│  │  NAT Gateway | Transit Gateway | Bastion           │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  DEV SPOKE (10.11.0.0/16) - dev-spoke              │   │
│  │  K3s Cluster | ALB | GitHub Integration            │   │
│  │  Domain: *.dev.fitsync.online                      │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  STAGE SPOKE (10.12.0.0/16) - stage-spoke          │   │
│  │  K3s Cluster | ALB | GitHub Integration            │   │
│  │  Domain: *.stage.fitsync.online                    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Key Architecture Changes

1. **Hub Module Simplified**: No GitHub integration, no IAM roles - purely networking
2. **Spoke Module Self-Contained**: Each spoke creates its own IAM OIDC provider (prod-spoke) or references existing (dev/stage), IAM roles, and GitHub environment
3. **OIDC Provider Sharing**: prod-spoke creates the OIDC provider, dev/stage spokes use data source to reference it
4. **Subdomain Support**: Certificates and DNS records properly use subdomain_prefix for multi-environment support
5. **Cloudflare Ruleset**: Only created by prod-spoke (one per zone limit)

### Traffic Flow

```
Internet → Cloudflare → ALB (Hub VPC) → TGW → Istio Gateway (Spoke) → App Pods
                ↓
         TLS Termination (ACM)
                ↓
         HTTPS to Istio (30443)
                ↓
         TLS Re-encryption (Let's Encrypt)
```

## Network Allocation

| Environment | Component | VPC CIDR | Env Name | Domain |
|-------------|-----------|----------|----------|--------|
| Shared | ECR | N/A | shared | N/A |
| Production | Hub | 10.0.0.0/16 | prod-hub | N/A |
| Production | Spoke | 10.1.0.0/16 | prod-spoke | *.fitsync.online |
| Non-Prod | Hub | 10.10.0.0/16 | non-prod-hub | N/A |
| Non-Prod | Dev Spoke | 10.11.0.0/16 | dev-spoke | *.dev.fitsync.online |
| Non-Prod | Stage Spoke | 10.12.0.0/16 | stage-spoke | *.stage.fitsync.online |

## Prerequisites

### Local Tools
```bash
# Required
terraform >= 1.0
aws-cli >= 2.0
ssh
git

# Optional (for manual operations)
kubectl
istioctl
```

### AWS Account
- AWS Account with admin access
- Sufficient permissions to create IAM OIDC providers, roles, VPCs, EC2, etc.

### Cloudflare Account
- Domain managed in Cloudflare (fitsync.online)
- API token with DNS edit permissions

### GitHub
- Repository access to all three repos
- GitHub Actions enabled
- Personal access token for managing secrets/variables

## Initial Setup

### 1. Generate SSH Keys

```bash
cd fitsync-aws-terraform-modules
./generate-keys.sh
# Creates: ssh-keys/aws-key and ssh-keys/aws-key.pub
```

### 2. Configure Secret Files

Create `conf.secret.auto.tfvars` files:

**Hub directories** (prod/hub, non-prod/hub):
```hcl
# No secrets needed - hub doesn't use GitHub
```

**Spoke directories** (prod/spoke, non-prod/spoke-dev, non-prod/spoke-stage):
```hcl
github_token         = "ghp_your_github_personal_access_token"
cloudflare_api_token = "your_cloudflare_api_token"
```

### 3. Deploy Infrastructure with Terraform

#### Deployment Order

**Production Environment:**
```bash
# 1. Shared ECR (once)
cd live/shared
terraform init && terraform apply

# 2. Production Hub
cd live/prod/hub
terraform init && terraform apply

# 3. Production Spoke
cd live/prod/spoke
terraform init && terraform apply
```

**Non-Production Environment:**
```bash
# 4. Non-Prod Hub
cd live/non-prod/hub
terraform init && terraform apply

# 5. Dev Spoke
cd live/non-prod/spoke-dev
terraform init && terraform apply

# 6. Stage Spoke
cd live/non-prod/spoke-stage
terraform init && terraform apply
```

### 4. What Gets Created

#### Shared Layer
- ECR repository: `fitsync-ecr`
- Lifecycle policies (delete untagged images > 14 days)
- Repository access policies

#### Hub (prod-hub, non-prod-hub)
- VPC with public/private subnets (multi-AZ)
- Internet Gateway
- NAT Gateways (multi-AZ for HA)
- Transit Gateway
- Bastion host (public subnet)
- SSH key pair
- Security groups

#### Spoke (prod-spoke, dev-spoke, stage-spoke)
- VPC with private subnets only (multi-AZ)
- TGW attachment and routing
- VPC endpoints (ECR API, ECR Docker, S3)
- K3s master nodes (configurable count) with ECR credential provider
- K3s worker nodes (configurable count) with ECR credential provider
- Database nodes (configurable count)
- Internal NLB (K3s API on port 6443)
- Public ALB (HTTPS on port 443) in hub VPC
- IAM OIDC provider (prod-spoke creates, others reference)
- IAM role for GitHub Actions (per spoke)
- IAM role with ECR read permissions for all EC2 instances
- GitHub environment with variables/secrets
- ACM certificate (wildcard for domain)
- Cloudflare DNS records (automatic validation)
- Cloudflare transform ruleset (prod-spoke only)
- Security groups
- EBS volumes for databases
- **JWT Secrets**: Secure random JWT_SECRET and JWT_REFRESH_SECRET in AWS Secrets Manager
- **Database Secrets**: Connection strings for all databases stored in AWS Secrets Manager

### 5. Configure SSH Access

```bash
# Update ssh-config with bastion IPs
vim ssh-config

# Test SSH - Production
ssh -F ssh-config prod-bastion
ssh -F ssh-config prod-master1

# Test SSH - Non-Production
ssh -F ssh-config nonprod-bastion
ssh -F ssh-config dev-master1
ssh -F ssh-config stage-master1
```

### 6. Configure Cloudflare DNS

Terraform automatically creates DNS records, but verify:

**Production:**
```
*.fitsync.online → prod-alb-dns-name (CNAME, Proxied)
fitsync.online → prod-alb-dns-name (CNAME, Proxied)
www.fitsync.online → prod-alb-dns-name (CNAME, Proxied)
```

**Development:**
```
*.dev.fitsync.online → dev-alb-dns-name (CNAME, Proxied)
dev.fitsync.online → dev-alb-dns-name (CNAME, Proxied)
```

**Staging:**
```
*.stage.fitsync.online → stage-alb-dns-name (CNAME, Proxied)
stage.fitsync.online → stage-alb-dns-name (CNAME, Proxied)
```

## Configuration Files

### Shared (`live/shared/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "shared"
enable_deletion_protection = false
```

### Production Hub (`live/prod/hub/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "prod-hub"
vpc_cidr                   = "10.0.0.0/16"
admin_cidr                 = "0.0.0.0/0"
public_key_path            = "../../../ssh-keys/aws-key.pub"
enable_deletion_protection = false
```

### Production Spoke (`live/prod/spoke/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "prod-spoke"
hub_env                    = "prod-hub"
vpc_cidr                   = "10.1.0.0/16"
master_count               = 1
worker_count               = 1
db_count                   = 1
db_vol_size                = 50
master_instance_type       = "t3.medium"
worker_instance_type       = "t3.medium"
db_instance_type           = "t3.medium"
public_key_path            = "../../../ssh-keys/aws-key.pub"
github_repo                = "FitSync-G13/fitsync-cd"
deployment_environment     = "production"
domain_name                = "fitsync.online"
subdomain_prefix           = ""
enable_deletion_protection = false
```

### Non-Prod Hub (`live/non-prod/hub/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "non-prod-hub"
vpc_cidr                   = "10.10.0.0/16"
admin_cidr                 = "0.0.0.0/0"
public_key_path            = "../../../ssh-keys/aws-key.pub"
enable_deletion_protection = false
```

### Dev Spoke (`live/non-prod/spoke-dev/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "dev-spoke"
hub_env                    = "non-prod-hub"
vpc_cidr                   = "10.11.0.0/16"
master_count               = 1
worker_count               = 1
db_count                   = 1
db_vol_size                = 50
master_instance_type       = "t3.medium"
worker_instance_type       = "t3.medium"
db_instance_type           = "t3.medium"
public_key_path            = "../../../ssh-keys/aws-key.pub"
github_repo                = "FitSync-G13/fitsync-cd"
deployment_environment     = "development"
domain_name                = "fitsync.online"
subdomain_prefix           = "dev"
enable_deletion_protection = false
```

### Stage Spoke (`live/non-prod/spoke-stage/conf.auto.tfvars`)
```hcl
project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "stage-spoke"
hub_env                    = "non-prod-hub"
vpc_cidr                   = "10.12.0.0/16"
master_count               = 1
worker_count               = 1
db_count                   = 1
db_vol_size                = 50
master_instance_type       = "t3.medium"
worker_instance_type       = "t3.medium"
db_instance_type           = "t3.medium"
public_key_path            = "../../../ssh-keys/aws-key.pub"
github_repo                = "FitSync-G13/fitsync-cd"
deployment_environment     = "staging"
domain_name                = "fitsync.online"
subdomain_prefix           = "stage"
enable_deletion_protection = false
```

## ECR Integration and Secret Management

### ECR Credential Provider Integration

**Automatic ECR Access**: All K3s nodes (masters and workers) are configured with ECR credential provider for seamless container image pulling.

**Components**:
- **ECR Credential Provider Binary**: Downloaded and installed on all nodes (`/usr/local/bin/ecr-credential-provider`)
- **Configuration File**: `/etc/kubernetes/ecr-credential-provider.json` with proper `CredentialProviderConfig` format
- **Kubelet Integration**: K3s configured with `--kubelet-arg=image-credential-provider-config` and `--kubelet-arg=image-credential-provider-bin-dir`
- **IAM Permissions**: EC2 instances have `AmazonEC2ContainerRegistryReadOnly` policy attached

**Configuration Format**:
```json
{
  "kind": "CredentialProviderConfig",
  "apiVersion": "kubelet.config.k8s.io/v1",
  "providers": [
    {
      "name": "ecr-credential-provider",
      "matchImages": [
        "*.dkr.ecr.*.amazonaws.com",
        "*.dkr.ecr.*.amazonaws.com.cn"
      ],
      "apiVersion": "credentialprovider.kubelet.k8s.io/v1",
      "defaultCacheDuration": "12h"
    }
  ]
}
```

### AWS Secrets Manager Integration

**Secure Secret Storage**: All sensitive configuration is stored in AWS Secrets Manager with environment-specific paths.

**Secret Categories**:

1. **Database Connection Strings**:
   - `fitsync/{environment}/userdb-db-url`
   - `fitsync/{environment}/trainingdb-db-url`
   - `fitsync/{environment}/scheduledb-db-url`
   - `fitsync/{environment}/progressdb-db-url`
   - `fitsync/{environment}/redis-url`

2. **JWT Authentication Secrets** (Generated by Terraform):
   - `fitsync/{environment}/jwt-secret` (64-character secure random)
   - `fitsync/{environment}/jwt-refresh-secret` (64-character secure random)

**Secret Management**:
- **Creation**: Database secrets created by `database-setup-enhanced.yml`, JWT secrets by Terraform
- **Access**: IAM roles have `secretsmanager:GetSecretValue` permissions for environment-specific secrets
- **Rotation**: Secrets can be rotated independently without infrastructure changes

### FitSync Helm Chart Deployment

**Automated Application Deployment**: Complete FitSync microservices deployment using Helm with secure secret injection.

**Deployment Process**:
1. **Secret Retrieval**: Gets all secrets from AWS Secrets Manager for the target environment
2. **Helm Installation**: Installs Helm on K3s master node if not present
3. **Chart Deployment**: Deploys FitSync chart with environment-specific values override
4. **Rolling Restart**: Ensures all pods pick up new secrets
5. **Verification**: Comprehensive status checks for deployment health

**Services Deployed**:
- **User Service**: Authentication and user management
- **Training Service**: Workout and training data
- **Schedule Service**: Scheduling and calendar functionality
- **Progress Service**: Progress tracking and analytics
- **API Gateway**: Central API routing and authentication
- **Notification Service**: Push notifications and alerts

**Values Override Example**:
```yaml
userService:
  env:
    DATABASE_URL: "postgresql://user:pass@db.domain:5432/userdb?sslmode=require"
    JWT_SECRET: "secure-64-char-random-string"
    JWT_REFRESH_SECRET: "secure-64-char-random-string"
    REDIS_URL: "rediss://db.domain:6379"
```

## GitHub Actions Integration

### How It Works

1. **Spoke Terraform** creates GitHub environment (production/development/staging)
2. **Environment Variables** are automatically set:
   - `AWS_REGION`: us-east-2
   - `PROJECT_NAME`: fitsync
   - `HUB_ENV`: prod-hub or non-prod-hub
   - `SPOKE_ENV`: prod-spoke, dev-spoke, or stage-spoke
   - `VPC_CIDR`: Spoke VPC CIDR
   - `MASTER_COUNT`, `WORKER_COUNT`: Node counts
   - `DOMAIN_NAME`, `SUBDOMAIN_PREFIX`: Domain configuration

3. **Environment Secrets** are automatically set:
   - `AWS_ROLE_ARN`: IAM role for OIDC authentication
   - `CLOUDFLARE_API_TOKEN`: For DNS management

4. **GitHub Actions** workflows can now deploy to each environment using OIDC authentication

### Accessing AWS from GitHub Actions

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
```

## Important Architecture Notes

### IAM OIDC Provider

- **Created by**: prod-spoke only (first spoke deployed)
- **Used by**: All spokes (dev/stage reference via data source)
- **Why**: AWS allows only one OIDC provider per URL per account
- **Implication**: Deploy prod-spoke before dev/stage spokes

### Cloudflare Transform Ruleset

- **Created by**: prod-spoke only
- **Why**: Cloudflare allows only one transform ruleset per zone per phase
- **Implication**: Non-prod spokes don't create this ruleset
- **Impact**: Minimal - ruleset adds header for ALB validation

### ACM Certificate Validation

- **Method**: DNS validation via Cloudflare
- **Automation**: Terraform creates DNS validation records automatically
- **Domains**:
  - Prod: `*.fitsync.online` + `fitsync.online`
  - Dev: `*.dev.fitsync.online` + `dev.fitsync.online`
  - Stage: `*.stage.fitsync.online` + `stage.fitsync.online`
- **Validation Time**: 5-10 minutes (timeout: 45 minutes)

### Subdomain Prefix Logic

- **Empty string** (`""`): Root domain (production)
  - Certificate: `*.fitsync.online`
  - DNS: `*.fitsync.online`, `fitsync.online`, `www.fitsync.online`
  
- **Non-empty** (`"dev"`, `"stage"`): Subdomain
  - Certificate: `*.dev.fitsync.online`
  - DNS: `*.dev.fitsync.online`, `dev.fitsync.online`

## Troubleshooting

### Common Issues

#### 1. OIDC Provider Already Exists (Non-Prod Spokes)

**Error**: `EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists`

**Cause**: prod-spoke already created it

**Solution**: This is expected and handled automatically via data source

#### 2. Cloudflare DNS Record Already Exists

**Error**: `An A, AAAA, or CNAME record with that host already exists`

**Cause**: Duplicate DNS records or previous deployment

**Solution**:
```bash
# Check Cloudflare dashboard for duplicate records
# Or import existing record:
terraform import 'module.spoke.cloudflare_dns_record.wildcard[0]' <zone-id>/<record-id>
```

#### 3. Certificate Validation Timeout

**Error**: Certificate stuck in "Pending Validation"

**Cause**: DNS validation records not created or propagated

**Solution**:
```bash
# Check ACM console for validation records
# Verify DNS records in Cloudflare
# Wait up to 45 minutes for validation
```

#### 4. Cloudflare Ruleset Limit

**Error**: `exceeded maximum number of zone rulesets for phase http_request_late_transform`

**Cause**: Trying to create ruleset in non-prod spoke

**Solution**: This is fixed - only prod-spoke creates ruleset (check `var.env == "prod-spoke"`)

### Verification Commands

```bash
# Check Terraform outputs
cd live/prod/spoke
terraform output

# Check AWS resources
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=fitsync"
aws iam list-open-id-connect-providers
aws acm list-certificates --region us-east-2

# Check GitHub environment
# Go to: GitHub repo → Settings → Environments → production
```

## Cost Estimate

### Per Environment

**Hub:**
- NAT Gateway (2x): $64/month
- Bastion (t3.micro): $7/month
- **Subtotal**: ~$71/month

**Spoke:**
- K3s Masters (1x t3.medium): $30/month
- K3s Workers (1x t3.medium): $30/month
- Database (1x t3.medium): $30/month
- ALB: $16/month
- NLB: $16/month
- EBS (150GB): $15/month
- **Subtotal**: ~$137/month

### Total Infrastructure

- Shared ECR: $1/month
- Production (hub + spoke): $208/month
- Non-Prod (hub + 2 spokes): $345/month
- **Grand Total**: ~$554/month

## Maintenance

### Adding New Spoke

```bash
# 1. Copy configuration
cp -r live/non-prod/spoke-dev live/non-prod/spoke-test

# 2. Update conf.auto.tfvars
vim live/non-prod/spoke-test/conf.auto.tfvars
# Change: env, vpc_cidr, subdomain_prefix, deployment_environment

# 3. Deploy
cd live/non-prod/spoke-test
terraform init && terraform apply
```

### Destroying Resources

**Reverse order:**
```bash
# Spokes first
cd live/non-prod/spoke-stage && terraform destroy
cd live/non-prod/spoke-dev && terraform destroy
cd live/prod/spoke && terraform destroy

# Hubs
cd live/non-prod/hub && terraform destroy
cd live/prod/hub && terraform destroy

# Shared (last)
cd live/shared && terraform destroy
```

## Quick Reference

### Directory Structure
```
live/
├── shared/              # ECR (deploy once)
├── prod/
│   ├── hub/            # 10.0.0.0/16
│   └── spoke/          # 10.1.0.0/16 → *.fitsync.online
└── non-prod/
    ├── hub/            # 10.10.0.0/16
    ├── spoke-dev/      # 10.11.0.0/16 → *.dev.fitsync.online
    └── spoke-stage/    # 10.12.0.0/16 → *.stage.fitsync.online
```

### Important Files
```
ssh-keys/aws-key                    # Private SSH key
ssh-config                          # SSH configuration
live/*/conf.auto.tfvars            # Public configuration
live/*/conf.secret.auto.tfvars     # Secrets (gitignored)
```

### Key Outputs
```bash
# Get bastion IPs
terraform output bastion_public_ip

# Get ALB DNS
terraform output alb_dns_name

# Get K3s API endpoint
terraform output k3s_api_dns

# Get IAM role ARN
terraform output github_actions_role_arn
```

## CD Pipeline Architecture

### Enhanced Pipeline Flow

```
GitHub Actions Trigger
    ↓
0. Install ECR Credential Provider (All Nodes)
    ↓
1. Install K3s (Masters → Workers) with ECR Integration
    ↓
2. Install Cilium CNI
    ↓
3. Install Istio Service Mesh
    ↓
4. Install cert-manager
    ↓
5. Create Wildcard Certificate (Let's Encrypt)
    ↓
6. Deploy Istio Gateway with HTTPS
    ↓
7. Setup Enhanced Database (PostgreSQL + Redis + TLS)
    ↓
8. Deploy FitSync Application (Helm Chart) OR Sample Application
```

### Workflow Templates (fitsync-cd-templates)

#### k3s-install-modular.yml
- **ECR Integration**: Installs ECR credential provider on all nodes before K3s
- **Split Jobs**: `install-ecr-credential-provider` → `install-k3s-masters` → `install-k3s-workers`
- **Credential Provider Config**: Proper `CredentialProviderConfig` with required `kind` field
- **Kubelet Arguments**: `--kubelet-arg=image-credential-provider-config=/etc/kubernetes/ecr-credential-provider.json`
- **Version Management**: Configurable ECR credential provider version (default: latest)
- **Timeout Handling**: Extended timeouts for worker installation (15 minutes)

#### database-setup-enhanced.yml
- **Multi-Database Support**: Creates userdb, trainingdb, scheduledb, progressdb
- **Redis Integration**: Installs Redis with TLS support
- **TLS Configuration**: Let's Encrypt certificates for both PostgreSQL and Redis
- **Secret Management**: Stores connection strings in AWS Secrets Manager
- **Idempotent**: Checks existing databases and secrets before creation
- **Auto-Renewal**: Configures certificate auto-renewal hooks

#### fitsync-helm-deploy.yml (NEW)
- **Secret Retrieval**: Gets all secrets from AWS Secrets Manager
- **Helm Installation**: Installs Helm on K3s master node
- **Chart Deployment**: Deploys FitSync Helm chart with proper values override
- **Rolling Restart**: Ensures pods pick up new secrets
- **Verification**: Comprehensive deployment status checks
- **Configurable**: Chart version, namespace, and environment-specific values

#### cilium-install.yml
- Installs Cilium CNI (replaces default Flannel)
- Disables K3s built-in network policy controller
- Verifies installation with `cilium status`
- **Important**: Uses `sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml` for all kubectl/cilium commands

#### istio-install.yml
- Downloads and installs Istio
- Creates `istio-system` namespace
- Deploys ingress gateway with NodePort services
- Configures for K3s environment

#### cert-manager-install.yml
- Installs cert-manager with Helm
- **Known Issue**: Webhook bootstrap fails on K3s v1.33.6
- **Workaround Applied**: Sets webhook `failurePolicy: Ignore`
- Creates ClusterIssuer for Let's Encrypt (production)

#### wildcard-cert.yml
- Creates wildcard TLS certificate via Let's Encrypt
- Uses Cloudflare DNS-01 challenge
- Certificate names:
  - Production: `production-wildcard-cert` (for `*.fitsync.online`)
  - Development: `dev-wildcard-cert` (for `*.dev.fitsync.online`)
  - Staging: `stage-wildcard-cert` (for `*.stage.fitsync.online`)
- Stores certificate in `istio-system` namespace

#### istio-gateway-https.yml
- Creates Istio Gateway resource with HTTPS
- **Gateway naming**: Always uses `{environment}-gateway` (e.g., `development-gateway`)
- **Certificate naming**: Uses `{subdomain_prefix}-wildcard-cert` (e.g., `dev-wildcard-cert`)
- Configures HTTP → HTTPS redirect
- Uses wildcard hosts (`*`) to accept any Host header from Cloudflare/ALB

#### istio-sample-app.yml
- Deploys Bookinfo sample application
- Creates VirtualService with gateway reference: `istio-system/{environment}-gateway`
- Configures mTLS STRICT mode
- Routes traffic to productpage service

### Main Deployment Workflow (fitsync-cd)

#### k3s-deploy.yml
Orchestrates complete cluster deployment with configurable options:

**Inputs:**
- `environment`: Target environment (development/staging/production)
- `install_k3s_masters`: Install K3s masters with ECR integration
- `install_k3s_workers`: Install K3s workers with ECR integration
- `install_cilium`: Install Cilium CNI
- `install_istio`: Install Istio service mesh
- `install_cert_manager`: Install cert-manager
- `create_wildcard_cert`: Create TLS certificate
- `deploy_istio_gateway`: Deploy Istio Gateway
- `setup_database`: Setup PostgreSQL + Redis with TLS
- `deploy_sample_app`: Deploy Bookinfo sample application
- `deploy_fitsync_app`: Deploy FitSync Helm chart (NEW)

**Enhanced Job Dependencies:**
```
get-infrastructure-info (always runs)
    ↓
install-ecr-credential-provider
    ↓
install-k3s-masters → install-k3s-workers
    ↓
install-cilium
    ↓
install-istio
    ↓
install-cert-manager → create-wildcard-cert
    ↓
deploy-istio-gateway
    ↓
setup-database
    ↓
deploy-fitsync-app OR deploy-sample-app
```
```
get-infrastructure-info (always runs)
    ↓
install-k3s-masters → install-k3s-workers
    ↓
install-cilium
    ↓
install-istio
    ↓
install-cert-manager → create-wildcard-cert
    ↓
deploy-istio-gateway
    ↓
deploy-sample-app
```

**Key Features:**
- Uses `always()` condition for independent job re-runs
- Passes `inputs.environment` to all templates for correct resource naming
- Retrieves infrastructure info from AWS (master/worker instance IDs)

### Resource Naming Convention

**CRITICAL**: Kubernetes resources use `environment`, domain resources use `subdomain_prefix`

| Resource Type | Naming Pattern | Example (Dev) | Example (Prod) |
|---------------|----------------|---------------|----------------|
| Gateway | `{environment}-gateway` | `development-gateway` | `production-gateway` |
| VirtualService | References gateway | `istio-system/development-gateway` | `istio-system/production-gateway` |
| Certificate | `{subdomain_prefix}-wildcard-cert` | `dev-wildcard-cert` | `production-wildcard-cert` |
| DNS Records | `{subdomain_prefix}.{domain}` | `*.dev.fitsync.online` | `*.fitsync.online` |

**Why This Matters:**
- Gateway names must be consistent across deployments
- VirtualService must reference correct gateway name
- Mismatch causes 404 errors (traffic not routed)

## Known Issues and Solutions

### 1. cert-manager Webhook Bootstrap Failure (K3s v1.33.6)

**Symptom:**
```
Failed to generate serving certificate
CA secret not found: secret "cert-manager-webhook-ca" not found
```

**Root Cause:**
- K3s v1.33.6 has service account token caching bug
- Affects cert-manager webhook bootstrap process
- Not a cert-manager version issue (tested v1.16.2, v1.19.1, v1.20.0-alpha.0)

**Solution Applied:**
Webhook `failurePolicy` set to `Ignore` in cert-manager-install.yml:
```bash
kubectl patch validatingwebhookconfiguration cert-manager-webhook \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'

kubectl patch mutatingwebhookconfiguration cert-manager-webhook \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'
```

**Impact:**
- Webhook validation disabled but not critical
- Main cert-manager controller handles certificate operations
- Certificates are created and renewed successfully

### 2. Istio Gateway 404 Errors

**Symptom:**
- HTTPS requests to domain return 404
- ALB health checks pass
- Application pods running

**Root Causes:**

#### A. Multiple Gateways with Different Names
**Problem**: Old gateway (`dev-gateway`) and new gateway (`development-gateway`) both exist
**Detection**:
```bash
kubectl get gateway.networking.istio.io -n istio-system
# Shows: dev-gateway, development-gateway
```
**Solution**:
```bash
# Delete old gateway
kubectl delete gateway.networking.istio.io dev-gateway -n istio-system

# Verify ingress gateway picks up new config
kubectl exec -n istio-system <ingress-pod> -- \
  pilot-agent request GET config_dump | grep route_config_name
```

#### B. Gateway Name Mismatch in VirtualService
**Problem**: VirtualService references wrong gateway name
**Detection**:
```bash
kubectl get virtualservice -A -o yaml | grep -A 2 gateways
```
**Solution**: Ensure VirtualService uses correct format:
```yaml
spec:
  gateways:
  - istio-system/development-gateway  # Must match Gateway metadata.name
```

#### C. Host Header Mismatch
**Problem**: Cloudflare sends `Host: dev.fitsync.online`, Gateway expects specific host
**Solution**: Use wildcard hosts in Gateway:
```yaml
spec:
  servers:
  - hosts:
    - "*"  # Accepts any Host header
```

### 3. Cilium Status Check Failures

**Symptom:**
```
Error: Unable to connect to Cilium daemon
```

**Root Cause:**
- Missing KUBECONFIG environment variable in cilium commands

**Solution Applied:**
All cilium commands now use:
```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml cilium status
```

### 4. K3s Worker Join Failures

**Symptom:**
- Workers cannot join cluster
- Connection timeout to K3s API

**Causes & Solutions:**

#### A. Masters Not Ready
```bash
# Check master status
ssh -F ssh-config master1 "sudo kubectl get nodes"

# Wait for masters to be Ready before joining workers
```

#### B. NLB Health Check Failing
```bash
# Check NLB target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Verify K3s API is listening
ssh -F ssh-config master1 "sudo netstat -tlnp | grep 6443"
```

#### C. Security Group Issues
```bash
# Verify security group allows port 6443
aws ec2 describe-security-groups --group-ids <sg-id>
```

### 5. ALB to Istio Gateway Connection Issues

**Symptom:**
- ALB health checks fail
- 502 Bad Gateway errors

**Causes & Solutions:**

#### A. Istio Gateway Not Listening on NodePort
```bash
# Check ingress gateway service
kubectl get svc -n istio-system istio-ingressgateway

# Verify NodePort is exposed (30443 for HTTPS)
```

#### B. Security Group Blocking ALB → Worker Traffic
```bash
# Check security group allows traffic from ALB security group
# Hub VPC CIDR should be allowed in spoke security group
```

#### C. Certificate Not Loaded
```bash
# Check certificate secret exists
kubectl get secret -n istio-system | grep cert

# Verify Gateway references correct certificate
kubectl get gateway.networking.istio.io -n istio-system -o yaml
```

#### 6. ECR Credential Provider Issues

**Symptom**: K3s fails to start with credential provider errors

**Error**: `Object 'Kind' is missing in credential provider config`

**Diagnosis**:
```bash
# Check credential provider config
ssh -F ssh-config master1 "sudo cat /etc/kubernetes/ecr-credential-provider.json"

# Check K3s logs
ssh -F ssh-config master1 "sudo journalctl -u k3s --no-pager -n 50"
```

**Solutions**:
- Ensure config has `"kind": "CredentialProviderConfig"` field
- Verify `apiVersion: "kubelet.config.k8s.io/v1"` at top level
- Check provider `apiVersion: "credentialprovider.kubelet.k8s.io/v1"`

#### 7. Helm Deployment Failures

**Symptom**: FitSync Helm chart deployment fails

**Diagnosis**:
```bash
# Check Helm status
ssh -F ssh-config master1 "helm status fitsync -n fitsync"

# Check pod status
ssh -F ssh-config master1 "kubectl get pods -n fitsync"

# Check secret retrieval
aws secretsmanager get-secret-value --secret-id "fitsync/development/jwt-secret"
```

**Solutions**:
- Verify all secrets exist in AWS Secrets Manager
- Check IAM permissions for secret access
- Ensure database setup completed successfully
- Verify Helm chart syntax and values

#### 8. Secret Management Issues

**Symptom**: Pods fail to start due to missing secrets

**Diagnosis**:
```bash
# List secrets in environment
aws secretsmanager list-secrets --filters Key=tag-key,Values=Environment

# Check specific secret
aws secretsmanager describe-secret --secret-id "fitsync/development/userdb-db-url"

# Check pod logs
ssh -F ssh-config master1 "kubectl logs -n fitsync deployment/user-service"
```

**Solutions**:
- Run database setup workflow first
- Verify Terraform applied JWT secrets
- Check secret naming convention matches environment
- Ensure rolling restart completed after secret updates

## Troubleshooting Commands

### Infrastructure Verification

```bash
# Check all VPCs
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=fitsync"

# Check Transit Gateway attachments
aws ec2 describe-transit-gateway-attachments

# Check ALB status
aws elbv2 describe-load-balancers --names fitsync-*-alb

# Check NLB target health
aws elbv2 describe-target-health --target-group-arn <arn>

# Check ACM certificate status
aws acm describe-certificate --certificate-arn <arn>
```

### ECR and Secret Verification

```bash
# Check ECR credential provider installation
ssh -F ssh-config master1 "ls -la /usr/local/bin/ecr-credential-provider"
ssh -F ssh-config master1 "sudo cat /etc/kubernetes/ecr-credential-provider.json"

# Test ECR access
ssh -F ssh-config master1 "aws ecr get-login-token --region us-east-2"

# List secrets for environment
aws secretsmanager list-secrets --filters Key=name,Values=fitsync/development

# Get specific secret value
aws secretsmanager get-secret-value --secret-id "fitsync/development/jwt-secret" --query SecretString --output text
```

### Cluster and Application Verification

```bash
# SSH to master
ssh -F ssh-config master1

# Check K3s status
sudo systemctl status k3s

# Check all nodes
sudo kubectl get nodes -o wide

# Check ECR credential provider in kubelet
sudo ps aux | grep kubelet | grep credential-provider

# Check Helm deployments
helm list -A

# Check FitSync application
kubectl get pods -n fitsync
kubectl get services -n fitsync
kubectl get secrets -n fitsync
```

### Cluster Verification

```bash
# SSH to master
ssh -F ssh-config master2

# Check K3s status
sudo systemctl status k3s

# Check all nodes
sudo kubectl get nodes -o wide

# Check all pods
sudo kubectl get pods -A

# Check Cilium status
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml cilium status

# Check Istio installation
sudo kubectl get pods -n istio-system
```

### Istio Gateway Debugging

```bash
# Check Gateway resources
sudo kubectl get gateway.networking.istio.io -A

# Check VirtualService resources
sudo kubectl get virtualservice -A

# Check ingress gateway configuration
sudo kubectl exec -n istio-system <ingress-pod> -- \
  pilot-agent request GET config_dump | grep -A 20 "route_config"

# Check ingress gateway logs
sudo kubectl logs -n istio-system <ingress-pod> --tail=100

# Test from within cluster
curl -k https://localhost:8443/productpage -H 'Host: dev.fitsync.online' -I
```

### Certificate Debugging

```bash
# Check cert-manager pods
sudo kubectl get pods -n cert-manager

# Check cert-manager logs
sudo kubectl logs -n cert-manager deploy/cert-manager

# Check ClusterIssuer
sudo kubectl get clusterissuer -o yaml

# Check Certificate resources
sudo kubectl get certificate -A

# Check Certificate status
sudo kubectl describe certificate -n istio-system

# Check certificate secret
sudo kubectl get secret -n istio-system <cert-name> -o yaml
```

### Application Debugging

```bash
# Check application pods
sudo kubectl get pods -n default

# Check service endpoints
sudo kubectl get endpoints -n default

# Test service directly
sudo kubectl run debug --image=curlimages/curl --restart=Never --rm -i -- \
  curl -s http://productpage.default.svc.cluster.local:9080/productpage

# Check pod logs
sudo kubectl logs -n default <pod-name>
```

## Traffic Flow Verification

### End-to-End Request Path

```
1. Browser → https://dev.fitsync.online
2. Cloudflare (Proxy + TLS termination)
3. ALB in Hub VPC (HTTPS:443 → NodePort:30443)
4. Transit Gateway (Hub → Spoke routing)
5. Istio Ingress Gateway (NodePort:30443)
6. Istio Gateway Resource (development-gateway)
7. VirtualService (bookinfo)
8. Kubernetes Service (productpage:9080)
9. Application Pod
```

### Verification Steps

```bash
# 1. Check Cloudflare DNS
dig dev.fitsync.online
# Should return Cloudflare proxy IPs

# 2. Check ALB DNS resolution
dig <alb-dns-name>
# Should return ALB IPs in hub VPC

# 3. Check ALB target health
aws elbv2 describe-target-health --target-group-arn <arn>
# All targets should be "healthy"

# 4. Check Istio Gateway exists
kubectl get gateway.networking.istio.io development-gateway -n istio-system

# 5. Check VirtualService routing
kubectl get virtualservice bookinfo -o yaml

# 6. Check service endpoints
kubectl get endpoints productpage
# Should show pod IPs

# 7. Test end-to-end
curl -I https://dev.fitsync.online/productpage
# Should return 200 OK
```

## Performance Tuning

### K3s Optimization

```bash
# Increase API server resources (on masters)
sudo vim /etc/systemd/system/k3s.service
# Add: --kube-apiserver-arg=max-requests-inflight=400

# Restart K3s
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### Istio Optimization

```bash
# Scale ingress gateway replicas
kubectl scale deployment istio-ingressgateway -n istio-system --replicas=3

# Adjust resource limits
kubectl edit deployment istio-ingressgateway -n istio-system
```

### Cilium Optimization

```bash
# Enable Hubble for observability
cilium hubble enable

# Check network policies
kubectl get networkpolicies -A
```

## Security Hardening

### Network Security

```bash
# Restrict bastion access (in hub conf.auto.tfvars)
admin_cidr = "YOUR_OFFICE_IP/32"

# Enable VPC Flow Logs
aws ec2 create-flow-logs --resource-type VPC --resource-ids <vpc-id>

# Enable CloudTrail
aws cloudtrail create-trail --name fitsync-trail
```

### Kubernetes Security

```bash
# Enable Pod Security Standards
kubectl label namespace default pod-security.kubernetes.io/enforce=restricted

# Create NetworkPolicies
kubectl apply -f network-policy.yaml

# Enable audit logging (on masters)
sudo vim /etc/rancher/k3s/config.yaml
# Add audit policy configuration
```

### Certificate Management

```bash
# Rotate certificates regularly
kubectl delete certificate -n istio-system <cert-name>
# cert-manager will recreate automatically

# Monitor certificate expiry
kubectl get certificate -A -o json | jq '.items[] | {name: .metadata.name, notAfter: .status.notAfter}'
```

## Backup and Disaster Recovery

### K3s Backup

```bash
# Backup K3s data (on master)
ssh -F ssh-config master1
sudo systemctl stop k3s
sudo tar -czf k3s-backup-$(date +%Y%m%d).tar.gz /var/lib/rancher/k3s
sudo systemctl start k3s

# Copy backup locally
scp -F ssh-config master1:~/k3s-backup-*.tar.gz ./backups/
```

### Terraform State Backup

```bash
# Backup state files
cd live/prod/spoke
terraform state pull > terraform-state-backup-$(date +%Y%m%d).json

# Store in S3 (recommended)
aws s3 cp terraform-state-backup-*.json s3://fitsync-terraform-state-backup/
```

### Database Backup

```bash
# Backup database (on db node)
ssh -F ssh-config db1
sudo tar -czf db-backup-$(date +%Y%m%d).tar.gz /mnt/data
```

## Monitoring and Observability

### Recommended Tools

```bash
# Install Prometheus + Grafana
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Install Hubble (Cilium observability)
cilium hubble enable
cilium hubble ui

# Install Kiali (Istio observability)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
```

### Key Metrics to Monitor

- K3s API server latency
- Cilium network policy drops
- Istio ingress gateway request rate
- Certificate expiry dates
- ALB/NLB target health
- EC2 instance CPU/memory usage

## Cost Optimization

### Right-Sizing Instances

```bash
# Monitor instance utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance-id>

# Downsize if underutilized (in conf.auto.tfvars)
master_instance_type = "t3.small"  # From t3.medium
worker_instance_type = "t3.small"
```

### Use Spot Instances (Non-Prod)

```hcl
# In spoke module (for non-prod only)
resource "aws_instance" "worker" {
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.05"
    }
  }
}
```

### Optimize NAT Gateway

```bash
# Use single NAT Gateway for non-prod (in hub conf.auto.tfvars)
max_azs = 1  # Reduces NAT Gateway cost by 50%
```

## Maintenance Schedule

### Weekly
- Check certificate expiry dates
- Review CloudWatch logs for errors
- Verify backup completion

### Monthly
- Update K3s version
- Update Istio version
- Review and optimize costs
- Security patch EC2 instances

### Quarterly
- Review and update Terraform modules
- Audit IAM permissions
- Test disaster recovery procedures
- Review and update documentation

---

**Last Updated:** December 11, 2025  
**Status:** Production Ready with Full Application Deployment ✅  
**Environments:** Production + Non-Production (Dev + Stage)  

**Component Versions:**
- **K3s Version:** v1.33.6+k3s1 (with ECR credential provider integration)
- **Istio Version:** 1.20+
- **Cilium Version:** Latest stable  
- **cert-manager Version:** v1.16.2 (with webhook workaround)
- **Helm Version:** Latest (auto-installed)
- **ECR Credential Provider:** Latest (configurable)

**New Features Added:**
- ✅ **ECR Integration**: Automatic container image pulling from AWS ECR
- ✅ **Secret Management**: AWS Secrets Manager integration for secure configuration
- ✅ **JWT Security**: Auto-generated secure JWT secrets via Terraform
- ✅ **Database Setup**: Enhanced PostgreSQL + Redis with TLS
- ✅ **Helm Deployment**: Complete FitSync application deployment
- ✅ **Rolling Updates**: Automated pod restarts for secret updates
- ✅ **Multi-Database**: Support for microservices database architecture

**Deployment Options:**
- **Sample Application**: Istio Bookinfo for testing
- **FitSync Application**: Complete microservices stack with Helm
- **Database Services**: PostgreSQL + Redis with TLS encryption
- **Secret Injection**: Automatic secret retrieval and injection
