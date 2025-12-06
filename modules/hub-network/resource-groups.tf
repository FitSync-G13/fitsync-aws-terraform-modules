resource "aws_resourcegroups_group" "hub_network" {
  name = "${var.env}-hub-network-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Module"
          Values = ["hub-network"]
        },
        {
          Key    = "Env"
          Values = [var.env]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-hub-network-resources"
  })
}
