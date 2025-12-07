# FitSync Traffic Flow and Ingress Architecture

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Load Balancer Chaining Pattern](#load-balancer-chaining-pattern)
3. [Complete Traffic Flow](#complete-traffic-flow)
4. [How to Expose Applications](#how-to-expose-applications)
5. [Security Model](#security-model)
6. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Hub-Spoke Network Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HUB VPC (10.0.0.0/16)                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Public Subnets (IGW attached)               │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Public NLB (Internet-facing)                      │  │   │
│  │  │  - fitsync-prod-spoke-public-nlb                   │  │   │
│  │  │  - Ports: 80, 443                                  │  │   │
│  │  │  - Targets: Spoke worker/master IPs via TGW       │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────┐  ┌────────────────┐                 │   │
│  │  │  NAT Gateway   │  │  Bastion Host  │                 │   │
│  │  └────────────────┘  └────────────────┘                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                             │                                    │
│  ┌──────────────────────────┼────────────────────────────────┐  │
│  │         Private Subnets  │                                │  │
│  │  ┌───────────────────────▼──────────────────────────────┐│  │
│  │  │         Transit Gateway Attachment                   ││  │
│  │  └──────────────────────────────────────────────────────┘│  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │ Transit Gateway
                             │ (Cross-VPC Routing)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SPOKE VPC (10.1.0.0/16)                     │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         Private Subnets ONLY (No IGW, No NAT)            │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  K3s Master Nodes (10.1.1.49)                      │  │   │
│  │  │  - Control plane                                   │  │   │
│  │  │  - NodePort 30080/30443 exposed                    │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  K3s Worker Nodes (10.1.1.104)                     │  │   │
│  │  │  - Application workloads                           │  │   │
│  │  │  - NodePort 30080/30443 exposed                    │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Istio Ingress Gateway (NodePort Service)         │  │   │
│  │  │  - Port 80 → NodePort 30080 → targetPort 8080     │  │   │
│  │  │  - Port 443 → NodePort 30443 → targetPort 8443    │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Application Pods (with Istio sidecars)           │  │   │
│  │  │  - mTLS STRICT mode enforced                      │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Load Balancer Chaining Pattern

### Why This Architecture?

**Problem**: Spoke VPC is fully private (no Internet Gateway) but needs to serve internet traffic.

**Solution**: Load Balancer Chaining via Transit Gateway

```
Internet → Hub Public NLB → Transit Gateway → Spoke NodePort → Istio → App
```

### Key Components

#### 1. Hub Public NLB
- **Type**: Network Load Balancer (Layer 4)
- **Scheme**: Internet-facing
- **Location**: Hub VPC public subnets
- **Target Type**: IP addresses (cross-VPC)
- **Targets**: Spoke worker and master node IPs
- **Ports**: 80 (HTTP), 443 (HTTPS)

#### 2. Transit Gateway
- **Purpose**: Cross-VPC routing
- **Route**: Hub public subnet → Spoke private subnet
- **Configuration**: 
  - Hub public route table: `10.1.0.0/16 → TGW`
  - Spoke default route: `0.0.0.0/0 → TGW`

#### 3. Spoke NodePort
- **Service**: istio-ingressgateway
- **Type**: NodePort
- **Ports**:
  - `80 → 30080 → 8080` (HTTP)
  - `443 → 30443 → 8443` (HTTPS)
- **Exposed On**: All master and worker nodes

#### 4. Istio Ingress Gateway
- **Type**: Envoy proxy
- **Listens On**: Ports 8080 (HTTP), 8443 (HTTPS)
- **Routes**: Based on Gateway and VirtualService resources

---

## Complete Traffic Flow

### Inbound Request (Internet → Application)

```
1. User Browser
   ↓ DNS: fitsync-prod-spoke-public-nlb-xxx.elb.us-east-2.amazonaws.com
   ↓ HTTP GET /productpage

2. Hub Public NLB (10.0.1.117, 10.0.2.19)
   ↓ Target: 10.1.1.104:30080 (worker) or 10.1.1.49:30080 (master)
   ↓ Protocol: TCP
   ↓ Health Check: TCP on port 30080

3. Transit Gateway
   ↓ Route: 10.1.0.0/16 → Spoke VPC Attachment
   ↓ Preserves source IP: NLB private IP (10.0.x.x)

4. Spoke Worker/Master Node (10.1.1.104 or 10.1.1.49)
   ↓ Security Group: Allow 30080/30443 from 10.0.0.0/16
   ↓ iptables: KUBE-NODEPORTS → NodePort 30080

5. Istio Ingress Gateway Pod
   ↓ Service: istio-ingressgateway (NodePort)
   ↓ Container Port: 8080
   ↓ Envoy Proxy: Listens on 0.0.0.0:8080

6. Gateway Resource (bookinfo-gateway)
   ↓ Selector: istio=ingressgateway
   ↓ Match: Port 80, Protocol HTTP, Hosts: *

7. VirtualService (bookinfo)
   ↓ Gateway: bookinfo-gateway
   ↓ Match: URI /productpage
   ↓ Route: productpage service

8. Productpage Service (ClusterIP 10.43.207.81:9080)
   ↓ Selector: app=productpage
   ↓ Endpoints: Productpage pod IPs

9. Productpage Pod (10.42.0.206:9080)
   ↓ Istio Sidecar: Intercepts inbound traffic
   ↓ mTLS: Verifies client certificate (from ingress gateway)
   ↓ Application Container: Processes request

10. Response (Application → Internet)
    ↓ Same path in reverse
    ↓ mTLS encrypted between pods
    ↓ Plain HTTP/HTTPS to internet
```

### Service-to-Service Communication (Pod → Pod)

```
1. Productpage Pod calls Details Service
   ↓ HTTP GET http://details:9080/details/0

2. Istio Sidecar (Envoy Outbound)
   ↓ Intercepts outbound request
   ↓ Establishes mTLS connection
   ↓ Presents client certificate

3. Details Service (ClusterIP 10.43.x.x:9080)
   ↓ Kubernetes DNS resolution
   ↓ Load balances to pod endpoint

4. Details Pod Istio Sidecar (Envoy Inbound)
   ↓ Receives mTLS connection
   ↓ Verifies client certificate (STRICT mode)
   ↓ Decrypts traffic

5. Details Application Container
   ↓ Receives plain HTTP on localhost:9080
   ↓ Processes request
   ↓ Returns response

6. Response encrypted via mTLS back to Productpage
```

---

## How to Expose Applications

### Method 1: Using Istio Gateway (Recommended)

#### Step 1: Deploy Your Application
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: <your-ecr-repo>/myapp:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: default
spec:
  selector:
    app: myapp
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
```

#### Step 2: Create Gateway Resource
```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: myapp-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80        # Service port (NOT 8080)
      name: http
      protocol: HTTP
    hosts:
    - "*"               # Or specific domain
```

#### Step 3: Create VirtualService
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: myapp
  namespace: default
spec:
  hosts:
  - "*"
  gateways:
  - myapp-gateway
  http:
  - match:
    - uri:
        prefix: /myapp
    route:
    - destination:
        host: myapp
        port:
          number: 8080
```

#### Step 4: Access Your Application
```bash
# Via public NLB
curl http://<public-nlb-dns>/myapp

# Example
curl http://fitsync-prod-spoke-public-nlb-xxx.elb.us-east-2.amazonaws.com/myapp
```

### Method 2: Using Custom Domain (Production)

#### Step 1: Create Route53 Record
```hcl
resource "aws_route53_record" "app" {
  zone_id = var.hosted_zone_id
  name    = "app.example.com"
  type    = "A"
  
  alias {
    name                   = aws_lb.public_ingress.dns_name
    zone_id                = aws_lb.public_ingress.zone_id
    evaluate_target_health = true
  }
}
```

#### Step 2: Update Gateway for Specific Host
```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: myapp-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "app.example.com"
```

#### Step 3: Access via Domain
```bash
curl http://app.example.com/myapp
```

### Method 3: HTTPS with TLS (Secure)

#### Step 1: Create TLS Secret
```bash
kubectl create secret tls myapp-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n istio-system
```

#### Step 2: Configure Gateway with TLS
```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: myapp-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: myapp-tls
    hosts:
    - "app.example.com"
```

---

## Security Model

### Network Security

#### 1. Hub VPC Security Groups
```
Bastion Security Group:
├── Ingress: SSH (22) from 0.0.0.0/0
└── Egress: All traffic

Public NLB:
└── No security groups (NLB doesn't use SGs)
```

#### 2. Spoke VPC Security Groups
```
Cluster Security Group (Masters & Workers):
├── Ingress:
│   ├── SSH (22) from Hub VPC (10.0.0.0/16)
│   ├── K3s API (6443) from Hub VPC (10.0.0.0/16)
│   ├── NodePort HTTP (30080) from Hub VPC (10.0.0.0/16)  ← NLB traffic
│   ├── NodePort HTTPS (30443) from Hub VPC (10.0.0.0/16) ← NLB traffic
│   └── All traffic from Spoke VPC (10.1.0.0/16)
└── Egress: All traffic
```

#### 3. Routing Security
```
Hub Public Route Table:
├── 10.0.0.0/16 → local
├── 10.1.0.0/16 → Transit Gateway  ← Critical for NLB to reach spoke
└── 0.0.0.0/0 → Internet Gateway

Spoke Private Route Table:
├── 10.1.0.0/16 → local
└── 0.0.0.0/0 → Transit Gateway  ← All internet traffic via hub
```

### Application Security (Istio mTLS)

#### mTLS Configuration
```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT  # All pod-to-pod traffic requires mTLS
```

#### How mTLS Works
1. **Certificate Issuance**: Istiod issues certificates to each pod's sidecar
2. **Automatic Rotation**: Certificates auto-rotate before expiry
3. **Mutual Authentication**: Both client and server verify certificates
4. **Encryption**: All service mesh traffic is encrypted

#### Verify mTLS Enforcement
```bash
# Test 1: Direct connection without sidecar (should FAIL)
curl http://<pod-ip>:9080/endpoint
# Result: Connection reset by peer

# Test 2: Connection with sidecar (should SUCCEED)
kubectl exec <pod-with-sidecar> -c app -- curl http://service:9080/endpoint
# Result: Success
```

---

## Troubleshooting

### Issue 1: NLB Targets Unhealthy

**Symptoms**: NLB shows targets as unhealthy, curl times out

**Diagnosis**:
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn> \
  --region us-east-2

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <spoke-cluster-sg> \
  --region us-east-2
```

**Common Causes**:
1. ❌ Security group missing NodePort rules from hub VPC
2. ❌ Hub public route table missing spoke CIDR → TGW route
3. ❌ NodePort service not listening on worker/master nodes

**Solution**:
```bash
# Verify security group allows 30080/30443 from 10.0.0.0/16
# Verify hub route table has: 10.1.0.0/16 → tgw-xxx
# Verify NodePort: kubectl get svc istio-ingressgateway -n istio-system
```

### Issue 2: Application Returns 503 Service Unavailable

**Symptoms**: NLB is healthy but app returns 503

**Diagnosis**:
```bash
# Check Gateway configuration
kubectl get gateway -o yaml

# Check VirtualService
kubectl get virtualservice -o yaml

# Check pod status
kubectl get pods -o wide
```

**Common Causes**:
1. ❌ Gateway port is 8080 instead of 80
2. ❌ Pods don't have Istio sidecars (not 2/2 Running)
3. ❌ mTLS certificates not properly configured

**Solution**:
```bash
# Fix Gateway port to 80
# Restart pods to inject sidecars: kubectl delete pods -l app=myapp
# Verify sidecars: kubectl get pods (should show 2/2)
```

### Issue 3: Service-to-Service Communication Fails

**Symptoms**: Pod A cannot call Pod B, connection timeout

**Diagnosis**:
```bash
# Check mTLS policy
kubectl get peerauthentication

# Check if pods have sidecars
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Test connectivity
kubectl exec <pod-a> -c app -- curl http://service-b:port
```

**Common Causes**:
1. ❌ Pods created before namespace labeled for injection
2. ❌ mTLS STRICT mode but pods lack sidecars
3. ❌ Service selector doesn't match pod labels

**Solution**:
```bash
# Restart pods to inject sidecars
kubectl delete pods --all

# Verify namespace label
kubectl get namespace default --show-labels

# Add label if missing
kubectl label namespace default istio-injection=enabled
```

### Issue 4: Cannot Access from Internet

**Symptoms**: curl to public NLB DNS times out

**Diagnosis**:
```bash
# Get NLB DNS
terraform output public_nlb_dns

# Test from local machine
curl -v http://<nlb-dns>/productpage

# Check NLB status
aws elbv2 describe-load-balancers \
  --names fitsync-prod-spoke-public-nlb \
  --region us-east-2
```

**Common Causes**:
1. ❌ NLB is internal instead of internet-facing
2. ❌ NLB in private subnets instead of public
3. ❌ Security group blocking traffic (NLBs don't use SGs, check targets)

**Solution**:
```bash
# Verify NLB scheme: "Scheme": "internet-facing"
# Verify NLB subnets are public (have IGW route)
# Verify targets are healthy
```

---

## Best Practices

### 1. Always Use Istio Gateway for Ingress
- Don't expose services as LoadBalancer or NodePort directly
- Use Gateway + VirtualService for routing
- Leverage Istio's traffic management features

### 2. Enable mTLS STRICT Mode
- Enforces encryption for all service-to-service traffic
- Provides mutual authentication
- Prevents unauthorized access

### 3. Use Namespace Isolation
- Deploy apps in separate namespaces
- Apply PeerAuthentication per namespace
- Use NetworkPolicies for additional isolation

### 4. Monitor NLB Health
- Set up CloudWatch alarms for unhealthy targets
- Monitor target response times
- Track connection counts

### 5. Use Custom Domains
- Don't expose NLB DNS directly to users
- Use Route53 with custom domains
- Implement proper TLS certificates

### 6. Implement Rate Limiting
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: myapp
spec:
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: myapp
    retries:
      attempts: 3
      perTryTimeout: 2s
    timeout: 10s
```

---

## Summary

This architecture provides:
- ✅ **Internet access** to fully private spoke VPC
- ✅ **Load balancer chaining** via Transit Gateway
- ✅ **Zero vendor lock-in** with self-managed K3s
- ✅ **Service mesh security** with Istio mTLS
- ✅ **Scalable ingress** supporting multiple applications
- ✅ **Production-ready** with health checks and monitoring

For additional spokes, simply repeat the spoke module deployment - each gets its own public NLB automatically.
