# OpenClaw Terraform Deployment

Terraform infrastructure-as-code deployment for [OpenClaw](https://github.com/openclaw/openclaw) on AWS EC2 with native host install and Amazon Bedrock.

## Features

- **SSM-Only Access**: No SSH keys, no port 22 - pure AWS Systems Manager Session Manager
- **Cost-Optimized**: Defaults to cheapest instance (t4g.small ~$13/month), VPC endpoints optional
- **Bedrock Default**: Amazon Bedrock with IAM role auth (no API keys). OpenRouter supported as optional provider.
- **Ubuntu 24.04 LTS**: Production-ready OS with long-term support
- **Native Host Install**: Node.js + OpenClaw installed directly, managed as a systemd user service
- **Default VPC**: Zero additional networking costs, no NAT Gateway needed

## Quick Start

```bash
cd openclaw-aws-deployment

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (defaults work for Bedrock)

# 2. Deploy
terraform init
terraform plan
terraform apply

# 3. Wait ~8 minutes for instance setup, then access:

# Port forward (keep terminal open)
aws ssm start-session \
  --target $(terraform output -raw instance_id) \
  --region $(terraform output -raw model_provider | xargs -I{} aws configure get region) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

# Get token (new terminal)
eval $(terraform output -raw gateway_token_retrieval_command)

# Open browser: http://localhost:18789/?token=<token>
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  AWS Cloud                                          │
│                                                     │
│  ┌──────────────┐                                   │
│  │ EC2 Instance │── IAM Role ──▶ SSM / Bedrock      │
│  │  (Ubuntu)    │                                   │
│  │  Node.js     │── systemd ──▶ OpenClaw            │
│  └──────────────┘                                   │
│         │                                           │
│    Default VPC (no NAT Gateway)                     │
│         │                                           │
│  ┌──────────────┐                                   │
│  │  SSM Agent   │── Internet ──▶ AWS SSM           │
│  └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
              │
              ▼ (SSM Session Manager)
        ┌──────────────┐
        │   Your PC    │── Port Forward ──▶ localhost:18789
        └──────────────┘
```

## Configuration

See [terraform.tfvars.example](terraform.tfvars.example) for all options:

```hcl
# Cheapest instance (ARM64)
instance_type = "t4g.small"

# Model provider (Bedrock is default)
model_provider   = "bedrock"
bedrock_model_id = "amazon.nova-lite-v1:0"

# Optional: Use OpenRouter instead (set key in SSM first, see Runbook.md)
# model_provider           = "openrouter"
# openrouter_ssm_parameter = "/openclaw/dev/openrouter-api-key"

# Optional VPC endpoints (+$22/month)
enable_vpc_endpoints = false
```

## Project Structure

```
openclaw-aws-deployment/
├── main.tf                      # Root orchestration
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values
├── versions.tf                  # Provider constraints
├── terraform.tfvars.example     # Example configuration
├── Runbook.md                   # Complete operational guide
├── DIFF_SUMMARY.md              # Changes from CloudFormation
├── modules/
│   ├── iam/                     # IAM role & instance profile
│   ├── network/                 # Security group (SSM-only)
│   ├── ec2/                     # EC2 instance & user_data
│   └── vpc_endpoints/           # Optional VPC endpoints
└── files/
    └── user_data.sh.tpl         # Ubuntu setup script (host install)
```

## Cost Estimate

**Default Configuration** (t4g.small, Bedrock, no VPC endpoints):
- EC2: ~$12.60/month
- EBS (30GB): ~$2.40/month
- Data transfer: ~$1-5/month
- Bedrock: Pay-per-use (~$5-8/month for light usage with Nova Lite)
- **Total: ~$21-28/month**

**With VPC Endpoints** (production):
- Add ~$22/month for SSM + Bedrock endpoints
- **Total: ~$43-50/month**

## Security

- **No SSH**: SSM Session Manager only
- **No inbound ports**: Security group has no ingress rules
- **No secrets in Terraform state**: Gateway token generated at boot; OpenRouter key set via CLI
- **Encrypted storage**: EBS volumes encrypted by default
- **Secrets in SSM**: All tokens stored as SecureString parameters
- **Least-privilege IAM**: Scoped permissions for SSM and Bedrock
- **Loopback binding**: Gateway binds to 127.0.0.1 only, accessible via SSM port-forward
- **No insecure auth**: controlUi requires token authentication

## Documentation

- **[Runbook.md](Runbook.md)**: Complete operations guide (deploy, access, troubleshoot, update, Telegram setup)
- **[DIFF_SUMMARY.md](DIFF_SUMMARY.md)**: Detailed comparison with CloudFormation template

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured
- SSM Session Manager Plugin installed
- Amazon Bedrock model access enabled in your AWS account
- OpenRouter API key (only if using OpenRouter provider)

## License

MIT - See root repository LICENSE
