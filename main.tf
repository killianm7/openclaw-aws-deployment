# Data Sources

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# Ubuntu 24.04 LTS AMI lookup
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${local.architecture_label}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = local.is_arm64 ? ["arm64"] : ["x86_64"]
  }
}

# Locals
locals {
  # Determine architecture based on instance type prefix
  is_arm64         = can(regex("^t4g|^c6g|^c7g|^m6g|^m7g|^r6g|^r7g", var.instance_type))
  architecture_label = local.is_arm64 ? "arm64" : "amd64"
  
  # SSM parameter paths
  ssm_prefix       = var.ssm_parameter_prefix
  gateway_token    = "${local.ssm_prefix}/${var.environment}/gateway-token"
  openrouter_key   = "${local.ssm_prefix}/${var.environment}/openrouter-api-key"
  
  # Platform-specific configuration
  user_data_vars = {
    environment          = var.environment
    model_provider       = var.model_provider
    bedrock_model_id     = var.bedrock_model_id
    gateway_token_param  = aws_ssm_parameter.gateway_token.name
    openrouter_key_param = var.model_provider == "openrouter" ? aws_ssm_parameter.openrouter_api_key[0].name : ""
    region               = data.aws_region.current.name
    log_group            = aws_cloudwatch_log_group.user_data.name
  }
}

# Store OpenRouter API Key in SSM (only if using OpenRouter)
resource "aws_ssm_parameter" "openrouter_api_key" {
  count = var.model_provider == "openrouter" ? 1 : 0

  name  = local.openrouter_key
  type  = "SecureString"
  value = var.openrouter_api_key

  tags = {
    Name = "OpenRouter API Key"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

# Generate and store gateway token
resource "random_password" "gateway_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "gateway_token" {
  name  = local.gateway_token
  type  = "SecureString"
  value = random_password.gateway_token.result

  tags = {
    Name = "OpenClaw Gateway Token"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "user_data" {
  name              = "/openclaw/${var.environment}/user-data"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "openclaw-${var.environment}-logs"
  })
}

# Modules
module "iam" {
  source = "./modules/iam"

  environment          = var.environment
  model_provider       = var.model_provider
  ssm_parameter_prefix = local.ssm_prefix
  aws_region           = data.aws_region.current.name
  aws_account_id       = data.aws_caller_identity.current.account_id
}

module "network" {
  source = "./modules/network"

  vpc_id = data.aws_vpc.default.id
  tags   = var.tags
}

module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"
  count  = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = data.aws_vpc.default.id
  security_group_id = module.network.security_group_id
  subnet_ids        = data.aws_subnets.default.ids
  enable_bedrock    = var.model_provider == "bedrock"
  tags              = var.tags
  aws_region        = data.aws_region.current.name
}

module "ec2" {
  source = "./modules/ec2"

  ami_id               = data.aws_ami.ubuntu_2404.id
  instance_type        = var.instance_type
  subnet_id            = data.aws_subnets.default.ids[0]
  security_group_id    = module.network.security_group_id
  iam_instance_profile = module.iam.instance_profile_name

  root_volume_size = var.root_volume_size
  environment      = var.environment

  model_provider       = var.model_provider
  bedrock_model_id     = var.bedrock_model_id
  gateway_token_param  = aws_ssm_parameter.gateway_token.name
  openrouter_key_param = var.model_provider == "openrouter" ? aws_ssm_parameter.openrouter_api_key[0].name : ""
  log_group            = aws_cloudwatch_log_group.user_data.name
  region               = data.aws_region.current.name

  tags = var.tags
}