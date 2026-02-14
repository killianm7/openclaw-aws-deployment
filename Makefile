.PHONY: help init plan apply destroy ssh logs test clean

# Default AWS region
AWS_REGION ?= us-east-1

help: ## Show this help message
	@echo "OpenClaw AWS Deployment - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	cd terraform && terraform init

plan: ## Run Terraform plan
	cd terraform && terraform plan

apply: ## Deploy infrastructure
	cd terraform && terraform apply

apply-auto: ## Deploy infrastructure (auto-approve)
	cd terraform && terraform apply -auto-approve

destroy: ## Destroy all infrastructure
	cd terraform && terraform destroy

output: ## Show Terraform outputs
	cd terraform && terraform output

ssh: ## SSH into the EC2 instance
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	echo "Connecting to $$IP..." && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP

logs: ## View OpenClaw logs
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "sudo docker-compose -f /opt/openclaw/docker-compose.yml logs -f --tail=100"

status: ## Check OpenClaw status
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "sudo docker-compose -f /opt/openclaw/docker-compose.yml ps && curl -s http://localhost:18789/health"

restart: ## Restart OpenClaw
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "sudo docker-compose -f /opt/openclaw/docker-compose.yml restart"

update: ## Update OpenClaw to latest version
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "cd /opt/openclaw && sudo docker-compose pull && sudo docker-compose up -d"

test-api: ## Test API Gateway endpoint
	@URL=$$(cd terraform && terraform output -raw api_gateway_url) && \
	echo "Testing API Gateway: $$URL/webhook/telegram" && \
	curl -X POST "$$URL/webhook/telegram" \
		-H "Content-Type: application/json" \
		-d '{"test": true}'

test-health: ## Test OpenClaw health endpoint
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "curl -s http://localhost:18789/health | jq ."

get-token: ## Get OpenClaw gateway token (sensitive)
	@cd terraform && terraform output -raw openclaw_gateway_token

set-telegram-token: ## Set Telegram bot token in SSM
	@read -p "Enter Telegram Bot Token: " TOKEN; \
	aws ssm put-parameter \
		--name "/openclaw/channels/telegram/token" \
		--type "SecureString" \
		--value "$$TOKEN" \
		--overwrite \
		--region $(AWS_REGION) && \
	echo "Token stored in SSM"

set-claude-key: ## Set Anthropic Claude API key in SSM
	@read -p "Enter Claude API Key: " KEY; \
	aws ssm put-parameter \
		--name "/openclaw/providers/anthropic/api_key" \
		--type "SecureString" \
		--value "$$KEY" \
		--overwrite \
		--region $(AWS_REGION) && \
	echo "API key stored in SSM"

backup: ## Backup OpenClaw data
	@IP=$$(cd terraform && terraform output -raw ec2_public_ip) && \
	KEY=$$(cd terraform && terraform output -raw ssh_key_name 2>/dev/null || echo "openclaw-aws") && \
	BACKUP_FILE="openclaw-backup-$$(date +%Y%m%d-%H%M%S).tar.gz" && \
	ssh -i ~/.ssh/$$KEY.pem ec2-user@$$IP "sudo tar -czf /tmp/$$BACKUP_FILE /opt/openclaw/data /opt/openclaw/config" && \
	scp -i ~/.ssh/$$KEY.pem ec2-user@$$IP:/tmp/$$BACKUP_FILE ./ && \
	echo "Backup saved to: $$BACKUP_FILE"

costs: ## Estimate monthly costs
	@echo "Estimated Monthly Costs:"
	@echo "  EC2 (t3.micro):     ~\$8.50"
	@echo "  Elastic IP:         ~\$3.65"
	@echo "  API Gateway:        ~\$3.50"
	@echo "  Lambda:             ~\$0.20"
	@echo "  CloudWatch:         ~\$2.00"
	@echo "  SSM Parameters:     ~\$0.05"
	@echo "  Data Transfer:      ~\$1.00"
	@echo "  ------------------------"
	@echo "  Total:              ~\$18-25/month"

fmt: ## Format Terraform code
	cd terraform && terraform fmt -recursive

validate: ## Validate Terraform configuration
	cd terraform && terraform validate

clean: ## Clean up temporary files
	find . -type f -name "*.zip" -delete
	find . -type f -name "*.tfstate*" -delete
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleanup complete"

setup: ## Initial setup (run this first)
	@echo "Setting up OpenClaw AWS Deployment..."
	@echo ""
	@echo "Step 1: Get your public IP address"
	@curl -s https://api.ipify.org
	@echo ""
	@echo "Step 2: Copy and edit terraform.tfvars"
	@cp terraform/terraform.tfvars.example terraform/terraform.tfvars
	@echo "   terraform.tfvars created. Please edit it with your settings."
	@echo ""
	@echo "Step 3: Run 'make init' to initialize Terraform"
	@echo "Step 4: Run 'make apply' to deploy"
	@echo ""
	@echo "See RUNBOOK.md for detailed instructions."
