data "aws_ssm_parameter" "ami" {
  name = var.ssm_parameter_name
}

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.hub_env}-vpc"]
  }
}

data "aws_internet_gateway" "hub" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.hub.id]
  }
}

data "aws_route_table" "hub_public" {
  vpc_id = data.aws_vpc.hub.id
  
  filter {
    name   = "route.gateway-id"
    values = [data.aws_internet_gateway.hub.id]
  }
}

resource "aws_route" "hub_to_spoke" {
  route_table_id         = data.aws_route_table.hub_public.id
  destination_cidr_block = var.vpc_cidr
  transit_gateway_id     = var.hub_tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

data "aws_ec2_transit_gateway_route_table" "default" {
  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }
  filter {
    name   = "transit-gateway-id"
    values = [var.hub_tgw_id]
  }
}

resource "aws_ec2_transit_gateway_route" "spoke_to_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.default.id
}

data "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.hub.id]
  }
  filter {
    name   = "transit-gateway-id"
    values = [var.hub_tgw_id]
  }
}

resource "aws_key_pair" "main" {
  key_name   = "${var.env}-key"
  public_key = file(var.public_key_path)

  tags = {
    Name        = "${var.env}-key"
    Environment = var.env
  }
}

# VPC with private subnets only
resource "aws_vpc" "spoke" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.env}-spoke-vpc"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

    tags = merge(local.common_tags, {
      Name = "${var.env}-private-subnet-${count.index + 1}"
    })
}

# Transit Gateway Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = var.hub_tgw_id
  vpc_id             = aws_vpc.spoke.id

  tags = merge(local.common_tags, {
    Name = "${var.env}-spoke-tgw-attachment"
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
    Name = "${var.env}-private-rt"
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
  name_prefix = "${var.env}-vpc-endpoints-"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "${var.env}-vpc-endpoints-sg"
    Environment = var.env
  }
}

# VPC Endpoints
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.spoke.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-ecr-api-endpoint"
    Environment = var.env
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.spoke.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-ecr-dkr-endpoint"
    Environment = var.env
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.spoke.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "${var.env}-s3-endpoint"
    Environment = var.env
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.env}-ec2-role"

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
  name = "${var.env}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Security Groups
resource "aws_security_group" "cluster" {
  name_prefix = "${var.env}-cluster-"
  vpc_id      = aws_vpc.spoke.id

  # SSH from hub bastion
  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "${var.env}-cluster-sg"
  })
}

# K3s Master Instances
resource "aws_instance" "k3s_masters" {
  count                  = var.master_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = merge(local.common_tags, {
    Name = "${var.env}-k3s-master-${count.index + 1}"
    Role = "k3s-master"
  })
}

# K3s Worker Instances
resource "aws_instance" "k3s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = merge(local.common_tags, {
    Name = "${var.env}-k3s-worker-${count.index + 1}"
    Role = "k3s-worker"
  })
}

# Database Instances
resource "aws_instance" "databases" {
  count                  = var.db_count
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = merge(local.common_tags, {
    Name = "${var.env}-db-${count.index + 1}"
    Role = "db"
  })
}

# EBS Volumes for Databases
resource "aws_ebs_volume" "db_volumes" {
  count             = var.db_count
  availability_zone = aws_instance.databases[count.index].availability_zone
  size              = var.db_vol_size
  type              = "gp3"

  tags = {
    Name        = "${var.env}-db-volume-${count.index + 1}"
    Environment = var.env
  }
}

resource "aws_volume_attachment" "db_attachments" {
  count       = var.db_count
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.db_volumes[count.index].id
  instance_id = aws_instance.databases[count.index].id
}

# Network Load Balancer for K3s API
resource "aws_lb" "k3s_api" {
  name               = "${var.env}-k3s-api-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = {
    Name        = "${var.env}-k3s-api-nlb"
    Environment = var.env
  }
}

resource "aws_lb_target_group" "k3s_api" {
  name     = "${var.env}-k3s-api-tg"
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

  tags = {
    Name        = "${var.env}-k3s-api-tg"
    Environment = var.env
  }
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
