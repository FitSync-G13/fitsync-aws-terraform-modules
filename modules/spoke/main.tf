# Data source for ECR repository URLs from shared module
data "aws_ecr_repository" "shared_repositories" {
  for_each = toset(["user-service", "training-service", "schedule-service", "progress-service", "notification-service", "api-gateway", "frontend"])
  name     = "${var.project_name}-${each.value}"
}

# GitHub Actions OIDC Provider - create only for prod-spoke, others use existing
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.env == "prod-spoke" ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-github-oidc"
  })
}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.env != "prod-spoke" ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.env == "prod-spoke" ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.github_actions[0].arn
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.env}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-github-actions-role"
  })
}

# IAM Roles for CI Repositories (ECR Push Access)
resource "aws_iam_role" "ci_github_actions" {
  for_each = toset(var.ci_repositories)
  name     = "${var.project_name}-${var.env}-ci-${replace(split("/", each.value)[1], "-", "")}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${each.value}:*"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-ci-${replace(split("/", each.value)[1], "-", "")}-role"
    Type = "CI"
  })
}

# ECR Push Policy for CI Repositories
resource "aws_iam_role_policy" "ci_ecr_push" {
  for_each = toset(var.ci_repositories)
  name     = "${var.project_name}-${var.env}-ci-ecr-push-policy"
  role     = aws_iam_role.ci_github_actions[each.value].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for EC2 and SSM access
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "${var.project_name}-${var.env}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ssm:SendCommand",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elbv2:DescribeLoadBalancers",
          "elbv2:DescribeTargetGroups",
          "elbv2:DescribeTargetHealth",
          "elasticloadbalancing:DescribeLoadBalancers"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:TagResource"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.deployment_environment}/*"
        ]
      }
    ]
  })
}

# Attach managed policy for SSM
resource "aws_iam_role_policy_attachment" "github_actions_ssm" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_route" "hub_to_spoke" {
  route_table_id         = data.aws_route_table.hub_public.id
  destination_cidr_block = var.vpc_cidr
  transit_gateway_id     = var.hub_tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_ec2_transit_gateway_route" "spoke_to_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.default.id
}

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.env}-key"
  public_key = file(var.public_key_path)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-key"
  })
}

# VPC with private subnets only
resource "aws_vpc" "spoke" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-vpc"
  })
}

resource "aws_subnet" "private" {
  count             = length(local.auto_private_subnets)
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = local.auto_private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-private-subnet-${count.index + 1}"
  })
}

# Transit Gateway Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = var.hub_tgw_id
  vpc_id             = aws_vpc.spoke.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-tgw-attachment"
  })
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.spoke.id

  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = var.hub_tgw_id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-private-rt"
  })

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-${var.env}-vpc-endpoints-"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-vpc-endpoints-sg"
  })
}

# VPC Endpoints
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.spoke.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.spoke.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.spoke.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-s3-endpoint"
  })
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EBS CSI Driver permissions for OpenSearch storage
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.env}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = local.common_tags
}

# Security Groups
resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-${var.env}-cluster-"
  vpc_id      = aws_vpc.spoke.id

  # SSH from hub bastion
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
  }

  # K3s API access from hub VPC (for bastion kubectl access)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
  }

  # NodePort HTTP from hub VPC (for NLB health checks and traffic)
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
    description = "Istio ingress HTTP NodePort from hub NLB"
  }

  # NodePort HTTPS from hub VPC (for NLB health checks and traffic)
  ingress {
    from_port   = 30443
    to_port     = 30443
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
    description = "Istio ingress HTTPS NodePort from hub NLB"
  }

  # OpenSearch Dashboard NodePort from hub VPC (for ALB health checks and traffic)
  ingress {
    from_port   = 30601
    to_port     = 30601
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
    description = "OpenSearch Dashboard HTTPS NodePort from hub ALB"
  }

  # OpenSearch Service NodePort from hub VPC (for ALB health checks and traffic)
  ingress {
    from_port   = 30920
    to_port     = 30920
    protocol    = "tcp"
    cidr_blocks = [var.hub_vpc_cidr]
    description = "OpenSearch Service HTTPS NodePort from hub ALB"
  }

  # All traffic within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-cluster-sg"
  })
}

