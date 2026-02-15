output "instance_id" {
  description = "EC2 Instance ID"
  value       = module.ec2.instance_id
}

output "ssm_port_forward_command" {
  description = "Command to start SSM port forwarding for Web UI access"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${data.aws_region.current.name} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"18789\"]}'"
}

output "ssm_connect_command" {
  description = "Command to connect to instance via SSM"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${data.aws_region.current.name}"
}

output "gateway_token_ssm_path" {
  description = "SSM Parameter Store path for gateway token (written by instance at boot)"
  value       = local.gateway_token_ssm_path
}

output "gateway_token_retrieval_command" {
  description = "Command to retrieve the gateway token from SSM"
  value       = "aws ssm get-parameter --name ${local.gateway_token_ssm_path} --with-decryption --region ${data.aws_region.current.name} --query 'Parameter.Value' --output text"
}

output "web_ui_url" {
  description = "OpenClaw Web UI URL (requires port forwarding)"
  value       = "http://localhost:18789/?token=<retrieve-from-ssm>"
}

output "architecture" {
  description = "Instance architecture (x86_64 or arm64)"
  value       = local.is_arm64 ? "arm64" : "x86_64"
}

output "vpc_endpoints_enabled" {
  description = "Whether VPC endpoints are enabled"
  value       = var.enable_vpc_endpoints
}

output "model_provider" {
  description = "Configured model provider"
  value       = var.model_provider
}

output "monthly_cost_estimate" {
  description = "Estimated monthly cost"
  value       = var.enable_vpc_endpoints ? "~$35-45/month (includes VPC endpoints)" : "~$13-17/month (no VPC endpoints)"
}

output "openrouter_ssm_setup_command" {
  description = "Command to store OpenRouter API key in SSM (run once before deploy if using OpenRouter)"
  value       = "aws ssm put-parameter --name ${var.ssm_parameter_prefix}/${var.environment}/openrouter-api-key --type SecureString --value 'YOUR_KEY_HERE' --region ${data.aws_region.current.name}"
}

output "verification_commands" {
  description = "Commands to verify deployment"
  value       = <<-EOT
# Check instance status
aws ec2 describe-instances --instance-ids ${module.ec2.instance_id} --region ${data.aws_region.current.name}

# Get gateway token (written by instance at boot)
aws ssm get-parameter --name ${local.gateway_token_ssm_path} --with-decryption --region ${data.aws_region.current.name} --query 'Parameter.Value' --output text

# Connect via SSM
aws ssm start-session --target ${module.ec2.instance_id} --region ${data.aws_region.current.name}

# Check service status (run as ubuntu user on instance)
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 systemctl --user status openclaw

# View logs (run as ubuntu user on instance)
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 journalctl --user -u openclaw --no-pager -n 50

# View setup log
cat /var/log/openclaw-setup.log

# IMPORTANT: Gateway token is stored ONLY in AWS SSM Parameter Store.
# Never store tokens in plain text files or environment variables.
  EOT
}
