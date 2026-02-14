# Security Group - SSM-only access (no inbound ports)
resource "aws_security_group" "openclaw" {
  name_prefix = "openclaw-"
  description = "Security group for OpenClaw instance - SSM only, no SSH"
  vpc_id      = var.vpc_id

  # No ingress rules - SSM doesn't require inbound ports
  # SSM agent initiates outbound connection to AWS

  # Egress: Allow HTTPS for AWS services and package downloads
  egress {
    description = "HTTPS to anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: HTTP for package repositories (optional but helpful)
  egress {
    description = "HTTP to anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: DNS
  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Add UDP 123
  egress {
    description = "NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "openclaw-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}