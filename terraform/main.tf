# OpenClaw AWS Deployment - Terraform Configuration
# This sets up a secure, low-cost OpenClaw deployment on AWS

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "openclaw"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access (your IP/32)"
  type        = string
  default     = "0.0.0.0/0"  # CHANGE THIS TO YOUR IP!
}

variable "key_name" {
  description = "Name of the EC2 key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"  # t3.micro is free tier eligible, t3.small recommended for better performance
}

variable "openclaw_gateway_token" {
  description = "Token for OpenClaw gateway authentication"
  type        = string
  sensitive   = true
  default     = ""  # Will be generated if empty
}

variable "telegram_bot_token" {
  description = "Telegram Bot API token"
  type        = string
  sensitive   = true
  default     = ""
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC Configuration
resource "aws_vpc" "openclaw" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "openclaw-vpc"
  }
}

resource "aws_internet_gateway" "openclaw" {
  vpc_id = aws_vpc.openclaw.id

  tags = {
    Name = "openclaw-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.openclaw.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "openclaw-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.openclaw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openclaw.id
  }

  tags = {
    Name = "openclaw-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "openclaw_ec2" {
  name_prefix = "openclaw-ec2-"
  description = "Security group for OpenClaw EC2 instance"
  vpc_id      = aws_vpc.openclaw.id

  # SSH access - RESTRICT TO YOUR IP!
  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # OpenClaw gateway - INTERNAL ONLY (Lambda to EC2)
  # This security group allows ingress from the Lambda security group
  ingress {
    description     = "OpenClaw gateway from Lambda"
    from_port       = 18789
    to_port         = 18789
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  # Outbound internet access
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "openclaw-ec2-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "lambda" {
  name_prefix = "openclaw-lambda-"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.openclaw.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "openclaw-lambda-sg"
  }
}

# IAM Role for EC2
resource "aws_iam_role" "openclaw_ec2" {
  name = "openclaw-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "openclaw_ec2" {
  name = "openclaw-ec2-policy"
  role = aws_iam_role.openclaw_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/openclaw/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/openclaw/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "openclaw_ec2" {
  name = "openclaw-ec2-profile"
  role = aws_iam_role.openclaw_ec2.name
}

# SSM Parameters for Secrets
resource "aws_ssm_parameter" "openclaw_gateway_token" {
  count = var.openclaw_gateway_token != "" ? 1 : 0

  name  = "/openclaw/gateway/token"
  type  = "SecureString"
  value = var.openclaw_gateway_token

  tags = {
    Name = "openclaw-gateway-token"
  }
}

resource "aws_ssm_parameter" "telegram_bot_token" {
  count = var.telegram_bot_token != "" ? 1 : 0

  name  = "/openclaw/channels/telegram/token"
  type  = "SecureString"
  value = var.telegram_bot_token

  tags = {
    Name = "openclaw-telegram-token"
  }
}

# CloudWatch Log Group for OpenClaw
resource "aws_cloudwatch_log_group" "openclaw" {
  name              = "/openclaw/application"
  retention_in_days = 30

  tags = {
    Name = "openclaw-logs"
  }
}

# EC2 Instance
resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.openclaw_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw_ec2.name

  user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh", {
    aws_region             = var.aws_region
    openclaw_log_group     = aws_cloudwatch_log_group.openclaw.name
    openclaw_gateway_token = var.openclaw_gateway_token != "" ? var.openclaw_gateway_token : random_password.gateway_token[0].result
  }))

  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "openclaw-server"
  }
}

# Generate gateway token if not provided
resource "random_password" "gateway_token" {
  count   = var.openclaw_gateway_token == "" ? 1 : 0
  length  = 64
  special = false
}

# Elastic IP for stable IP address (optional but recommended)
resource "aws_eip" "openclaw" {
  domain = "vpc"

  tags = {
    Name = "openclaw-eip"
  }
}

resource "aws_eip_association" "openclaw" {
  instance_id   = aws_instance.openclaw.id
  allocation_id = aws_eip.openclaw.id
}

# Lambda Function for Webhook Handler
resource "aws_iam_role" "lambda_webhook" {
  name = "openclaw-lambda-webhook-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_webhook" {
  name = "openclaw-lambda-webhook-policy"
  role = aws_iam_role.lambda_webhook.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "webhook_handler" {
  filename         = data.archive_file.lambda_webhook.output_path
  function_name    = "openclaw-webhook-handler"
  role             = aws_iam_role.lambda_webhook.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = [aws_subnet.public.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      OPENCLAW_HOST = aws_instance.openclaw.private_ip
      OPENCLAW_PORT = "18789"
      OPENCLAW_TOKEN = var.openclaw_gateway_token != "" ? var.openclaw_gateway_token : random_password.gateway_token[0].result
    }
  }

  depends_on = [aws_instance.openclaw]
}

data "archive_file" "lambda_webhook" {
  type        = "zip"
  source_file = "${path.module}/lambda/webhook_handler.py"
  output_path = "${path.module}/lambda/webhook_handler.zip"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_webhook" {
  name              = "/aws/lambda/${aws_lambda_function.webhook_handler.function_name}"
  retention_in_days = 14
}

# API Gateway
resource "aws_api_gateway_rest_api" "openclaw" {
  name        = "openclaw-webhook-api"
  description = "API Gateway for OpenClaw webhooks"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.openclaw.id
  parent_id   = aws_api_gateway_rest_api.openclaw.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_resource" "telegram" {
  rest_api_id = aws_api_gateway_rest_api.openclaw.id
  parent_id   = aws_api_gateway_resource.webhook.id
  path_part   = "telegram"
}

resource "aws_api_gateway_method" "telegram_post" {
  rest_api_id   = aws_api_gateway_rest_api.openclaw.id
  resource_id   = aws_api_gateway_resource.telegram.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "telegram_lambda" {
  rest_api_id = aws_api_gateway_rest_api.openclaw.id
  resource_id = aws_api_gateway_resource.telegram.id
  http_method = aws_api_gateway_method.telegram_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook_handler.invoke_arn
}

resource "aws_api_gateway_deployment" "openclaw" {
  depends_on = [
    aws_api_gateway_integration.telegram_lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.openclaw.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.openclaw.execution_arn}/*/*"
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.openclaw.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "ec2_public_ip" {
  description = "EC2 public IP address"
  value       = aws_eip.openclaw.public_ip
}

output "ec2_private_ip" {
  description = "EC2 private IP address"
  value       = aws_instance.openclaw.private_ip
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.openclaw.public_ip}"
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_deployment.openclaw.invoke_url}"
}

output "telegram_webhook_url" {
  description = "Telegram webhook URL (set this in BotFather)"
  value       = "${aws_api_gateway_deployment.openclaw.invoke_url}/webhook/telegram"
}

output "openclaw_gateway_token" {
  description = "OpenClaw gateway token (save this securely)"
  value       = var.openclaw_gateway_token != "" ? var.openclaw_gateway_token : random_password.gateway_token[0].result
  sensitive   = true
}

output "security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.openclaw_ec2.id
}
