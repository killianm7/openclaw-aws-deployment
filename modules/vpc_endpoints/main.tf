# VPC Endpoints Module - Uses region from root module

# Security group for VPC endpoints
resource "aws_security_group" "endpoints" {
  name_prefix = "openclaw-vpce-"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from OpenClaw security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.security_group_id]
  }

  tags = merge(var.tags, {
    Name = "openclaw-vpce-sg"
  })
}

# SSM endpoints (required for SSM Session Manager via VPC endpoints)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = merge(var.tags, {
    Name = "openclaw-ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = merge(var.tags, {
    Name = "openclaw-ssmmessages-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = merge(var.tags, {
    Name = "openclaw-ec2messages-endpoint"
  })
}

# Bedrock endpoint (only if using Bedrock)
resource "aws_vpc_endpoint" "bedrock" {
  count = var.enable_bedrock ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = merge(var.tags, {
    Name = "openclaw-bedrock-endpoint"
  })
}