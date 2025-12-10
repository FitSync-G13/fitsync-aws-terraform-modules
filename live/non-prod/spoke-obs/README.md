# Observability Spoke (non-prod)

Purpose: standalone K3s/Kubernetes spoke VPC dedicated to observability workloads (Prometheus/Grafana + OpenSearch), peered to the non-prod hub via TGW. App clusters can remote_write metrics and ship logs over TGW; no inbound traffic to app clusters is required.

## Inputs
- `conf.auto.tfvars`: environment wiring and sizing. Key overrides:
  - `env = "obs-spoke"`
  - `vpc_cidr = "10.13.0.0/16"`
  - `master_count = 1`, `worker_count = 2`, `db_count = 0`
  - `worker_instance_type = "t3.large"` (more headroom for metrics/logs)
  - `subdomain_prefix = "obs"` (results in `obs.fitsync.online`)
- `conf.secret.auto.tfvars`: secrets for GitHub OIDC + Cloudflare DNS.

## Deploy
```bash
terraform init
terraform plan
terraform apply
```

Outputs: K3s API DNS, master/worker IPs, public NLB DNS (for Grafana/OpenSearch ingress once deployed).

## Next: install observability stack
Use the new cluster’s kubeconfig and the Helm values under `fitsync-helm-chart/observability/`:
- Deploy kube-prometheus-stack (Prometheus/Grafana) in the obs cluster.
- Deploy Prometheus Agent in the app cluster with `remoteWrite` to the obs Prometheus/Thanos receive endpoint.
- Deploy OpenSearch + Dashboards in the obs cluster; ship logs from the app cluster with Fluent Bit/Filebeat/Vector over TLS.

Restrict ingress with Cloudflare IPs and per-app auth (Grafana admin/SSO, OpenSearch security plugin). Update DNS in Cloudflare via the provided tokens.