# K3s Master Instances
resource "aws_instance" "k3s_masters" {
  count                  = var.master_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.master_instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-k3s-master-${count.index + 1}"
    Role = "k3s-master"
  })
}

# K3s Worker Instances
resource "aws_instance" "k3s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-k3s-worker-${count.index + 1}"
    Role = "k3s-worker"
  })
}

# Database Instances
resource "aws_instance" "databases" {
  count                  = var.db_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.db_instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-db-${count.index + 1}"
    Role = "db"
  })
}

# EBS Volumes for Databases
resource "aws_ebs_volume" "db_volumes" {
  count             = var.db_count
  availability_zone = aws_instance.databases[count.index].availability_zone
  size              = var.db_vol_size
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-db-volume-${count.index + 1}"
  })
}

resource "aws_volume_attachment" "db_attachments" {
  count       = var.db_count
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.db_volumes[count.index].id
  instance_id = aws_instance.databases[count.index].id
}

# OpenSearch Master Instances
resource "aws_instance" "opensearch_masters" {
  count                  = var.opensearch_master_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.opensearch_master_instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-opensearch-master-${count.index + 1}"
    Role = "opensearch-master"
  })
}

# OpenSearch Worker Instances
resource "aws_instance" "opensearch_workers" {
  count                  = var.opensearch_worker_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.opensearch_worker_instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-opensearch-worker-${count.index + 1}"
    Role = "opensearch-worker"
  })
}

# Single EBS Volume for OpenSearch Cluster (managed via CSI)
resource "aws_ebs_volume" "opensearch_storage" {
  count             = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  availability_zone = var.opensearch_master_count > 0 ? aws_instance.opensearch_masters[0].availability_zone : aws_instance.opensearch_workers[0].availability_zone
  size              = var.opensearch_vol_size
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-${var.env}-opensearch-storage"
    ClusterRole = "opensearch-shared-storage"
    CSIManaged  = "true"
  })
}

# Internal Load Balancer for K3s API
resource "aws_lb" "opensearch_internal" {
  count              = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  name               = "${var.project_name}-${var.env}-opensearch-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-opensearch-nlb"
  })
}

resource "aws_lb_target_group" "opensearch" {
  count    = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  name     = "${var.project_name}-${var.env}-opensearch-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.spoke.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-opensearch-k3s-api-tg"
  })
}

resource "aws_lb_listener" "opensearch" {
  count             = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  load_balancer_arn = aws_lb.opensearch_internal[0].arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opensearch[0].arn
  }
}

resource "aws_lb_target_group_attachment" "opensearch_masters" {
  count            = var.opensearch_master_count
  target_group_arn = aws_lb_target_group.opensearch[0].arn
  target_id        = aws_instance.opensearch_masters[count.index].id
  port             = 6443
}

# Separate Internal NLB for OpenSearch API (port 9200)
resource "aws_lb" "opensearch_api_internal" {
  count              = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  name               = "${var.project_name}-${var.env}-os-api-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-os-api-nlb"
  })
}

resource "aws_lb_target_group" "opensearch_api" {
  count    = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  name     = "${var.project_name}-${var.env}-os-api-tg"
  port     = 30920
  protocol = "TCP"
  vpc_id   = aws_vpc.spoke.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-os-api-tg"
  })
}

resource "aws_lb_listener" "opensearch_api" {
  count             = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  load_balancer_arn = aws_lb.opensearch_api_internal[0].arn
  port              = "9200"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opensearch_api[0].arn
  }
}

resource "aws_lb_target_group_attachment" "opensearch_api_masters" {
  count            = var.opensearch_master_count
  target_group_arn = aws_lb_target_group.opensearch_api[0].arn
  target_id        = aws_instance.opensearch_masters[count.index].id
  port             = 30920
}

resource "aws_lb_target_group_attachment" "opensearch_api_workers" {
  count            = var.opensearch_worker_count
  target_group_arn = aws_lb_target_group.opensearch_api[0].arn
  target_id        = aws_instance.opensearch_workers[count.index].id
  port             = 30920
}

# Network Load Balancer for K3s API
resource "aws_lb" "k3s_api" {
  name               = "${var.project_name}-${var.env}-k3s-api-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-k3s-api-nlb"
  })
}

