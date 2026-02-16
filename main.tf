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
  is_arm64           = can(regex("^t4g|^c6g|^c7g|^m6g|^m7g|^r6g|^r7g", var.instance_type))
  architecture_label = local.is_arm64 ? "arm64" : "amd64"

  # SSM parameter paths (not managed by Terraform -- written by instance at boot)
  ssm_prefix             = var.ssm_parameter_prefix
  gateway_token_ssm_path = "${local.ssm_prefix}/${var.environment}/gateway-token"

  # Sort subnet IDs for deterministic selection
  sorted_subnet_ids = sort(data.aws_subnets.default.ids)
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
  subnet_ids        = local.sorted_subnet_ids
  enable_bedrock    = true # Always enable -- Bedrock is default and fallback
  tags              = var.tags
  aws_region        = data.aws_region.current.name
}

module "ec2" {
  source = "./modules/ec2"

  ami_id               = data.aws_ami.ubuntu_2404.id
  instance_type        = var.instance_type
  subnet_id            = local.sorted_subnet_ids[0]
  security_group_id    = module.network.security_group_id
  iam_instance_profile = module.iam.instance_profile_name

  root_volume_size          = var.root_volume_size
  delete_ebs_on_termination = var.delete_ebs_on_termination
  environment               = var.environment

  model_provider         = var.model_provider
  bedrock_model_id       = var.bedrock_model_id
  bedrock_context_window = var.bedrock_context_window
  bedrock_max_tokens     = var.bedrock_max_tokens
  openrouter_model_id    = var.openrouter_model_id
  gateway_token_ssm_path = local.gateway_token_ssm_path
  openrouter_ssm_param   = var.openrouter_ssm_parameter
  log_group              = aws_cloudwatch_log_group.user_data.name
  region                 = data.aws_region.current.name

  tags = var.tags
}
