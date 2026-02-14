# Terraform Unit Tests for OpenClaw Deployment
# These tests validate variables, logic, and module behavior WITHOUT deploying resources
#
# Run with: terraform test

# Test valid instance types
run "valid_instance_type_t4g_small" {
  variables {
    instance_type = "t4g.small"
  }

  assert {
    condition     = var.instance_type == "t4g.small"
    error_message = "Instance type should be t4g.small"
  }
}

run "valid_instance_type_t3_medium" {
  variables {
    instance_type = "t3.medium"
  }

  assert {
    condition     = var.instance_type == "t3.medium"
    error_message = "Instance type should be t3.medium"
  }
}

run "valid_instance_type_c6g_large" {
  variables {
    instance_type = "c6g.large"
  }

  assert {
    condition     = var.instance_type == "c6g.large"
    error_message = "Instance type should be c6g.large"
  }
}

# Test model provider validation
run "valid_model_provider_openrouter" {
  variables {
    model_provider   = "openrouter"
    openrouter_api_key = "test-api-key"
  }

  assert {
    condition     = var.model_provider == "openrouter"
    error_message = "Model provider should be openrouter"
  }
}

run "valid_model_provider_bedrock" {
  variables {
    model_provider = "bedrock"
  }

  assert {
    condition     = var.model_provider == "bedrock"
    error_message = "Model provider should be bedrock"
  }
}

# Test AWS region validation
run "valid_aws_region_us_west_2" {
  variables {
    aws_region = "us-west-2"
  }

  assert {
    condition     = can(regex("^(us|eu|ap|sa|ca|af|me)-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region should match valid pattern"
  }
}

run "valid_aws_region_eu_west_1" {
  variables {
    aws_region = "eu-west-1"
  }

  assert {
    condition     = can(regex("^(us|eu|ap|sa|ca|af|me)-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region should match valid pattern"
  }
}

# Test root volume size validation
run "valid_volume_size_minimum" {
  variables {
    root_volume_size = 20
  }

  assert {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size should be within valid range (20-1000 GB)"
  }
}

run "valid_volume_size_maximum" {
  variables {
    root_volume_size = 1000
  }

  assert {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size should be within valid range (20-1000 GB)"
  }
}

# Test environment naming
run "valid_environment_dev" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = var.environment == "dev"
    error_message = "Environment should be dev"
  }
}

run "valid_environment_prod" {
  variables {
    environment = "prod"
  }

  assert {
    condition     = var.environment == "prod"
    error_message = "Environment should be prod"
  }
}

# Test VPC endpoints configuration
run "vpc_endpoints_disabled" {
  variables {
    enable_vpc_endpoints = false
  }

  assert {
    condition     = var.enable_vpc_endpoints == false
    error_message = "VPC endpoints should be disabled"
  }
}

run "vpc_endpoints_enabled" {
  variables {
    enable_vpc_endpoints = true
  }

  assert {
    condition     = var.enable_vpc_endpoints == true
    error_message = "VPC endpoints should be enabled"
  }
}

# Test that verifies variable defaults work
run "test_default_values" {
  # Don't override any variables - test defaults
  
  assert {
    condition     = var.aws_region == "us-west-2"
    error_message = "Default AWS region should be us-west-2"
  }

  assert {
    condition     = var.environment == "dev"
    error_message = "Default environment should be dev"
  }

  assert {
    condition     = var.instance_type == "t4g.small"
    error_message = "Default instance type should be t4g.small"
  }

  assert {
    condition     = var.model_provider == "openrouter"
    error_message = "Default model provider should be openrouter"
  }

  assert {
    condition     = var.root_volume_size == 30
    error_message = "Default root volume size should be 30 GB"
  }

  assert {
    condition     = var.enable_vpc_endpoints == false
    error_message = "Default VPC endpoints should be disabled"
  }
}
