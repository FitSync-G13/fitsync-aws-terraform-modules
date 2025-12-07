provider "aws" {
  region = var.aws_region
}

provider "github" {
  token = var.github_token
  owner = split("/", var.github_repo)[0]
}
