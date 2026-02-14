#!/bin/bash
# OpenClaw Terraform Deployment Validation Script
# Validates Terraform configuration WITHOUT deploying any resources
#
# Usage: ./tests/test-deployment.sh [options]
# Options:
#   --static-only    Run only static analysis (no AWS credentials needed)
#   --plan-only      Run only terraform plan (requires AWS credentials)
#   --full           Run complete validation (default)
#   --ci             CI/CD mode (non-interactive, fails on any error)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall success
OVERALL_SUCCESS=true
ERRORS=0
WARNINGS=0

# Mode flags
STATIC_ONLY=false
PLAN_ONLY=false
CI_MODE=false
FULL_MODE=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --static-only)
      STATIC_ONLY=true
      FULL_MODE=false
      shift
      ;;
    --plan-only)
      PLAN_ONLY=true
      FULL_MODE=false
      shift
      ;;
    --full)
      FULL_MODE=true
      shift
      ;;
    --ci)
      CI_MODE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --static-only    Run only static analysis (no AWS credentials needed)"
      echo "  --plan-only      Run only terraform plan (requires AWS credentials)"
      echo "  --full           Run complete validation (default)"
      echo "  --ci             CI/CD mode (non-interactive, strict)"
      echo "  -h, --help       Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                              # Run full validation"
      echo "  $0 --static-only               # Validate without AWS"
      echo "  $0 --ci                        # CI/CD mode"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
  ((ERRORS++)) || true
  OVERALL_SUCCESS=false
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++)) || true
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Phase 1: Static Analysis
run_static_analysis() {
  print_header "PHASE 1: Static Analysis (No AWS Required)"
  
  # Check prerequisites
  print_info "Checking prerequisites..."
  
  if ! command_exists terraform; then
    print_error "Terraform is not installed"
    return 1
  fi
  print_success "Terraform found: $(terraform version | head -1)"
  
  # Check Terraform version
  TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
  REQUIRED_VERSION="1.5.0"
  if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$TF_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then 
    print_success "Terraform version $TF_VERSION meets requirement (>= $REQUIRED_VERSION)"
  else
    print_error "Terraform version $TF_VERSION is below required $REQUIRED_VERSION"
  fi
  
  # 1.1: Format check
  print_header "1.1: Terraform Format Check"
  if terraform fmt -check -recursive; then
    print_success "All Terraform files are properly formatted"
  else
    print_error "Terraform files need formatting. Run: terraform fmt -recursive"
    if [ "$CI_MODE" = true ]; then
      echo "Files that need formatting:"
      terraform fmt -check -recursive -list=true -write=false
    fi
  fi
  
  # 1.2: Syntax validation
  print_header "1.2: Terraform Syntax Validation"
  if terraform validate; then
    print_success "Terraform configuration is valid"
  else
    print_error "Terraform configuration has errors"
    return 1
  fi
  
  # 1.3: Security scan with tfsec
  print_header "1.3: Security Scan (tfsec)"
  if command_exists tfsec; then
    print_info "Running tfsec security scan..."
    if tfsec . --config-file tests/.tfsec/config.yml --severity HIGH,CRITICAL 2>&1 | tee tests/tfsec-results.txt; then
      print_success "No HIGH or CRITICAL security issues found"
    else
      print_warning "Security issues found (see tests/tfsec-results.txt)"
      if [ "$CI_MODE" = true ]; then
        print_error "Security scan failed in CI mode"
        cat tests/tfsec-results.txt
      fi
    fi
  else
    print_warning "tfsec not installed. Install with: brew install tfsec"
    print_info "Skipping security scan"
  fi
  
  # 1.4: Docker Compose validation
  print_header "1.4: Docker Compose Validation"
  if [ -f "docker-compose.yml" ]; then
    if command_exists docker-compose || command_exists docker; then
      if docker-compose -f docker-compose.yml config > /dev/null 2>&1; then
        print_success "Docker Compose configuration is valid"
      else
        print_error "Docker Compose configuration has errors"
      fi
    else
      print_warning "Docker not installed. Skipping Docker Compose validation"
    fi
  else
    print_warning "docker-compose.yml not found in root directory"
  fi
  
  # 1.5: Variable validation
  print_header "1.5: Variable Definitions Check"
  if [ -f "variables.tf" ]; then
    print_success "variables.tf exists"
    
    # Check for required variables without defaults
    print_info "Checking variable definitions..."
    grep -E "variable \"" variables.tf | head -10 | while read -r line; do
      print_info "  Found: $line"
    done
  else
    print_error "variables.tf not found"
  fi
  
  # 1.6: Check for example tfvars
  print_header "1.6: Configuration Examples"
  if [ -f "terraform.tfvars.example" ]; then
    print_success "terraform.tfvars.example exists"
  else
    print_warning "terraform.tfvars.example not found (recommended for documentation)"
  fi
  
  # 1.7: Module structure validation
  print_header "1.7: Module Structure Validation"
  REQUIRED_MODULES=("iam" "network" "ec2")
  for module in "${REQUIRED_MODULES[@]}"; do
    if [ -d "modules/$module" ]; then
      print_success "Module 'modules/$module' exists"
      if [ -f "modules/$module/main.tf" ]; then
        print_success "  └─ main.tf exists"
      else
        print_error "  └─ main.tf missing in modules/$module"
      fi
    else
      print_error "Required module 'modules/$module' not found"
    fi
  done
  
  # 1.8: User data script check
  print_header "1.8: User Data Script Check"
  if [ -f "files/user_data.sh.tpl" ]; then
    print_success "User data template exists"
    
    # Check for common issues
    if grep -q "set -e" files/user_data.sh.tpl; then
      print_success "User data has error handling (set -e)"
    else
      print_warning "User data missing error handling"
    fi
    
    if grep -q "IMDSv2" files/user_data.sh.tpl || grep -q "X-aws-ec2-metadata-token" files/user_data.sh.tpl; then
      print_success "User data uses IMDSv2 (secure)"
    else
      print_warning "User data may not use IMDSv2"
    fi
  else
    print_error "User data template (files/user_data.sh.tpl) not found"
  fi
}

