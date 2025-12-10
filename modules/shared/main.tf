resource "aws_ecr_repository" "main" {
  for_each             = var.enable_deletion_protection ? toset([]) : toset(local.repository_names)
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name    = each.value
    Service = split("-", each.value)[1]
  })
}

resource "aws_ecr_repository" "main_protected" {
  for_each             = var.enable_deletion_protection ? toset(local.repository_names) : toset([])
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name    = each.value
    Service = split("-", each.value)[1]
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = toset(local.repository_names)
  repository = each.value

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  depends_on = [aws_ecr_repository.main, aws_ecr_repository.main_protected]
}

resource "aws_ecr_repository_policy" "main" {
  for_each   = toset(local.repository_names)
  repository = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_ecr_repository.main, aws_ecr_repository.main_protected]
}

# Resource Group
resource "aws_resourcegroups_group" "shared_resources" {
  name = "${var.project_name}-shared-resources"

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
          Values = ["shared"]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-shared-resources"
  })
}
