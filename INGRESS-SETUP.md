# Istio Ingress Gateway with Public NLB

## Overview

This setup exposes the Istio ingress gateway via a public AWS Network Load Balancer (NLB) with HTTPS support.

## Architecture

```
Internet → AWS NLB (public) → Worker Nodes → Istio IngressGateway → Bookinfo App
           Port 443 (HTTPS)      Port 80/443
           Port 80 (HTTP)
```

## Setup Steps

### 1. Create ACM Certificate

```bash
# Request a certificate in AWS Certificate Manager
aws acm request-certificate \
  --domain-name "*.yourdomain.com" \
  --validation-method DNS \
  --region us-east-2

# Note the certificate ARN
```

### 2. Validate Certificate

- Go to AWS Console → Certificate Manager
- Add the DNS validation records to your domain
- Wait for certificate status to become "Issued"

### 3. Enable Ingress NLB

Update `live/02-spoke-prod/conf.auto.tfvars`:

```hcl
create_ingress_nlb  = true
ssl_certificate_arn = "arn:aws:acm:us-east-2:ACCOUNT_ID:certificate/CERT_ID"
```

### 4. Apply Terraform

```bash
cd live/02-spoke-prod
terraform apply
```

### 5. Get NLB DNS Name

```bash
terraform output ingress_nlb_dns
# Output: fitsync-prod-spoke-ingress-nlb-xxxxx.elb.us-east-2.amazonaws.com
```

### 6. Configure DNS

Add a CNAME record in your domain:

```
app.yourdomain.com → fitsync-prod-spoke-ingress-nlb-xxxxx.elb.us-east-2.amazonaws.com
```

### 7. Access Application

```bash
# HTTP (redirects to HTTPS if configured)
http://app.yourdomain.com/productpage

# HTTPS
https://app.yourdomain.com/productpage
```

## Without Custom Domain

If you don't have a domain, you can:

1. Use the NLB DNS directly (HTTP only):
   ```bash
   http://fitsync-prod-spoke-ingress-nlb-xxxxx.elb.us-east-2.amazonaws.com/productpage
   ```

2. Set `create_ingress_nlb = true` and `ssl_certificate_arn = ""` to skip HTTPS

## Security Notes

- NLB is in hub public subnets (internet-facing)
- Worker nodes are in spoke private subnets
- Traffic flows through Transit Gateway
- Istio handles mTLS between services internally
