# AGENTS.md - Agentic Coding Guidelines

## Build/Lint/Test Commands

### Terraform Commands
```bash
# Format all Terraform files
terraform fmt -recursive

# Validate Terraform configuration
terraform validate

# Initialize Terraform (required before other commands)
terraform init

# Plan deployment
terraform plan

# Apply deployment
terraform apply

# Plan destroy
terraform plan -destroy

# Destroy resources
terraform destroy
```

### Security Scanning
```bash
# Install tfsec (if not already installed)
brew install tfsec

# Run security scan
make security-scan
# or manually:
tfsec .
```

## Code Style Guidelines

### File Structure
- Use separate files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Place reusable components in `modules/<module_name>/`
- Use `files/` directory for templates and scripts

### Naming Conventions
- Use `snake_case` for all resource names, variables, and outputs
- Resource names: lowercase with underscores (e.g., `aws_instance.openclaw`)
- Variable names: descriptive and prefixed by purpose if needed (e.g., `aws_region`, `instance_type`)
- Module names: lowercase, descriptive (e.g., `iam`, `network`, `ec2`)

### Formatting
- Run `terraform fmt -recursive` before committing
- Indent with 2 spaces
- Align equals signs in blocks for readability
- Maximum line length: 100 characters where practical

### Variables
```hcl
variable "example_name" {
  description = "Clear, descriptive description of the variable"
  type        = string  # Always specify type
  default     = "value" # Include default if applicable
  sensitive   = true    # Mark secrets with sensitive = true
  
  validation {
    condition     = can(regex("^pattern$", var.example_name))
    error_message = "Human-readable error message explaining valid values."
  }
}
```

### Resource Organization
1. Data sources first (with comment headers)
2. Local values
3. Resources in logical order (IAM before EC2)
4. Modules last

### Comments
- Use `#` for single-line comments
- Add section headers for groups: `# Data Sources`, `# Locals`, `# Resources`
- Comment complex logic or security-critical decisions
- Reference issue numbers for workarounds: `# See: github.com/org/repo/issues/123`

### Security Best Practices
- Always use `metadata_options { http_tokens = "required" }` for EC2 IMDSv2
- Scope IAM policies to specific resources, never use `*`
- Mark sensitive variables with `sensitive = true`
- Use `SecureString` for SSM parameters containing secrets
- Pin Docker images to specific versions, never use `latest`
- Encrypt EBS volumes: `encrypted = true`

### Error Handling
- Use validation blocks on variables with clear error messages
- Use `precondition` and `postcondition` lifecycle rules for complex validation
- Include `count` or `for_each` for conditional resources instead of complex logic

### Module Design
- Pass all required data via explicit variables (no implicit dependencies)
- Use clear variable descriptions with types and defaults
- Define outputs for all values other modules might need
- Keep modules focused on single responsibility

### Outputs
```hcl
output "resource_id" {
  description = "Clear description of the output value"
  value       = aws_resource.name.id
  sensitive   = true  # If value contains sensitive data
}
```

### Version Constraints
```hcl
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use pessimistic constraint operator
    }
  }
}
```

### Bash Scripts (user_data.sh.tpl)
- Use `set -euo pipefail` for strict error handling
- Add retry logic for network operations
- Use full paths for commands in production
- Comment each major step with progress indicators
- Redirect output to logs: `exec > >(tee /var/log/script.log)`

### Tagging
- Always include standard tags via `default_tags` in provider
- Resource-specific tags via `merge(var.tags, { Name = "specific-name" })`
- Standard tags: `Project`, `ManagedBy`, `Environment`

### Pre-commit Checklist
Before submitting changes:
1. [ ] Run `terraform fmt -recursive`
2. [ ] Run `terraform validate`
3. [ ] Run `make security-scan` (tfsec)
4. [ ] Ensure no hardcoded secrets
5. [ ] Verify all variables have descriptions and types
6. [ ] Check that sensitive data is marked with `sensitive = true`
7. [ ] Review IAM policies for least privilege
8. [ ] Test with `terraform plan` and review changes

### Documentation
- Update README.md for new features
- Document breaking changes in commit messages
- Add examples to terraform.tfvars.example for new variables

## Makefile Targets
```makefile
.PHONY: fmt validate security plan apply destroy

fmt:
	terraform fmt -recursive

validate:
	terraform validate

security:
	tfsec .

plan:
	terraform plan -out=tfplan

apply:
	terraform apply tfplan

destroy:
	terraform destroy
```