resource "aws_lb_target_group" "k3s_api" {
  name     = "${var.project_name}-${var.env}-k3s-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.spoke.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-k3s-api-tg"
  })
}

resource "aws_lb_listener" "k3s_api" {
  load_balancer_arn = aws_lb.k3s_api.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_api.arn
  }
}

resource "aws_lb_target_group_attachment" "k3s_masters" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.k3s_api.arn
  target_id        = aws_instance.k3s_masters[count.index].id
  port             = 6443
}

# GitHub Environment for this spoke
resource "github_repository_environment" "deployment_env" {
  repository  = split("/", var.github_repo)[1]
  environment = var.deployment_environment
}

# Environment-level AWS role secret
resource "github_actions_environment_secret" "aws_role_arn" {
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

# Hub-level variables (previously created by hub)
resource "github_actions_environment_variable" "aws_region" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "AWS_REGION"
  value         = var.aws_region
}

resource "github_actions_environment_variable" "project_name" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "PROJECT_NAME"
  value         = var.project_name
}

resource "github_actions_environment_variable" "hub_env" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "HUB_ENV"
  value         = var.hub_env
}

# Spoke-specific variables
resource "github_actions_environment_variable" "spoke_env" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "SPOKE_ENV"
  value         = var.env
}

resource "github_actions_environment_variable" "vpc_cidr" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "VPC_CIDR"
  value         = var.vpc_cidr
}

resource "github_actions_environment_variable" "master_count" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "MASTER_COUNT"
  value         = tostring(var.master_count)
}

resource "github_actions_environment_variable" "worker_count" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "WORKER_COUNT"
  value         = tostring(var.worker_count)
}

resource "github_actions_environment_variable" "opensearch_master_count" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_MASTER_COUNT"
  value         = tostring(var.opensearch_master_count)
}

resource "github_actions_environment_variable" "opensearch_worker_count" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_WORKER_COUNT"
  value         = tostring(var.opensearch_worker_count)
}

resource "github_actions_environment_variable" "domain_name" {
  count         = var.domain_name != "" ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "DOMAIN_NAME"
  value         = var.domain_name
}

resource "github_actions_environment_variable" "subdomain_prefix" {
  count         = var.domain_name != "" && var.subdomain_prefix != "" ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "SUBDOMAIN_PREFIX"
  value         = var.subdomain_prefix
}

resource "github_actions_environment_variable" "alb_dns_name" {
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "ALB_DNS_NAME"
  value         = aws_lb.public_ingress.dns_name
}

resource "github_actions_environment_variable" "cert_email" {
  count         = var.domain_name != "" ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "CERT_EMAIL"
  value         = var.cloudflare_email
}

resource "github_actions_environment_variable" "db_private_dns" {
  count         = var.domain_name != "" && var.db_count > 0 ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "DB_PRIVATE_DNS"
  value         = local.db_fqdn
}

resource "github_actions_environment_variable" "opensearch_subdomain" {
  count         = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_SUBDOMAIN"
  value         = local.opensearch_fqdn
}

resource "github_actions_environment_variable" "opensearch_ebs_volume_id" {
  count         = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_EBS_VOLUME_ID"
  value         = aws_ebs_volume.opensearch_storage[0].id
}

resource "github_actions_environment_variable" "opensearch_nlb_dns" {
  count         = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_NLB_DNS"
  value         = aws_lb.opensearch_internal[0].dns_name
}

resource "github_actions_environment_variable" "opensearch_api_nlb_dns" {
  count         = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_API_NLB_DNS"
  value         = aws_lb.opensearch_api_internal[0].dns_name
}

resource "github_actions_environment_variable" "opensearch_dashboard_fqdn" {
  count         = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  repository    = split("/", var.github_repo)[1]
  environment   = github_repository_environment.deployment_env.environment
  variable_name = "OPENSEARCH_DASHBOARD_FQDN"
  value         = local.opensearch_dashboard_fqdn
}

resource "github_actions_environment_secret" "cloudflare_api_token" {
  count           = var.domain_name != "" && (var.cloudflare_api_token != "" || var.cloudflare_api_key != "") ? 1 : 0
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  secret_name     = "CLOUDFLARE_API_TOKEN"
  plaintext_value = var.cloudflare_api_token != "" ? var.cloudflare_api_token : var.cloudflare_api_key
}

