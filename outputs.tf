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
  description = "SSM Parameter Store path for gateway token"
  value       = aws_ssm_parameter.gateway_token.name
  sensitive   = true
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

output "verification_commands" {
  description = "Commands to verify deployment"
  value       = <<-EOT
# Check instance status
aws ec2 describe-instances --instance-ids ${module.ec2.instance_id} --region ${data.aws_region.current.name}

# Get gateway token
aws ssm get-parameter --name ${aws_ssm_parameter.gateway_token.name} --with-decryption --region ${data.aws_region.current.name} --query 'Parameter.Value' --output text

# Connect via SSM
aws ssm start-session --target ${module.ec2.instance_id} --region ${data.aws_region.current.name}

# Check logs on instance
sudo cat /var/log/openclaw-setup.log
sudo docker logs openclaw
  EOT
}