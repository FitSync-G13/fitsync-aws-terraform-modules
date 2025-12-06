resource "aws_resourcegroups_group" "shared_ecr" {
  name = "${var.env}-shared-ecr-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Module"
          Values = ["shared-ecr"]
        },
        {
          Key    = "Env"
          Values = [var.env]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-shared-ecr-resources"
  })
}
