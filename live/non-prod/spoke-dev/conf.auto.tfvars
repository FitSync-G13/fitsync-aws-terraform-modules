project_name                          = "fitsync"
aws_region                            = "us-east-2"
env                                   = "dev-spoke"
hub_env                               = "non-prod-hub"
vpc_cidr                              = "10.11.0.0/16"
master_count                          = 1
worker_count                          = 1
db_count                              = 1
db_vol_size                           = 50
master_instance_type                  = "t3.medium"
worker_instance_type                  = "t3.medium"
db_instance_type                      = "t3.medium"
opensearch_master_count               = 1
opensearch_worker_count               = 1
opensearch_master_instance_type       = "t3.medium"
opensearch_worker_instance_type       = "t3.medium"
opensearch_vol_size                   = 50
public_key_path                       = "../../../ssh-keys/aws-key.pub"
github_repo                           = "FitSync-G13/fitsync-cd"
deployment_environment                = "development"
domain_name                           = "fitsync.online"
subdomain_prefix                      = "dev-api"
db_subdomain_prefix                   = "db2"
opensearch_subdomain_prefix           = "opensearch2"
opensearch_dashboard_subdomain_prefix = "opensearch2-dashboard"
enable_deletion_protection            = false

# CI Repositories that need ECR access
ci_repositories = [
  "FitSync-G13/fitsync-user-service",
  "FitSync-G13/fitsync-training-service",
  "FitSync-G13/fitsync-schedule-service",
  "FitSync-G13/fitsync-progress-service",
  "FitSync-G13/fitsync-api-gateway",
  "FitSync-G13/fitsync-notification-service"
]
