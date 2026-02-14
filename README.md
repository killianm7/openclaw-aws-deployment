# OpenClaw Terraform Deployment

Terraform infrastructure-as-code deployment for [OpenClaw](https://github.com/openclaw/openclaw) on AWS EC2 using Docker Compose.

## Features

- **SSM-Only Access**: No SSH keys, no port 22 - pure AWS Systems Manager Session Manager
- **Cost-Optimized**: Defaults to cheapest instance (t4g.small ~$13/month), VPC endpoints optional
- **Flexible Model Provider**: OpenRouter (default) or AWS Bedrock
- **Ubuntu 24.04 LTS**: Production-ready OS with long-term support
- **Docker Deployment**: Clean container management with Docker Compose
- **Default VPC**: Zero additional networking costs, no NAT Gateway needed

## Quick Start

```bash
cd terraform-openclaw

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OpenRouter API key

# 2. Deploy
terraform init
terraform plan
terraform apply

# 3. Access
# Port forward (keep terminal open)
aws ssm start-session \
  --target $(terraform output -raw instance_id) \
  --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

# Get token (new terminal)
terraform output gateway_token_ssm_path
aws ssm get-parameter --name <path> --with-decryption --query 'Parameter.Value' --output text

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
│  │  Docker      │── Docker ────▶ OpenClaw           │
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

# Model provider
model_provider = "openrouter"  # or "bedrock"
openrouter_api_key = "sk-or-v1-..."

# Optional VPC endpoints (+$22/month)
enable_vpc_endpoints = false
```

## Project Structure

```
terraform-openclaw/
├── main.tf                      # Root orchestration
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values
├── versions.tf                  # Provider constraints
├── terraform.tfvars.example     # Example configuration
├── docker-compose.yml           # OpenClaw container config
├── Runbook.md                   # Complete operational guide
├── DIFF_SUMMARY.md              # Changes from CloudFormation
├── modules/
│   ├── iam/                     # IAM role & instance profile
│   ├── network/                 # Security group (SSM-only)
│   ├── ec2/                     # EC2 instance & user_data
│   └── vpc_endpoints/           # Optional VPC endpoints
└── files/
    └── user_data.sh.tpl         # Ubuntu setup script
```

## Cost Estimate

**Default Configuration** (t4g.small, no VPC endpoints):
- EC2: ~$12.60/month
- EBS (30GB): ~$2.40/month
- Data transfer: ~$1-5/month
- **Total: ~$16-20/month**

**With VPC Endpoints** (production):
- Add ~$22/month for SSM + Bedrock endpoints
- **Total: ~$38-42/month**

## Security

- **No SSH**: SSM Session Manager only
- **No inbound ports**: Security group has no ingress rules
- **Encrypted storage**: EBS volumes encrypted by default
- **Secrets in SSM**: API keys and tokens in SecureString parameters
- **Least-privilege IAM**: Scoped permissions, no wildcards

## Documentation

- **[Runbook.md](Runbook.md)**: Complete operations guide (deploy, access, troubleshoot, update)
- **[DIFF_SUMMARY.md](DIFF_SUMMARY.md)**: Detailed comparison with CloudFormation template

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured
- SSM Session Manager Plugin installed
- OpenRouter API key (if using OpenRouter)

## License

MIT - See root repository LICENSE
