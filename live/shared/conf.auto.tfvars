project_name               = "fitsync"
aws_region                 = "us-east-2"
env                        = "shared"
enable_deletion_protection = false

service_names = [
  "user-service",
  "training-service",
  "schedule-service",
  "progress-service",
  "notification-service",
  "api-gateway",
  "frontend"
]
