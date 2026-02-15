# EC2 Instance
resource "aws_instance" "openclaw" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.iam_instance_profile

  # Enforce IMDSv2 (Instance Metadata Service v2) for SSRF protection
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false # Preserve data on instance termination
  }

  user_data = base64encode(templatefile("${path.module}/../../files/user_data.sh.tpl", {
    environment            = var.environment
    model_provider         = var.model_provider
    bedrock_model_id       = var.bedrock_model_id
    gateway_token_ssm_path = var.gateway_token_ssm_path
    openrouter_ssm_param   = var.openrouter_ssm_param
    region                 = var.region
    log_group              = var.log_group
  }))

  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "openclaw-${var.environment}"
  })
}