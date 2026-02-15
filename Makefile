.PHONY: help fmt validate security plan apply destroy test test-static test-plan test-unit

# Default target
help:
	@echo "OpenClaw Terraform Deployment - Available Commands"
	@echo "=================================================="
	@echo ""
	@echo "Setup & Formatting:"
	@echo "  make fmt           - Format all Terraform files"
	@echo "  make validate      - Validate Terraform configuration"
	@echo "  make init          - Initialize Terraform (download providers)"
	@echo ""
	@echo "Security:"
	@echo "  make security      - Run tfsec security scan"
	@echo ""
	@echo "Testing (No Deployment):"
	@echo "  make test          - Run complete test suite (requires AWS)"
	@echo "  make test-static   - Run static analysis only (no AWS needed)"
	@echo "  make test-plan     - Run terraform plan only (requires AWS)"
	@echo "  make test-unit     - Run Terraform unit tests"
	@echo ""
	@echo "Deployment:"
	@echo "  make plan          - Generate deployment plan"
	@echo "  make apply         - Apply deployment (creates resources)"
	@echo "  make destroy       - Destroy all resources"
	@echo ""
	@echo "CI/CD:"
	@echo "  make ci            - Run all checks for CI/CD pipeline"

# Formatting and validation
fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

validate:
	@echo "Validating Terraform configuration..."
	terraform validate

init:
	@echo "Initializing Terraform..."
	terraform init

# Security scanning
security:
	@echo "Running security scan with tfsec..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec . --config-file tests/.tfsec/config.yml --severity HIGH,CRITICAL; \
	else \
		echo "tfsec not installed. Install with: brew install tfsec"; \
		exit 1; \
	fi

# Testing targets (from tests/ directory)
test:
	@echo "Running complete test suite..."
	@./tests/test-deployment.sh

test-static:
	@echo "Running static analysis only..."
	@./tests/test-deployment.sh --static-only

test-plan:
	@echo "Running terraform plan analysis..."
	@./tests/test-deployment.sh --plan-only

test-unit:
	@echo "Running Terraform unit tests..."
	@terraform test

# CI/CD target (strict mode)
ci:
	@echo "Running CI/CD validation..."
	@./tests/test-deployment.sh --ci

# Deployment targets
plan:
	@echo "Generating Terraform plan..."
	terraform plan -out=tfplan

apply:
	@echo "Applying Terraform plan..."
	terraform apply tfplan

destroy:
	@echo "Planning destruction of all resources..."
	terraform plan -destroy
	@echo ""
	@echo "To destroy resources, run: terraform destroy"