# Resource Group
resource "aws_resourcegroups_group" "spoke_resources" {
  name = "${var.project_name}-${var.env}-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project_name]
        },
        {
          Key    = "Layer"
          Values = ["spoke"]
        },
        {
          Key    = "Env"
          Values = [var.env]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-resources"
  })
}

# Public ALB in Hub VPC with end-to-end encryption
resource "aws_lb" "public_ingress" {
  name               = "${var.project_name}-${var.env}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for assoc in data.aws_route_table.hub_public.associations : assoc.subnet_id if assoc.subnet_id != ""]

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-public-alb"
  })
}

# Security group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.env}-alb-"
  vpc_id      = data.aws_vpc.hub.id
  description = "Security group for public ALB"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTP from anywhere"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS from anywhere"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all outbound"
}

# ACM Certificate for ALB
resource "aws_acm_certificate" "wildcard" {
  count                     = var.domain_name != "" ? 1 : 0
  domain_name               = var.subdomain_prefix == "" ? "*.${var.domain_name}" : "*.${var.subdomain_prefix}.${var.domain_name}"
  validation_method         = "DNS"
  subject_alternative_names = var.subdomain_prefix == "" ? [var.domain_name] : ["${var.subdomain_prefix}.${var.domain_name}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-wildcard-cert"
  })
}

# Cloudflare Zone lookup
data "cloudflare_zone" "main" {
  count = var.domain_name != "" ? 1 : 0

  filter = {
    name = var.domain_name
  }
}

# Cloudflare DNS records for ACM validation
# First validation record (always created)
resource "cloudflare_dns_record" "cert_validation" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = data.cloudflare_zone.main[0].id
  name    = trimsuffix(tolist(aws_acm_certificate.wildcard[0].domain_validation_options)[0].resource_record_name, ".")
  content = trimsuffix(tolist(aws_acm_certificate.wildcard[0].domain_validation_options)[0].resource_record_value, ".")
  type    = tolist(aws_acm_certificate.wildcard[0].domain_validation_options)[0].resource_record_type
  ttl     = 60
  proxied = false
}

# ACM Certificate validation
resource "aws_acm_certificate_validation" "wildcard" {
  count           = var.domain_name != "" ? 1 : 0
  certificate_arn = aws_acm_certificate.wildcard[0].arn

  # Don't specify validation_record_fqdns - let AWS handle it automatically
  # The DNS records are created above and AWS will detect them

  depends_on = [
    cloudflare_dns_record.cert_validation
  ]

  timeouts {
    create = "45m"
  }
}

# Target group for HTTPS backend (ALB -> Istio HTTPS on 30443)
resource "aws_lb_target_group" "public_https" {
  name        = "${var.project_name}-${var.env}-pub-https"
  port        = 30443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = data.aws_vpc.hub.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/"
    port                = 30443
    protocol            = "HTTPS"
    timeout             = 10
    unhealthy_threshold = 2
    matcher             = "200-499"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-pub-https-tg"
  })
}

# Register spoke worker private IPs as HTTPS targets (cross-VPC via TGW)
resource "aws_lb_target_group_attachment" "public_https_workers" {
  count             = var.worker_count
  target_group_arn  = aws_lb_target_group.public_https.arn
  target_id         = aws_instance.k3s_workers[count.index].private_ip
  port              = 30443
  availability_zone = aws_instance.k3s_workers[count.index].availability_zone
}

# Register spoke master private IPs as HTTPS targets (cross-VPC via TGW)
resource "aws_lb_target_group_attachment" "public_https_masters" {
  count             = var.master_count
  target_group_arn  = aws_lb_target_group.public_https.arn
  target_id         = aws_instance.k3s_masters[count.index].private_ip
  port              = 30443
  availability_zone = aws_instance.k3s_masters[count.index].availability_zone
}

# Target group for OpenSearch Dashboard HTTPS backend (ALB -> OpenSearch Dashboard HTTPS on 30601)
resource "aws_lb_target_group" "opensearch_dashboard_https" {
  count       = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? 1 : 0
  name        = "${var.project_name}-${var.env}-os-dash-https"
  port        = 30601
  protocol    = "HTTPS"
  vpc_id      = data.aws_vpc.hub.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,302"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-opensearch-dashboard-https-tg"
  })
}

