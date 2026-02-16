variable "ami_id" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name"
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 30
}

variable "delete_ebs_on_termination" {
  description = "Delete root EBS volume when instance is terminated"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "model_provider" {
  description = "Model provider"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
  default     = ""
}

variable "bedrock_context_window" {
  description = "Context window size for the Bedrock model"
  type        = number
  default     = 200000
}

variable "bedrock_max_tokens" {
  description = "Maximum output tokens for the Bedrock model"
  type        = number
  default     = 8192
}

variable "openrouter_model_id" {
  description = "OpenRouter model ID"
  type        = string
  default     = "openai/gpt-4o-mini"
}

variable "gateway_token_ssm_path" {
  description = "SSM parameter path where userdata will store the gateway token"
  type        = string
}

variable "openrouter_ssm_param" {
  description = "SSM parameter path for OpenRouter API key (empty if not using OpenRouter)"
  type        = string
  default     = ""
}

variable "log_group" {
  description = "CloudWatch log group name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}