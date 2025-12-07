provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : null
  api_key   = var.cloudflare_api_key != "" ? var.cloudflare_api_key : null
  email     = var.cloudflare_email != "" ? var.cloudflare_email : null
}
