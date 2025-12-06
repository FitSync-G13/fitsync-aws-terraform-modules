resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.env}-key"
  public_key = file(var.public_key_path)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-key"
  })
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.project_name}-${var.env}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.auto_public_subnets
  private_subnets = local.auto_private_subnets

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-vpc"
  })
}

module "tgw" {
  source = "terraform-aws-modules/transit-gateway/aws"

  name        = "${var.project_name}-${var.env}-tgw"
  description = "Transit Gateway for ${var.project_name} ${var.env} environment"

  enable_auto_accept_shared_attachments  = true
  enable_default_route_table_association = true
  enable_default_route_table_propagation = true

  vpc_attachments = {
    vpc = {
      vpc_id     = module.vpc.vpc_id
      subnet_ids = module.vpc.private_subnets

      dns_support  = true
      ipv6_support = false

      transit_gateway_default_route_table_association = true
      transit_gateway_default_route_table_propagation = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "protected" {
  count              = var.enable_deletion_protection ? 1 : 0
  transit_gateway_id = module.tgw.ec2_transit_gateway_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-tgw-protected-rt"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.env}-bastion-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-bastion-sg"
  })
}

resource "aws_instance" "bastion" {
  count                       = var.enable_deletion_protection ? 0 : 1
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.bastion_instance_type
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-bastion"
    Role = "bastion"
  })
}

resource "aws_instance" "bastion_protected" {
  count                       = var.enable_deletion_protection ? 1 : 0
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.bastion_instance_type
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-bastion"
    Role = "bastion"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

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

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.env}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
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

# Instance profile for GitHub Actions role
resource "aws_iam_instance_profile" "github_actions" {
  name = "${var.project_name}-${var.env}-github-actions-profile"
  role = aws_iam_role.github_actions.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.env}-github-actions-profile"
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
      }
    ]
  })
}

# Attach managed policy for SSM
resource "aws_iam_role_policy_attachment" "github_actions_ssm" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# GitHub repository secret for AWS Role ARN
resource "github_actions_secret" "aws_role_arn" {
  repository      = split("/", var.github_repo)[1]  # Extract repo name from "owner/repo"
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

# GitHub Environment for this deployment
resource "github_repository_environment" "deployment_env" {
  repository  = split("/", var.github_repo)[1]
  environment = var.deployment_environment
}

# Environment-specific secrets
resource "github_actions_environment_secret" "aws_role_arn_env" {
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

# Environment-specific variables
resource "github_actions_environment_variable" "aws_region" {
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  variable_name   = "AWS_REGION"
  value           = var.aws_region
}

resource "github_actions_environment_variable" "project_name" {
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  variable_name   = "PROJECT_NAME"
  value           = var.project_name
}

resource "github_actions_environment_variable" "hub_env" {
  repository      = split("/", var.github_repo)[1]
  environment     = github_repository_environment.deployment_env.environment
  variable_name   = "HUB_ENV"
  value           = var.env
}

# Resource Group
resource "aws_resourcegroups_group" "hub_resources" {
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
          Values = ["hub"]
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