# Register OpenSearch master private IPs as Dashboard HTTPS targets (cross-VPC via TGW)
resource "aws_lb_target_group_attachment" "opensearch_dashboard_https_masters" {
  count             = var.opensearch_master_count
  target_group_arn  = aws_lb_target_group.opensearch_dashboard_https[0].arn
  target_id         = aws_instance.opensearch_masters[count.index].private_ip
  port              = 30601
  availability_zone = aws_instance.opensearch_masters[count.index].availability_zone
}

# Register OpenSearch worker private IPs as Dashboard HTTPS targets (cross-VPC via TGW)
resource "aws_lb_target_group_attachment" "opensearch_dashboard_https_workers" {
  count             = var.opensearch_worker_count
  target_group_arn  = aws_lb_target_group.opensearch_dashboard_https[0].arn
  target_id         = aws_instance.opensearch_workers[count.index].private_ip
  port              = 30601
  availability_zone = aws_instance.opensearch_workers[count.index].availability_zone
}



# HTTP listener - redirect to HTTPS
resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public_ingress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener - terminate TLS with ACM, forward HTTPS to Istio
resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public_ingress.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.wildcard[0].arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Access Denied"
      status_code  = "403"
    }
  }

  depends_on = [aws_acm_certificate_validation.wildcard]
}



# Listener rule: Forward OpenSearch Dashboard traffic
resource "aws_lb_listener_rule" "opensearch_dashboard" {
  count        = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  listener_arn = aws_lb_listener.public_https.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opensearch_dashboard_https[0].arn
  }

  condition {
    host_header {
      values = [local.opensearch_dashboard_fqdn]
    }
  }
}

# Listener rule: Forward if Cloudflare header present
resource "aws_lb_listener_rule" "cloudflare_header_validation" {
  count        = var.enable_cloudflare_restriction && var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.public_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_https.arn
  }

  condition {
    http_header {
      http_header_name = "X-Cloudflare-Zone-Id"
      values           = [data.cloudflare_zone.main[0].id]
    }
  }
}

# Listener rule: Forward all if restriction disabled
resource "aws_lb_listener_rule" "allow_all" {
  count        = var.enable_cloudflare_restriction ? 0 : 1
  listener_arn = aws_lb_listener.public_https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_https.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Cloudflare DNS records
resource "cloudflare_dns_record" "wildcard" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = var.subdomain_prefix == "" ? "*" : "*.${var.subdomain_prefix}"
  content = aws_lb.public_ingress.dns_name
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "root" {
  count   = var.domain_name != "" && var.subdomain_prefix == "" ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = "@"
  content = aws_lb.public_ingress.dns_name
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "subdomain_root" {
  count   = var.domain_name != "" && var.subdomain_prefix != "" ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = var.subdomain_prefix
  content = aws_lb.public_ingress.dns_name
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "www" {
  count   = var.domain_name != "" && var.subdomain_prefix == "" ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = "www"
  content = aws_lb.public_ingress.dns_name
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "opensearch_dashboard" {
  count   = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = local.opensearch_dashboard_subdomain
  content = aws_lb.public_ingress.dns_name
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

# Cloudflare Transform Rule for header validation (only for prod-spoke)
resource "cloudflare_ruleset" "transform_add_header" {
  count   = var.enable_cloudflare_restriction && var.domain_name != "" && var.env == "prod-spoke" ? 1 : 0
  zone_id = data.cloudflare_zone.main[0].id
  name    = "${var.env}-add-zone-header"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [{
    ref         = "add_zone_id_header"
    description = "Add X-Cloudflare-Zone-Id header for ALB validation"
    expression  = "(http.host eq \"${var.domain_name}\" or http.host eq \"www.${var.domain_name}\" or http.host wildcard \"*.${var.domain_name}\")"
    action      = "rewrite"

    action_parameters = {
      headers = {
        "X-Cloudflare-Zone-Id" = {
          operation = "set"
          value     = data.cloudflare_zone.main[0].id
        }
      }
    }
  }]
}

# Private Hosted Zone for Database
resource "aws_route53_zone" "db_private" {
  count = var.domain_name != "" && var.db_count > 0 ? 1 : 0
  name  = var.domain_name

  vpc {
    vpc_id = aws_vpc.spoke.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-db-private-zone"
  })
}

# DNS Record for Database Instance
resource "aws_route53_record" "db" {
  count   = var.domain_name != "" && var.db_count > 0 ? 1 : 0
  zone_id = aws_route53_zone.db_private[0].zone_id
  name    = local.db_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_instance.databases[0].private_ip]
}

# DNS Record for OpenSearch API NLB (uses existing database private zone)
resource "aws_route53_record" "opensearch" {
  count   = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  zone_id = aws_route53_zone.db_private[0].zone_id
  name    = local.opensearch_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.opensearch_api_internal[0].dns_name
    zone_id                = aws_lb.opensearch_api_internal[0].zone_id
    evaluate_target_health = true
  }
}

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  count = var.enable_ebs_backup ? 1 : 0
  name  = "${var.project_name}-${var.env}-backup-vault"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-backup-vault"
  })
}