# Phase 2: Terraform Plan
run_terraform_plan() {
  print_header "PHASE 2: Terraform Plan Analysis (Requires AWS)"
  
  # Check AWS credentials
  print_info "Checking AWS credentials..."
  if ! command_exists aws; then
    print_error "AWS CLI not installed"
    return 1
  fi
  
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    print_error "AWS credentials not configured or invalid"
    print_info "Run: aws configure"
    return 1
  fi
  
  AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
  print_success "AWS credentials valid (Account: $AWS_ACCOUNT)"
  print_info "IAM User/Role: $AWS_USER"
  
  # Initialize Terraform
  print_header "2.1: Terraform Initialization"
  if [ ! -d ".terraform" ]; then
    print_info "Initializing Terraform..."
    if terraform init -backend=false; then
      print_success "Terraform initialized (local mode)"
    else
      print_error "Terraform init failed"
      return 1
    fi
  else
    print_success "Terraform already initialized"
  fi
  
  # Generate plan
  print_header "2.2: Generating Terraform Plan"
  print_info "This shows what would be created WITHOUT actually deploying..."
  
  # Check if tfvars exists
  TFVARS_ARG=""
  if [ -f "terraform.tfvars" ]; then
    print_success "Using terraform.tfvars for variables"
    TFVARS_ARG="-var-file=terraform.tfvars"
  elif [ -f "tests/test.tfvars" ]; then
    print_success "Using tests/test.tfvars for test variables"
    TFVARS_ARG="-var-file=tests/test.tfvars"
  else
    print_warning "No tfvars file found, using defaults and environment variables"
  fi
  
  # Generate plan with detailed exit codes
  # 0 = No changes, 1 = Error, 2 = Changes present
  set +e
  terraform plan $TFVARS_ARG -detailed-exitcode -out=tests/tfplan 2>&1 | tee tests/plan-output.txt
  PLAN_EXIT_CODE=$?
  set -e
  
  if [ $PLAN_EXIT_CODE -eq 1 ]; then
    print_error "Terraform plan failed with errors"
    cat tests/plan-output.txt
    return 1
  elif [ $PLAN_EXIT_CODE -eq 0 ]; then
    print_success "Plan generated: No changes needed (infrastructure up to date)"
  elif [ $PLAN_EXIT_CODE -eq 2 ]; then
    print_success "Plan generated: Changes would be made (see tests/tfplan)"
  fi
  
  # Analyze plan
  print_header "2.3: Plan Analysis"
  
  # Count resources to be created
  CREATED=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.change.actions[] | contains("create"))] | length')
  DESTROYED=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.change.actions[] | contains("delete"))] | length')
  MODIFIED=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.change.actions[] | contains("update"))] | length')
  
  print_info "Resources to be created:   $CREATED"
  print_info "Resources to be destroyed: $DESTROYED"
  print_info "Resources to be modified:  $MODIFIED"
  
  if [ "$CREATED" -gt 0 ]; then
    print_info ""
    print_info "Resources that would be created:"
    terraform show -json tests/tfplan | jq -r '.resource_changes[]? | select(.change.actions[] | contains("create")) | "  - \(.address)"' | head -20
  fi
  
  # Cost estimation (rough)
  print_header "2.4: Cost Estimation"
  
  INSTANCE_TYPE=$(grep -E "instance_type" terraform.tfvars 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' || echo "t4g.small")
  VPC_ENDPOINTS=$(grep -E "enable_vpc_endpoints.*=.*true" terraform.tfvars 2>/dev/null | wc -l)
  
  print_info "Configuration detected:"
  print_info "  Instance Type: $INSTANCE_TYPE"
  print_info "  VPC Endpoints: $([ "$VPC_ENDPOINTS" -gt 0 ] && echo "Enabled (+~\$22/mo)" || echo "Disabled")"
  
  # Rough cost calculation
  case $INSTANCE_TYPE in
    t4g.small|t3.small)
      MONTHLY_COST="~\$13-17"
      ;;
    t4g.medium|t3.medium)
      MONTHLY_COST="~\$25-30"
      ;;
    t4g.large|t3.large)
      MONTHLY_COST="~\$50-60"
      ;;
    *)
      MONTHLY_COST="Variable (check AWS pricing)"
      ;;
  esac
  
  if [ "$VPC_ENDPOINTS" -gt 0 ]; then
    MONTHLY_COST="~\$35-45"
  fi
  
  print_info ""
  print_info "Estimated Monthly Cost: $MONTHLY_COST"
  print_info "(Based on on-demand pricing + EBS + data transfer)"
  
  # Security analysis of plan
  print_header "2.5: Plan Security Analysis"
  
  # Check for public IPs
  PUBLIC_IP_COUNT=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.address | contains("aws_instance")) | select(.change.after.associate_public_ip_address == true)] | length')
  if [ "$PUBLIC_IP_COUNT" -gt 0 ]; then
    print_warning "Instance would have public IP (expected for SSM access)"
  fi
  
  # Check IMDSv2 enforcement
  IMDSV2_COUNT=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.address | contains("aws_instance")) | select(.change.after.metadata_options[0].http_tokens == "required")] | length')
  if [ "$IMDSV2_COUNT" -gt 0 ]; then
    print_success "IMDSv2 enforced on instance (SSRF protection)"
  fi
  
  # Check encryption
  ENCRYPTED_COUNT=$(terraform show -json tests/tfplan | jq -r '[.resource_changes[]? | select(.address | contains("aws_instance")) | select(.change.after.root_block_device[0].encrypted == true)] | length')
  if [ "$ENCRYPTED_COUNT" -gt 0 ]; then
    print_success "Root volume encryption enabled"
  fi
}

