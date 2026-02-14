output "endpoint_ids" {
  description = "IDs of created VPC endpoints"
  value       = concat(
    [aws_vpc_endpoint.ssm.id, aws_vpc_endpoint.ssmmessages.id, aws_vpc_endpoint.ec2messages.id],
    var.enable_bedrock ? [aws_vpc_endpoint.bedrock[0].id] : []
  )
}