# AWS Backup Plan
resource "aws_backup_plan" "ebs_backup" {
  count = var.enable_ebs_backup ? 1 : 0
  name  = "${var.project_name}-${var.env}-ebs-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = var.backup_schedule

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-ebs-backup-plan"
  })
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  count = var.enable_ebs_backup ? 1 : 0
  name  = "${var.project_name}-${var.env}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.enable_ebs_backup ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  count      = var.enable_ebs_backup ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup Selection for Database Volumes
resource "aws_backup_selection" "db_volumes" {
  count        = var.enable_ebs_backup && var.db_count > 0 ? 1 : 0
  name         = "${var.project_name}-${var.env}-db-volumes"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.ebs_backup[0].id

  resources = aws_ebs_volume.db_volumes[*].arn
}

# Backup Selection for OpenSearch Storage Volume
resource "aws_backup_selection" "opensearch_storage" {
  count        = var.enable_ebs_backup && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? 1 : 0
  name         = "${var.project_name}-${var.env}-opensearch-storage"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.ebs_backup[0].id

  resources = [aws_ebs_volume.opensearch_storage[0].arn]
}

# Generate JWT secrets
resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "jwt_refresh_secret" {
  length  = 64
  special = true
}

# Store JWT secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project_name}/${var.deployment_environment}/jwt-secret"
  description = "JWT secret for ${var.deployment_environment} environment"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.env}-jwt-secret"
    Service = "authentication"
  })
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

# Store JWT refresh secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "jwt_refresh_secret" {
  name        = "${var.project_name}/${var.deployment_environment}/jwt-refresh-secret"
  description = "JWT refresh secret for ${var.deployment_environment} environment"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.env}-jwt-refresh-secret"
    Service = "authentication"
  })
}

resource "aws_secretsmanager_secret_version" "jwt_refresh_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_refresh_secret.id
  secret_string = random_password.jwt_refresh_secret.result
}

# CI Repository Environments and Secrets for ECR Access
resource "github_repository_environment" "ci_deployment_env" {
  for_each    = toset(var.ci_repositories)
  repository  = split("/", each.value)[1]
  environment = var.deployment_environment
}

resource "github_actions_environment_secret" "ci_aws_role_arn" {
  for_each        = toset(var.ci_repositories)
  repository      = split("/", each.value)[1]
  environment     = github_repository_environment.ci_deployment_env[each.value].environment
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.ci_github_actions[each.value].arn
}

resource "github_actions_environment_variable" "ci_ecr_registry" {
  for_each      = toset(var.ci_repositories)
  repository    = split("/", each.value)[1]
  environment   = github_repository_environment.ci_deployment_env[each.value].environment
  variable_name = "ECR_REGISTRY"
  value         = split("/", data.aws_ecr_repository.shared_repositories["user-service"].repository_url)[0]
}

resource "github_actions_environment_variable" "ci_aws_region" {
  for_each      = toset(var.ci_repositories)
  repository    = split("/", each.value)[1]
  environment   = github_repository_environment.ci_deployment_env[each.value].environment
  variable_name = "AWS_REGION"
  value         = var.aws_region
}