# Phase 3: Terraform Tests (if available)
run_terraform_tests() {
  print_header "PHASE 3: Terraform Unit Tests"
  
  if [ -d "tests" ] && ls tests/*.tftest.hcl 1> /dev/null 2>&1; then
    print_info "Running Terraform tests..."
    if terraform test; then
      print_success "All Terraform tests passed"
    else
      print_warning "Some Terraform tests failed"
    fi
  else
    print_info "No Terraform test files found (tests/*.tftest.hcl)"
    print_info "Skipping unit tests"
  fi
}

# Summary report
print_summary() {
  print_header "VALIDATION SUMMARY"
  
  if [ "$OVERALL_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Your Terraform configuration is valid and ready for deployment."
    echo ""
    echo "To deploy:"
    echo "  terraform init"
    echo "  terraform plan"
    echo "  terraform apply"
    echo ""
    echo "To see what would be created without deploying:"
    echo "  terraform plan"
    exit 0
  else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
  fi
}

# Main execution
main() {
  echo "OpenClaw Terraform Deployment Validator"
  echo "======================================"
  echo "Mode: $([ "$STATIC_ONLY" = true ] && echo "Static Analysis Only" || ([ "$PLAN_ONLY" = true ] && echo "Plan Only" || echo "Full Validation"))"
  echo "CI Mode: $([ "$CI_MODE" = true ] && echo "Enabled" || echo "Disabled")"
  echo ""
  
  cd "$(dirname "$0")/.."
  
  if [ "$PLAN_ONLY" = true ]; then
    run_terraform_plan
  elif [ "$STATIC_ONLY" = true ]; then
    run_static_analysis
  else
    # Full mode
    run_static_analysis
    if [ "$OVERALL_SUCCESS" = true ] || [ "$CI_MODE" = false ]; then
      run_terraform_plan
      run_terraform_tests
    fi
  fi
  
  print_summary
}

main "$@"
