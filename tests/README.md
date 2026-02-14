# OpenClaw Terraform Test Suite

Comprehensive testing framework for validating Terraform infrastructure WITHOUT deploying resources.

## Quick Start

```bash
# Run all tests (requires AWS credentials for plan phase)
cd tests
./test-deployment.sh

# Run only static analysis (no AWS needed)
./test-deployment.sh --static-only

# Run only terraform plan (requires AWS)
./test-deployment.sh --plan-only

# CI/CD mode (strict, non-interactive)
./test-deployment.sh --ci
```

## Test Structure

```
tests/
├── test-deployment.sh          # Main test runner
├── test-docker-compose.sh      # Docker Compose validator
├── validation.tftest.hcl       # Terraform unit tests
├── test.tfvars                 # Test variables
├── .tfsec/
│   └── config.yml             # Security scan configuration
└── README.md                   # This file
```

## What Gets Tested

### Phase 1: Static Analysis (No AWS Required)

- ✅ Terraform format validation (`terraform fmt`)
- ✅ Terraform initialization (downloads modules/providers)
- ✅ Syntax validation (`terraform validate`)
- ✅ Security scanning (`tfsec`)
- ✅ Docker Compose validation
- ✅ Module structure checks
- ✅ Variable validation
- ✅ User data script review

### Phase 2: Terraform Plan (Requires AWS Credentials)

- ✅ AWS credential validation
- ✅ Plan generation (shows what would be created)
- ✅ Resource counting
- ✅ Cost estimation
- ✅ Security analysis of plan

### Phase 3: Unit Tests

- ✅ Variable validation tests
- ✅ Module logic tests
- ✅ Default value verification

## Prerequisites

### Required

- Terraform >= 1.5.0
- AWS CLI configured (for plan phase)

### Optional

- tfsec (`brew install tfsec`)
- Docker (for compose validation)

## Usage Examples

### Development Workflow

```bash
# Before committing - validate everything
cd tests
./test-deployment.sh

# If you don't have AWS access yet
./test-deployment.sh --static-only
```

### CI/CD Integration

```bash
# In GitHub Actions, GitLab CI, etc.
./tests/test-deployment.sh --ci
```

### Docker Validation

```bash
# Test Docker Compose configuration
./tests/test-docker-compose.sh
```

### Terraform Unit Tests

```bash
# Run unit tests only
terraform test
```

## Understanding Results

### Success
```
✓ All checks passed!

Your Terraform configuration is valid and ready for deployment.

To deploy:
  terraform init
  terraform plan
  terraform apply
```

### Warnings (Yellow ⚠)
- Non-critical issues that should be reviewed
- Example: tfsec not installed, optional features disabled

### Errors (Red ✗)
- Must be fixed before deployment
- Example: Syntax errors, missing files, security violations

## Cost Estimation

The test suite provides rough cost estimates based on your configuration:

| Instance Type | VPC Endpoints | Monthly Cost |
|---------------|---------------|--------------|
| t4g.small     | Disabled      | ~$13-17      |
| t4g.small     | Enabled       | ~$35-45      |
| t3.small      | Disabled      | ~$15-19      |
| t4g.medium    | Disabled      | ~$25-30      |

*Note: Actual costs depend on usage, data transfer, and region.*

## Security Checks

### Automatically Verified

- ✅ IMDSv2 enforced (SSRF protection)
- ✅ EBS encryption enabled
- ✅ Security group has no unnecessary ingress
- ✅ Secrets stored in SSM Parameter Store (SecureString)
- ✅ No hardcoded credentials
- ✅ IAM least-privilege access

### Manual Review Required

- AWS account billing alerts
- CloudTrail logging
- VPC Flow Logs (if using VPC endpoints)
- Regular security patches (handled by Ubuntu 24.04 LTS)

## Customizing Tests

### Adding New Tests

1. **Variable Tests**: Edit `validation.tftest.hcl`
   ```hcl
   run "test_custom" {
     variables {
       custom_var = "value"
     }
     assert {
       condition = var.custom_var == "value"
       error_message = "Custom test failed"
     }
   }
   ```

2. **Security Rules**: Edit `.tfsec/config.yml`
   ```yaml
   exclude:
     - aws-check-name
   ```

3. **Test Variables**: Edit `test.tfvars`

### Skipping Checks

In `test-deployment.sh`, you can skip specific phases:
```bash
# Comment out unwanted phases
# run_static_analysis
run_terraform_plan
# run_terraform_tests
```

## Troubleshooting

### "AWS credentials not configured"

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### "Terraform version is below required"

```bash
# macOS
brew upgrade terraform

# Linux
sudo apt-get update && sudo apt-get install terraform
```

### "tfsec not installed"

```bash
brew install tfsec
# or
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
```

## Exit Codes

- `0`: All tests passed
- `1`: One or more tests failed
- `2`: Terraform plan shows changes (only in CI mode)

## Integration with Pre-commit Hooks

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: terraform-validate
        name: Terraform Validate
        entry: ./tests/test-deployment.sh --static-only
        language: system
        pass_filenames: false
        always_run: true
```

## Integration with CI/CD

### GitHub Actions

```yaml
name: Terraform Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: "1.5.0"
      
      - name: Run Tests
        run: ./tests/test-deployment.sh --static-only
```

### GitLab CI

```yaml
validate:
  stage: test
  image: hashicorp/terraform:1.5.0
  script:
    - ./tests/test-deployment.sh --static-only
```

## References

- [Terraform Testing](https://developer.hashicorp.com/terraform/language/tests)
- [tfsec Documentation](https://aquasecurity.github.io/tfsec/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## Contributing

When adding new resources:

1. Add variable tests to `validation.tftest.hcl`
2. Update security rules in `.tfsec/config.yml` if needed
3. Add validation logic to `test-deployment.sh`
4. Update this README

## License

MIT - See root repository LICENSE
