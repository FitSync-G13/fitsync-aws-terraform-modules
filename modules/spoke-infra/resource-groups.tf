resource "aws_resourcegroups_group" "spoke_infra" {
  name = "${var.env}-spoke-infra-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Module"
          Values = ["spoke-infra"]
        },
        {
          Key    = "Env"
          Values = [var.env]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-spoke-infra-resources"
  })
}
