# Test Variables for OpenClaw Terraform Testing
# These are safe test values - no real secrets or production configs

aws_region    = "us-west-2"
environment   = "test"
instance_type = "t4g.small"

# Model provider configuration
model_provider   = "bedrock"
bedrock_model_id = "amazon.nova-lite-v1:0"

# Optional features (disabled for cost savings in tests)
enable_vpc_endpoints = false

# Resource sizing
root_volume_size = 20

# Tags for test resources
tags = {
  Test      = "true"
  Temporary = "true"
  TestRun   = "validation"
}
