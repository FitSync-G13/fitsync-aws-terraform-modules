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
    matcher             = "200"
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
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

# Export spoke environment variables to GitHub (environment created by hub)
resource "github_actions_environment_variable" "spoke_env" {
  repository      = split("/", var.github_repo)[1]
  environment     = var.deployment_environment
  variable_name   = "SPOKE_ENV"
  value           = var.env
}

resource "github_actions_environment_variable" "vpc_cidr" {
  repository      = split("/", var.github_repo)[1]
  environment     = var.deployment_environment
  variable_name   = "VPC_CIDR"
  value           = var.vpc_cidr
}

resource "github_actions_environment_variable" "master_count" {
  repository      = split("/", var.github_repo)[1]
  environment     = var.deployment_environment
  variable_name   = "MASTER_COUNT"
  value           = tostring(var.master_count)
}

resource "github_actions_environment_variable" "worker_count" {
  repository      = split("/", var.github_repo)[1]
  environment     = var.deployment_environment
  variable_name   = "WORKER_COUNT"
  value           = tostring(var.worker_count)
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
