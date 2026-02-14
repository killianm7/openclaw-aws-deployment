# OpenClaw AWS Deployment - Complete Runbook

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Deployment Steps](#deployment-steps)
5. [Configuration](#configuration)
6. [Testing](#testing)
7. [Operations](#operations)
8. [Adding More Apps](#adding-more-apps)
9. [Troubleshooting](#troubleshooting)
10. [Security Checklist](#security-checklist)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    │ HTTPS Webhooks
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS API Gateway                               │
│              (Public HTTPS endpoint)                             │
│         /webhook/telegram, /webhook/whatsapp                     │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    │ Lambda Invoke
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              Lambda Function (VPC)                               │
│         Forwards webhooks to OpenClaw                            │
│         - Receives external webhooks                             │
│         - Authenticates requests                                 │
│         - Proxies to EC2 via internal network                    │
└───────────────────┬─────────────────────────────────────────────┘
                    │ HTTP (internal VPC only)
                    │ Port 18789
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              EC2 Instance (t3.micro/small)                       │
│              Public Subnet (cost optimization)                   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Docker Host                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────────────────┐ │   │
│  │  │ OpenClaw        │    │ Ollama (optional)           │ │   │
│  │  │ Gateway         │    │ Local LLM inference         │ │   │
│  │  │ - Port 18789    │    │ - Port 11434 (internal)     │ │   │
│  │  │ - Binds to      │    │                             │ │   │
│  │  │   127.0.0.1     │    │                             │ │   │
│  │  │   (localhost)   │    │                             │ │   │
│  │  └─────────────────┘    └─────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Security Groups:                                                │
│  - SSH (22): YOUR_IP_ONLY                                        │
│  - OpenClaw (18789): Lambda SG only (no public access)          │
│  - Outbound: All (for API calls, model access)                   │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Services                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ SSM Params  │  │ CloudWatch  │  │ CloudWatch Logs         │  │
│  │ - API keys  │  │ - Metrics   │  │ - Application logs      │  │
│  │ - Tokens    │  │ - Alarms    │  │ - System logs           │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Security Features
- **No Public Ports**: OpenClaw gateway binds to localhost only
- **Private Access**: Only Lambda can reach OpenClaw via VPC networking
- **IP-Restricted SSH**: SSH access limited to your IP only
- **Encrypted Secrets**: All API keys stored in AWS SSM Parameter Store
- **Audit Logging**: CloudWatch logs for all operations
- **Sandboxed Execution**: Tools run in Docker containers

---

## Prerequisites

### AWS Requirements
- AWS Account with appropriate permissions
- AWS CLI installed and configured
- Terraform >= 1.5.0 installed
- EC2 Key Pair created in your target region

### Local Requirements
```bash
# macOS
brew install awscli terraform

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y awscli terraform

# Verify installations
aws --version
terraform --version
```

### Knowledge Requirements
- Basic understanding of AWS (VPC, EC2, IAM)
- Familiarity with Docker and Docker Compose
- Understanding of Telegram Bot API (for bot setup)

---

## Initial Setup

### 1. Get Your Public IP Address

```bash
# Get your current public IP
curl -s https://api.ipify.org

# Or use
curl -s https://ifconfig.me

# Note this down - you'll need it for SSH security group
```

### 2. Generate SSH Key Pair (if needed)

```bash
# Generate a new key pair (if you don't have one)
ssh-keygen -t ed25519 -C "openclaw-aws" -f ~/.ssh/openclaw-aws

# Or import existing public key to AWS
aws ec2 import-key-pair \
    --key-name openclaw-aws \
    --public-key-material fileb://~/.ssh/openclaw-aws.pub \
    --region us-east-1
```

### 3. Clone/Download Deployment Files

```bash
# Create working directory
mkdir -p ~/openclaw-deployment
cd ~/openclaw-deployment

# Copy all files from this deployment package
cp -r /path/to/openclaw-aws-deployment/* .
```

---

## Deployment Steps

### Step 1: Configure Terraform Variables

Create a `terraform.tfvars` file:

```hcl
# terraform/terraform.tfvars

# AWS Configuration
aws_region = "us-east-1"
environment = "production"

# IMPORTANT: Replace with your actual IP!
# Get your IP: curl -s https://api.ipify.org
# Format: "x.x.x.x/32"
ssh_allowed_cidr = "YOUR.IP.ADDRESS.HERE/32"

# EC2 Configuration
key_name       = "openclaw-aws"  # Your EC2 key pair name
instance_type  = "t3.micro"      # t3.micro (free tier) or t3.small (recommended)

# Optional: Pre-configure tokens
# If left empty, tokens will be auto-generated
openclaw_gateway_token = ""
telegram_bot_token     = ""  # We'll configure this later
```

### Step 2: Initialize Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# View the execution plan
terraform plan
```

### Step 3: Deploy Infrastructure

```bash
# Deploy everything (takes ~5-10 minutes)
terraform apply

# Confirm with 'yes' when prompted
```

### Step 4: Save Deployment Outputs

After successful deployment, save these outputs:

```bash
# Get all outputs
terraform output

# Save to file for reference
terraform output > deployment-info.txt

# Get specific values
terraform output ec2_public_ip
terraform output api_gateway_url
terraform output telegram_webhook_url
terraform output -raw openclaw_gateway_token  # Save this securely!
```

**CRITICAL**: Save the gateway token securely - you'll need it for Lambda and any direct API calls.

---

## Configuration

### Step 5: Configure SSM Parameters

Even if you didn't set tokens in terraform.tfvars, you should configure SSM parameters:

```bash
# Set your OpenClaw gateway token (if auto-generated, get it from terraform output)
aws ssm put-parameter \
    --name "/openclaw/gateway/token" \
    --type "SecureString" \
    --value "your-gateway-token-here" \
    --overwrite \
    --region us-east-1

# This will be used when we configure Telegram
aws ssm put-parameter \
    --name "/openclaw/channels/telegram/token" \
    --type "SecureString" \
    --value "placeholder" \
    --overwrite \
    --region us-east-1
```

### Step 6: Connect to EC2 Instance

```bash
# Use the SSH command from terraform output
ssh -i ~/.ssh/openclaw-aws.pem ec2-user@YOUR_EC2_PUBLIC_IP

# Or get it dynamically
ssh -i ~/.ssh/openclaw-aws.pem ec2-user@$(cd terraform && terraform output -raw ec2_public_ip)
```

### Step 7: Verify OpenClaw Installation

Once connected to EC2:

```bash
# Check if bootstrap completed
sudo tail -n 50 /var/log/openclaw-bootstrap.log

# Check Docker status
sudo docker ps

# Check if OpenClaw config exists
ls -la /opt/openclaw/config/

# View OpenClaw configuration
cat /opt/openclaw/config/openclaw.json
```

### Step 8: Start OpenClaw

```bash
# Option 1: Using systemd service
sudo systemctl start openclaw
sudo systemctl status openclaw

# Option 2: Manual start
cd /opt/openclaw
sudo docker-compose up -d

# View logs
sudo docker-compose logs -f

# Or follow CloudWatch logs
aws logs tail /openclaw/application --follow --region us-east-1
```

### Step 9: Test OpenClaw Health

```bash
# From the EC2 instance, test OpenClaw is running
curl http://localhost:18789/health

# Should return: {"status":"ok"} or similar
```

---

## Testing

### Test 1: Lambda to OpenClaw Connectivity

```bash
# Invoke Lambda function to test connectivity
aws lambda invoke \
    --function-name openclaw-webhook-handler \
    --payload '{}' \
    --region us-east-1 \
    response.json

cat response.json
```

### Test 2: API Gateway Endpoint

```bash
# Get your API Gateway URL
API_URL=$(cd terraform && terraform output -raw api_gateway_url)

# Test with curl
curl -X POST "${API_URL}/webhook/telegram" \
    -H "Content-Type: application/json" \
    -d '{"test": true}'

# Should return: {"ok": true}
```

### Test 3: Configure Telegram Bot (Full Integration)

#### 3.1 Create Telegram Bot

1. Open Telegram app
2. Search for **@BotFather**
3. Start a conversation
4. Send: `/newbot`
5. Follow prompts:
   - Bot name: "My OpenClaw Assistant"
   - Bot username: Must end in `bot` (e.g., `myopenclaw_bot`)
6. **Save the token** BotFather gives you

#### 3.2 Update SSM with Telegram Token

```bash
aws ssm put-parameter \
    --name "/openclaw/channels/telegram/token" \
    --type "SecureString" \
    --value "YOUR_BOT_TOKEN_HERE" \
    --overwrite \
    --region us-east-1
```

#### 3.3 Update OpenClaw Config

SSH to your EC2 instance:

```bash
# Edit the config file
sudo nano /opt/openclaw/config/openclaw.json
```

Update the Telegram section:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "mode": "webhook",
      "token": "YOUR_BOT_TOKEN",
      "webhook": {
        "url": "YOUR_API_GATEWAY_URL/webhook/telegram"
      }
    }
  }
}
```

#### 3.4 Restart OpenClaw

```bash
sudo docker-compose -f /opt/openclaw/docker-compose.yml restart
```

#### 3.5 Set Telegram Webhook

```bash
# Get your webhook URL
WEBHOOK_URL=$(cd terraform && terraform output -raw telegram_webhook_url)

# Set webhook with Telegram
curl -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook" \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"${WEBHOOK_URL}\"}"

# Verify webhook is set
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/getWebhookInfo"
```

#### 3.6 Send Test Message

1. Open Telegram
2. Search for your bot (e.g., @myopenclaw_bot)
3. Send: `/start` or "Hello!"
4. Check logs on EC2: `sudo docker-compose logs -f`

---

## Operations

### Daily Operations

```bash
# SSH to instance
ssh -i ~/.ssh/openclaw-aws.pem ec2-user@YOUR_IP

# View OpenClaw logs
sudo docker-compose -f /opt/openclaw/docker-compose.yml logs -f

# Check OpenClaw status
sudo docker-compose -f /opt/openclaw/docker-compose.yml ps

# Check system resources
free -h
df -h
top

# View CloudWatch logs locally
aws logs tail /openclaw/application --follow --region us-east-1
```

### Updating OpenClaw

```bash
# SSH to instance
ssh -i ~/.ssh/openclaw-aws.pem ec2-user@YOUR_IP

# Pull latest image
cd /opt/openclaw
sudo docker-compose pull

# Restart with new image
sudo docker-compose up -d

# Verify
sudo docker-compose ps
```

### Backup and Restore

```bash
# Backup data directory
sudo tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz /opt/openclaw/data /opt/openclaw/config

# Download backup
scp -i ~/.ssh/openclaw-aws.pem ec2-user@YOUR_IP:openclaw-backup-*.tar.gz .

# Restore (on new instance)
# 1. Deploy new infrastructure
# 2. SCP backup to new instance
# 3. Extract: sudo tar -xzf openclaw-backup-*.tar.gz -C /
```

### Monitoring and Alerts

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace OpenClaw \
    --metric-name mem_used_percent \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Average \
    --region us-east-1

# Set up alarm for high CPU
aws cloudwatch put-metric-alarm \
    --alarm-name openclaw-high-cpu \
    --alarm-description "CPU usage > 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value=YOUR_INSTANCE_ID \
    --evaluation-periods 2 \
    --region us-east-1
```

---

## Adding More Apps

### Adding WhatsApp Support

#### Step 1: Choose WhatsApp Provider

Options:
- **Twilio** (easiest, paid)
- **WhatsApp Business API** (official, requires Meta approval)
- **WhatsApp Web API** (unofficial, may violate ToS)

#### Step 2: Configure Lambda for WhatsApp

Update `lambda/webhook_handler.py`:

```python
def handle_whatsapp_webhook(event):
    # Parse Twilio/WhatsApp format
    body = parse_qs(event.get('body', ''))
    
    message_data = {
        'from': body.get('From', [''])[0],
        'body': body.get('Body', [''])[0],
        'media_url': body.get('MediaUrl0', [''])[0]
    }
    
    return forward_to_openclaw(message_data, 'whatsapp')
```

#### Step 3: Add API Gateway Endpoint

Update `terraform/main.tf`:

```hcl
resource "aws_api_gateway_resource" "whatsapp" {
  rest_api_id = aws_api_gateway_rest_api.openclaw.id
  parent_id   = aws_api_gateway_resource.webhook.id
  path_part   = "whatsapp"
}

resource "aws_api_gateway_method" "whatsapp_post" {
  rest_api_id   = aws_api_gateway_rest_api.openclaw.id
  resource_id   = aws_api_gateway_resource.whatsapp.id
  http_method   = "POST"
  authorization = "NONE"
}
```

#### Step 4: Update OpenClaw Config

```bash
# On EC2
sudo nano /opt/openclaw/config/openclaw.json
```

Enable WhatsApp:

```json
{
  "channels": {
    "whatsapp": {
      "enabled": true,
      "mode": "webhook",
      "webhook": {
        "url": "YOUR_API_GATEWAY_URL/webhook/whatsapp"
      },
      "dmPolicy": "pairing"
    }
  }
}
```

#### Step 5: Redeploy

```bash
cd terraform
terraform apply

# On EC2
sudo docker-compose restart
```

### Adding Slack Support

Similar process:
1. Create Slack app at https://api.slack.com/apps
2. Configure Event Subscriptions pointing to your API Gateway
3. Add `/webhook/slack` endpoint
4. Update OpenClaw config

### Adding Discord Support

1. Create Discord bot at https://discord.com/developers/applications
2. Configure webhook/interactions URL
3. Add `/webhook/discord` endpoint
4. Update OpenClaw config

---

## Configuring Claude/Anthropic (Paid Models)

### Step 1: Get API Key

1. Go to https://console.anthropic.com/
2. Create an account
3. Generate an API key
4. Add payment method

### Step 2: Store in SSM

```bash
aws ssm put-parameter \
    --name "/openclaw/providers/anthropic/api_key" \
    --type "SecureString" \
    --value "sk-ant-api03-..." \
    --region us-east-1
```

### Step 3: Update OpenClaw Config

```bash
# SSH to EC2
sudo nano /opt/openclaw/config/openclaw.json
```

Update the model section:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "provider": "anthropic",
        "model": "claude-3-5-sonnet-20241022",
        "apiKey": "${ANTHROPIC_API_KEY}",
        "temperature": 0.7,
        "maxTokens": 4096
      }
    }
  }
}
```

### Step 4: Pass API Key to Container

Update `docker-compose.yml`:

```yaml
services:
  openclaw:
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

Or fetch from SSM in bootstrap script:

```bash
# Add to bootstrap.sh
ANTHROPIC_API_KEY=$(aws ssm get-parameter --name "/openclaw/providers/anthropic/api_key" --with-decryption --query Parameter.Value --output text --region $AWS_REGION)
```

### Step 5: Restart

```bash
sudo docker-compose restart
```

---

## Troubleshooting

### Issue: Cannot SSH to EC2

```bash
# Check security group allows your IP
aws ec2 describe-security-groups \
    --group-ids YOUR_SG_ID \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# Update security group with correct IP
MY_IP=$(curl -s https://api.ipify.org)
aws ec2 authorize-security-group-ingress \
    --group-id YOUR_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr "${MY_IP}/32"
```

### Issue: OpenClaw Not Starting

```bash
# Check logs
sudo docker-compose logs --tail=100 openclaw

# Check if port is in use
sudo netstat -tlnp | grep 18789

# Check Docker status
sudo systemctl status docker

# Reset and restart
sudo docker-compose down
sudo docker-compose up -d
```

### Issue: Lambda Cannot Connect to OpenClaw

```bash
# Test from Lambda VPC
# 1. Create test Lambda in same VPC
# 2. Test connectivity:

import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
result = sock.connect_ex(('OPENCLAW_PRIVATE_IP', 18789))
print(result)  # 0 = success
```

### Issue: Telegram Webhook Not Working

```bash
# Verify webhook URL
curl "https://api.telegram.org/botYOUR_TOKEN/getWebhookInfo"

# Check API Gateway logs
aws logs tail /aws/apigateway/openclaw-webhook-api --region us-east-1

# Test API Gateway directly
curl -X POST "${API_URL}/webhook/telegram" \
    -d '{"message": {"text": "test"}}'

# Check Lambda logs
aws logs tail /aws/lambda/openclaw-webhook-handler --region us-east-1
```

### Issue: High Memory Usage

```bash
# Monitor memory
free -h

# Check container stats
sudo docker stats --no-stream

# Scale up instance type
cd terraform
# Edit terraform.tfvars: instance_type = "t3.small"
terraform apply
```

---

## Security Checklist

Before going to production, verify:

- [ ] SSH access restricted to your IP only (`ssh_allowed_cidr`)
- [ ] OpenClaw gateway token is strong (64+ characters)
- [ ] All API keys stored in SSM Parameter Store (SecureString)
- [ ] CloudWatch logging enabled
- [ ] OpenClaw binds to localhost (127.0.0.1:18789) only
- [ ] No public ingress on port 18789
- [ ] Docker images use specific versions (not `:latest` in production)
- [ ] Regular backups configured
- [ ] MFA enabled on AWS account
- [ ] EC2 instance has instance profile (not hardcoded credentials)
- [ ] Telegram bot privacy mode enabled
- [ ] DM policy set to "pairing" or "allowlist"
- [ ] Sandbox mode enabled for tools
- [ ] Sensitive data redacted from logs

---

## Cost Optimization

### Current Monthly Estimate (us-east-1)

| Service | Configuration | Monthly Cost |
|---------|----------------|--------------|
| EC2 | t3.micro | ~$8.50 |
| EIP | 1 address | ~$3.65 |
| Data Transfer | ~10GB | ~$0.90 |
| API Gateway | 1M requests | ~$3.50 |
| Lambda | 1M invocations | ~$0.20 |
| CloudWatch | Logs + Metrics | ~$2.00 |
| SSM | Parameters | ~$0.05 |
| **Total** | | **~$18-25/month** |

### Cost Saving Tips

1. **Use t3.micro** (free tier eligible for 12 months)
2. **Spot instances** for non-critical workloads (up to 90% savings)
3. **Schedule start/stop** using Lambda + CloudWatch Events
4. **Reserved instances** for long-term commitment (up to 40% savings)
5. **Monitor with CloudWatch Alarms** to catch unexpected usage

```bash
# Stop instance when not needed
aws ec2 stop-instances --instance-ids YOUR_INSTANCE_ID

# Start when needed
aws ec2 start-instances --instance-ids YOUR_INSTANCE_ID
```

---

## Next Steps

1. ✅ Deploy infrastructure with Terraform
2. ✅ Configure Telegram bot
3. ✅ Test basic functionality
4. ⬜ Configure Anthropic Claude API (optional)
5. ⬜ Set up custom skills
6. ⬜ Add monitoring/alerting
7. ⬜ Document custom workflows
8. ⬜ Set up CI/CD for config updates
9. ⬜ Add WhatsApp support (when ready)
10. ⬜ Configure backup automation

---

## Getting Help

- **OpenClaw Documentation**: https://docs.openclaw.ai
- **GitHub Issues**: https://github.com/openclaw/openclaw
- **Community Discord**: Check OpenClaw GitHub for invite link
- **AWS Support**: AWS Free Tier includes basic support

---

## Quick Reference

```bash
# SSH to instance
ssh -i ~/.ssh/openclaw-aws.pem ec2-user@$(terraform output -raw ec2_public_ip)

# View logs
sudo docker-compose -f /opt/openclaw/docker-compose.yml logs -f

# Restart OpenClaw
sudo docker-compose -f /opt/openclaw/docker-compose.yml restart

# Update config
sudo nano /opt/openclaw/config/openclaw.json
sudo docker-compose restart

# Check health
curl http://localhost:18789/health

# API Gateway URL
terraform output api_gateway_url

# Telegram webhook URL
terraform output telegram_webhook_url
```

---

**Deployment Complete!** 🎉

Your OpenClaw instance is now running securely on AWS. Start chatting with your bot on Telegram!
