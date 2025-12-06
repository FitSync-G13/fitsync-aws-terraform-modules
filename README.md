# AWS Hub-Spoke Infrastructure Architecture

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Network Topology](#network-topology)
3. [Component Details](#component-details)
4. [Security Model](#security-model)
5. [Traffic Flow](#traffic-flow)
6. [Deployment Guide](#deployment-guide)
7. [Operations Guide](#operations-guide)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

This infrastructure implements a **Hub-and-Spoke network topology** on AWS, designed for self-managed container orchestration using K3s (lightweight Kubernetes). The architecture follows a strict separation of concerns with three distinct layers:

### Design Principles
- **No Vendor Lock-in**: Avoid managed services (EKS/ECS/RDS)
- **Self-Managed**: Bootstrap K3s and databases on EC2 instances
- **Security First**: Private subnets, VPC endpoints, centralized routing
- **Scalable**: Easy to add new spokes without hub modifications
- **Cost Effective**: Shared infrastructure reduces redundancy

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SHARED SERVICES LAYER                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 ECR Repository                          │   │
│  │           (Docker Image Registry)                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        HUB LAYER                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Transit Gateway │  │   NAT Gateway   │  │  Bastion Host   │ │
│  │   (Routing)     │  │  (Internet)     │  │   (SSH Jump)    │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       SPOKE LAYER                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   K3s Masters   │  │   K3s Workers   │  │   Databases     │ │
│  │  (Control Plane)│  │  (Workloads)    │  │   (Storage)     │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Network Topology

### IP Address Allocation

| Layer | Environment | VPC CIDR | Purpose |
|-------|-------------|----------|---------|
| Shared | Global | N/A | ECR Registry |
| Hub | prod-hub | 10.0.0.0/16 | Core networking |
| Spoke | prod-spoke | 10.1.0.0/16 | Application workloads |
| Spoke | dev-spoke | 10.2.0.0/16 | Development workloads |

### Subnet Design

#### Hub VPC (10.0.0.0/16)
```
Public Subnets:
├── 10.0.1.0/24 (us-west-2a) - Bastion, NAT Gateway
└── 10.0.2.0/24 (us-west-2b) - NAT Gateway (HA)

Private Subnets:
└── 10.0.10.0/24 (us-west-2a) - TGW Attachment
```

#### Spoke VPC (10.1.0.0/16)
```
Private Subnets Only:
├── 10.1.1.0/24 (us-west-2a) - K3s Masters, Workers, DBs
└── 10.1.2.0/24 (us-west-2b) - K3s Masters, Workers, DBs
```

### Routing Architecture

```
Internet ←→ IGW ←→ Public Subnets ←→ NAT Gateway
                        ↓
                   Transit Gateway
                        ↓
              Private Subnets (Hub/Spoke)
```

---

## Component Details

### 1. Shared Services Layer

#### ECR Repository (`modules/shared-ecr`)
**Purpose**: Centralized Docker image storage for all environments

**Components**:
- **ECR Repository**: Stores Docker images with AES256 encryption
- **Lifecycle Policy**: Automatically deletes untagged images > 14 days
- **Repository Policy**: Allows cross-account access via IAM root principal
- **Image Scanning**: Vulnerability scanning on push enabled

**Security Features**:
- Encryption at rest (AES256)
- Vulnerability scanning
- Access control via IAM policies
- Lifecycle management for cost optimization

### 2. Hub Layer (`modules/hub-network`)

#### VPC Infrastructure
**Purpose**: Central networking hub for all spoke connections

**Components**:
- **VPC**: 10.0.0.0/16 with DNS resolution enabled
- **Internet Gateway**: Provides internet access
- **NAT Gateways**: Multi-AZ for high availability internet egress
- **Public Subnets**: Host bastion and NAT gateways
- **Private Subnets**: TGW attachment points

#### Transit Gateway (TGW)
**Purpose**: Central router connecting all VPCs

**Configuration**:
- Auto-accept shared attachments: Enabled
- Default route table association: Enabled
- Default route table propagation: Enabled
- DNS support: Enabled

**Routing Logic**:
```
Default Route Table:
├── 10.0.0.0/16 → Hub VPC Attachment
├── 10.1.0.0/16 → Spoke VPC Attachment
└── 0.0.0.0/0 → Hub VPC (for internet via NAT)
```

#### Bastion Host
**Purpose**: Secure SSH access point for private resources

**Specifications**:
- **Instance Type**: t3.micro
- **AMI**: Ubuntu 24.04 LTS (via SSM parameter)
- **Placement**: Public subnet with public IP
- **Security Group**: SSH (22) from admin CIDR only

### 3. Spoke Layer (`modules/spoke-infra`)

#### VPC Infrastructure
**Purpose**: Isolated environment for application workloads

**Design Constraints**:
- **Private Subnets Only**: No internet gateways
- **No NAT Gateways**: All internet traffic via hub
- **TGW Connectivity**: Routes to hub for internet access

#### VPC Endpoints (PrivateLink)
**Purpose**: Private access to AWS services without internet routing

**Endpoints Created**:
- **ECR API**: `ecr.api` interface endpoint
- **ECR Docker**: `ecr.dkr` interface endpoint  
- **S3 Gateway**: Required for ECR image layer downloads

**Security**: Restricted to spoke VPC CIDR (10.1.0.0/16)

#### Compute Infrastructure

##### K3s Master Nodes
**Purpose**: Kubernetes control plane

**Specifications**:
- **Count**: Configurable (default: 1)
- **Instance Type**: Configurable (default: t3.micro)
- **AMI**: Ubuntu 24.04 LTS
- **Load Balancer**: Internal NLB on port 6443
- **Tags**: Role=k3s-master (for Ansible discovery)

##### K3s Worker Nodes  
**Purpose**: Kubernetes workload execution

**Specifications**:
- **Count**: Configurable (default: 1)
- **Instance Type**: Configurable (default: t3.micro)
- **AMI**: Ubuntu 24.04 LTS
- **Tags**: Role=k3s-worker (for Ansible discovery)

##### Database Nodes
**Purpose**: Self-managed database instances

**Specifications**:
- **Count**: Configurable (default: 1)
- **Instance Type**: Configurable (default: t3.micro)
- **AMI**: Ubuntu 24.04 LTS
- **Storage**: Additional EBS volume (gp3, configurable size)
- **Tags**: Role=db (for Ansible discovery)

#### IAM Configuration
**Purpose**: Secure access to AWS services

**IAM Role Permissions**:
- `AmazonEC2ContainerRegistryReadOnly`: Pull images from ECR
- `AmazonSSMManagedInstanceCore`: Systems Manager access

---

## Security Model

### Network Security

#### Security Groups

##### Hub Bastion Security Group
```
Ingress:
├── SSH (22/tcp) ← Admin CIDR (0.0.0.0/0)

Egress:
└── All Traffic (0/all) → 0.0.0.0/0
```

##### Spoke Cluster Security Group
```
Ingress:
├── SSH (22/tcp) ← Hub VPC CIDR (10.0.0.0/16)
└── All Traffic (0/all) ← Spoke VPC CIDR (10.1.0.0/16)

Egress:
└── All Traffic (0/all) → 0.0.0.0/0
```

##### VPC Endpoints Security Group
```
Ingress:
└── HTTPS (443/tcp) ← Spoke VPC CIDR (10.1.0.0/16)
```

#### Network ACLs
- **Default ACLs**: Allow all traffic (security enforced at SG level)
- **Custom ACLs**: Not implemented (can be added for additional security)

### Access Control

#### SSH Access Pattern
```
Internet → Bastion (Public IP) → Private Instances
         ↓
    SSH Key Authentication
         ↓
    Hub VPC (10.0.0.0/16) → Spoke VPC (10.1.0.0/16)
```

#### ECR Access Pattern
```
Spoke Instances → VPC Endpoint → ECR Service
                ↓
         IAM Role Authentication
                ↓
         ECR Repository Policy Check
```

### Deletion Protection

#### Resource Protection
- **ECR Repository**: `prevent_destroy` lifecycle rule
- **VPCs**: `prevent_destroy` on critical networking
- **Force Delete**: Disabled on ECR when protection enabled

#### Resource Groups
- **Shared ECR**: `shared-ecr-resources`
- **Hub Network**: `prod-hub-hub-network-resources`
- **Spoke Infrastructure**: `prod-spoke-spoke-infra-resources`

---

## Traffic Flow

### 1. Internet to Spoke Applications

```
Internet Request
    ↓
Application Load Balancer (Future: Not in Phase 1)
    ↓
K3s Ingress Controller (Future: Phase 2)
    ↓
K3s Service (ClusterIP)
    ↓
K3s Pod on Worker Node
```

### 2. Spoke to Internet (Egress)

```
Spoke Instance (10.1.x.x)
    ↓
Default Route (0.0.0.0/0)
    ↓
Transit Gateway
    ↓
Hub VPC Private Route Table
    ↓
NAT Gateway (Public Subnet)
    ↓
Internet Gateway
    ↓
Internet
```

### 3. Spoke to ECR (Container Images)

```
Spoke Instance
    ↓
ECR API Call (docker pull)
    ↓
VPC Endpoint (ecr.api)
    ↓
ECR Service
    ↓
S3 VPC Endpoint (image layers)
    ↓
S3 Service
```

### 4. SSH Access to Spoke

```
Admin Workstation
    ↓
SSH to Bastion (Public IP)
    ↓
SSH Jump to Spoke Instance (Private IP)
    ↓
Spoke Instance (via TGW routing)
```

### 5. Inter-Spoke Communication (Future)

```
Spoke A Instance
    ↓
Transit Gateway
    ↓
Spoke B Instance
```

---

## Deployment Guide

### Prerequisites

1. **AWS CLI Configuration**
   ```bash
   aws configure
   # OR
   aws sso login --profile your-profile
   ```

2. **SSH Key Generation**
   ```bash
   ./generate-keys.sh
   # Creates: ssh-keys/aws-key and ssh-keys/aws-key.pub
   ```

3. **Terraform Installation**
   ```bash
   # Terraform >= 1.0 required
   terraform --version
   ```

### Deployment Order

#### Phase 1: Shared Services
```bash
cd live/00-shared-global
terraform init
terraform plan
terraform apply
```

**Resources Created**:
- ECR repository with lifecycle policies
- Repository access policies
- Resource group for ECR resources

#### Phase 2: Hub Infrastructure  
```bash
cd live/01-hub-prod
terraform init
terraform plan
terraform apply
```

**Resources Created**:
- Hub VPC with public/private subnets
- Internet Gateway and NAT Gateways
- Transit Gateway with default routing
- Bastion host with security groups
- SSH key pair from local public key
- Resource group for hub resources

#### Phase 3: Spoke Infrastructure
```bash
cd live/02-spoke-prod
terraform init
terraform plan
terraform apply
```

**Resources Created**:
- Spoke VPC with private subnets only
- VPC endpoints for ECR and S3 access
- TGW attachment and routing configuration
- K3s master/worker/database instances
- Internal NLB for K3s API server
- EBS volumes for database storage
- IAM roles and instance profiles
- Resource group for spoke resources

### Configuration Options

#### AMI Selection
```hcl
# Default: Ubuntu 24.04 LTS
# No configuration needed

# Ubuntu 22.04 LTS
ssm_parameter_name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"

# Amazon Linux 2
ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
```

#### Instance Sizing
```hcl
# Development
instance_type = "t3.micro"
master_count  = 1
worker_count  = 1
db_count      = 1

# Production
instance_type = "t3.medium"
master_count  = 3
worker_count  = 3
db_count      = 2
```

#### Security Configuration
```hcl
# Restrict bastion access
admin_cidr = "203.0.113.0/24"  # Your office IP range

# Enable deletion protection
enable_deletion_protection = true
```

---

## Operations Guide

### SSH Access

#### Connect to Bastion
```bash
ssh -i ssh-keys/aws-key ubuntu@<bastion-public-ip>
```

#### Connect to Spoke Instances
```bash
# Using SSH config (recommended)
ssh -F ssh-config master1
ssh -F ssh-config worker1
ssh -F ssh-config db1

# Manual jump
ssh -i ssh-keys/aws-key -J ubuntu@<bastion-ip> ubuntu@<spoke-private-ip>
```

### K3s Cluster Setup (Phase 2)

#### Install First Master
```bash
ssh -F ssh-config master1
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san=<nlb-dns-name>
```

#### Get Join Token
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

#### Join Additional Masters
```bash
ssh -F ssh-config master2
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://<first-master-ip>:6443 \
  --token <token> \
  --tls-san=<nlb-dns-name>
```

#### Join Workers
```bash
ssh -F ssh-config worker1
curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://<nlb-dns-name>:6443 \
  --token <token>
```

#### Get Kubeconfig
```bash
scp -F ssh-config master1:/etc/rancher/k3s/k3s.yaml ./kubeconfig
sed -i 's/127.0.0.1/<nlb-dns-name>/g' kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

### Monitoring and Maintenance

#### Resource Groups
- **AWS Console** → Resource Groups → View resources by environment
- **Cost Allocation** → Filter by Module and Env tags
- **Compliance** → Check resource tagging and protection

#### Health Checks
```bash
# Check TGW route propagation
aws ec2 describe-transit-gateway-route-tables

# Check VPC endpoint status
aws ec2 describe-vpc-endpoints

# Check instance health
aws ec2 describe-instances --filters "Name=tag:Module,Values=spoke-infra"
```

### Scaling Operations

#### Add New Spoke
1. Copy `live/02-spoke-prod` to `live/03-spoke-dev`
2. Update `conf.auto.tfvars`:
   ```hcl
   env = "dev-spoke"
   vpc_cidr = "10.2.0.0/16"
   private_subnets = ["10.2.1.0/24", "10.2.2.0/24"]
   ```
3. Deploy: `terraform init && terraform apply`

#### Scale Existing Spoke
```hcl
# Update conf.auto.tfvars
master_count = 3
worker_count = 5
db_count = 2

# Apply changes
terraform apply
```

---

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failures

**Symptom**: Cannot SSH to bastion or spoke instances

**Diagnosis**:
```bash
# Check bastion public IP
terraform output bastion_public_ip

# Check security groups
aws ec2 describe-security-groups --group-names "*bastion*"

# Test connectivity
telnet <bastion-ip> 22
```

**Solutions**:
- Verify `admin_cidr` includes your IP
- Check SSH key permissions: `chmod 600 ssh-keys/aws-key`
- Verify bastion has public IP assigned

#### 2. Spoke Internet Access Issues

**Symptom**: Spoke instances cannot reach internet

**Diagnosis**:
```bash
# Check TGW route tables
aws ec2 describe-transit-gateway-route-tables

# Check spoke routing
ssh -F ssh-config master1 "ip route"

# Test DNS resolution
ssh -F ssh-config master1 "nslookup google.com"
```

**Solutions**:
- Verify TGW route propagation is enabled
- Check NAT Gateway status in hub
- Verify spoke route table points to TGW

#### 3. ECR Access Issues

**Symptom**: Cannot pull Docker images from ECR

**Diagnosis**:
```bash
# Check VPC endpoints
aws ec2 describe-vpc-endpoints

# Test ECR connectivity
ssh -F ssh-config master1 "aws ecr get-login-token"

# Check IAM permissions
aws iam get-role-policy --role-name <spoke-role>
```

**Solutions**:
- Verify VPC endpoints are available
- Check IAM role has ECR permissions
- Ensure security groups allow HTTPS to endpoints

#### 4. K3s Cluster Issues

**Symptom**: K3s nodes cannot join cluster

**Diagnosis**:
```bash
# Check NLB health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Check K3s logs
ssh -F ssh-config master1 "sudo journalctl -u k3s"

# Test API server connectivity
ssh -F ssh-config worker1 "curl -k https://<nlb-dns>:6443/healthz"
```

**Solutions**:
- Verify NLB target group health
- Check security groups allow port 6443
- Ensure TLS SAN includes NLB DNS name

### Performance Optimization

#### Network Optimization
- **Enhanced Networking**: Enable on larger instance types
- **Placement Groups**: Use cluster placement for low latency
- **Instance Types**: Use network-optimized instances for high throughput

#### Cost Optimization
- **Spot Instances**: Use for non-critical workloads
- **Reserved Instances**: For predictable workloads
- **EBS GP3**: More cost-effective than GP2
- **Lifecycle Policies**: Automatic cleanup of old resources

### Security Hardening

#### Additional Security Measures
1. **VPC Flow Logs**: Enable for network monitoring
2. **CloudTrail**: Enable for API call auditing
3. **Config Rules**: Automated compliance checking
4. **Systems Manager**: Patch management and compliance
5. **Secrets Manager**: Store sensitive configuration
6. **Parameter Store**: Encrypted configuration storage

#### Network Segmentation
```hcl
# Custom NACLs for additional security
resource "aws_network_acl" "spoke_private" {
  vpc_id = aws_vpc.spoke.id
  
  # Allow only required traffic
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = "10.0.0.0/16"  # Hub only
    action     = "allow"
  }
}
```

---

## Architecture Benefits

### Scalability
- **Horizontal**: Easy to add new spokes
- **Vertical**: Scale instances within spokes
- **Geographic**: Deploy spokes in different regions

### Security
- **Network Isolation**: Private subnets with controlled routing
- **Centralized Access**: Single bastion for SSH access
- **Service Isolation**: VPC endpoints for AWS service access
- **Least Privilege**: Minimal IAM permissions

### Cost Efficiency
- **Shared Infrastructure**: Hub services shared across spokes
- **Resource Optimization**: Right-sized instances
- **Automated Cleanup**: Lifecycle policies for cost control

### Operational Excellence
- **Infrastructure as Code**: Complete Terraform automation
- **Standardized Tagging**: Consistent resource organization
- **Resource Groups**: Easy resource management
- **Deletion Protection**: Prevents accidental resource loss

This architecture provides a robust, secure, and scalable foundation for self-managed Kubernetes workloads on AWS while maintaining cost efficiency and operational simplicity.
