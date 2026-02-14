variable "environment" {
  description = "Environment name"
  type        = string
}

variable "model_provider" {
  description = "Model provider (openrouter or bedrock)"
  type        = string
}

variable "ssm_parameter_prefix" {
  description = "SSM parameter prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}