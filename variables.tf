# Input Variables for OpenClaw Terraform Deployment

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^(us|eu|ap|sa|ca|af|me)-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Must be a valid AWS region format (e.g., us-west-2, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type. t4g.small is cheapest (ARM64/Graviton). t3.small is cheapest x86."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = can(regex("^(t3|t4g|c5|c6g|c7g)[.](small|medium|large|xlarge)$", var.instance_type))
    error_message = "Instance type must be t3.* (x86) or t4g/c6g/c7g.* (ARM64) in small/medium/large/xlarge sizes."
  }
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for SSM and Bedrock (adds ~$22/month). Recommended for production."
  type        = bool
  default     = false
}

variable "model_provider" {
  description = "AI model provider: 'openrouter' (default) or 'bedrock'"
  type        = string
  default     = "openrouter"

  validation {
    condition     = contains(["openrouter", "bedrock"], var.model_provider)
    error_message = "Model provider must be 'openrouter' or 'bedrock'."
  }
}

variable "openrouter_api_key" {
  description = "OpenRouter API key (required if model_provider = 'openrouter'). Stored in SSM SecureString."
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_model_id" {
  description = "Bedrock model ID (required if model_provider = 'bedrock')"
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "ssm_parameter_prefix" {
  description = "Prefix for SSM Parameter Store paths"
  type        = string
  default     = "/openclaw"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 20 and 1000 GB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}