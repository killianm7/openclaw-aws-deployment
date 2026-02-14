output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.openclaw.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.openclaw.arn
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.openclaw.private_ip
}

output "public_ip" {
  description = "Public IP address of the instance (if applicable)"
  value       = aws_instance.openclaw.public_ip
}