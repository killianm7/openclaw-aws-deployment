# OpenClaw Terraform Runbook

Complete operational guide for the OpenClaw Terraform deployment.

## Prerequisites

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.5.0 installed
3. **SSM Session Manager Plugin** installed for secure instance access
4. **Amazon Bedrock** model access enabled in your region (default provider)

## Quick Start

### 1. Configure Variables

```bash
cd openclaw-aws-deployment
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` if needed. The defaults use Bedrock with `amazon.nova-lite-v1:0` -- no API keys required.

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan Deployment

```bash
terraform plan
```

Review the plan carefully. It should show:
- 1 IAM role and instance profile
- 1 security group (egress only, no ingress)
- 1 EC2 instance (Ubuntu 24.04)
- 1 CloudWatch log group
- Optional: VPC endpoints (if enabled)

### 4. Apply Deployment

```bash
terraform apply
```

Type `yes` to confirm. Deployment takes ~8 minutes for the instance to be fully ready (Node.js + OpenClaw install).

## Post-Deployment: Access OpenClaw

### Step 1: Connect via SSM Session

```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)

# Connect to instance shell
aws ssm start-session --target $INSTANCE_ID --region $REGION
```

Once connected, switch to the ubuntu user:

```bash
sudo su - ubuntu
```

### Step 2: Port-Forward localhost:18789

In a **dedicated terminal** (keep it open):

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)

aws ssm start-session \
  --target $INSTANCE_ID \
  --region $REGION \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
```

You should see: `Waiting for connections...`

### Step 3: Retrieve the Gateway Token from SSM

In a **new terminal**:

```bash
# Option A: Use the Terraform output directly
eval $(terraform output -raw gateway_token_retrieval_command)

# Option B: Manual command
REGION=$(aws configure get region)
aws ssm get-parameter \
  --name "/openclaw/dev/gateway-token" \
  --with-decryption \
  --region $REGION \
  --query 'Parameter.Value' \
  --output text
```

### Step 4: Open the Web UI

Open your browser:

```
http://localhost:18789/?token=<TOKEN_FROM_STEP_3>
```

Replace `<TOKEN_FROM_STEP_3>` with the actual token value.

## Switching to OpenRouter Provider

### Step 1: Store the OpenRouter API Key in SSM

This is a one-time operation. The key is stored in SSM SecureString and **never** touches Terraform state.

```bash
REGION=$(aws configure get region)

aws ssm put-parameter \
  --name "/openclaw/dev/openrouter-api-key" \
  --type "SecureString" \
  --value "sk-or-v1-YOUR_ACTUAL_KEY_HERE" \
  --region $REGION
```

Get your key from: https://openrouter.ai/keys

### Step 2: Update Terraform Variables

Edit `terraform.tfvars`:

```hcl
model_provider           = "openrouter"
openrouter_ssm_parameter = "/openclaw/dev/openrouter-api-key"
```

### Step 3: Apply Changes

```bash
terraform apply
```

**Note**: This will recreate the EC2 instance (user_data changes). The new instance will retrieve the OpenRouter key from SSM at boot. If the key is not found, it will automatically fall back to Bedrock.

### Switching Back to Bedrock

Edit `terraform.tfvars`:

```hcl
model_provider           = "bedrock"
openrouter_ssm_parameter = ""
```

```bash
terraform apply
```

## Telegram Bot Setup

The Telegram plugin is pre-enabled during deployment. Follow these steps to configure it.

### Step 1: Create a Telegram Bot

1. Open Telegram and message [@BotFather](https://t.me/botfather)
2. Send `/newbot`
3. Choose a name (e.g., `My OpenClaw`)
4. Choose a username (e.g., `my_openclaw_bot`)
5. BotFather will reply with a token like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`

### Step 2: Store the Bot Token in SSM

```bash
REGION=$(aws configure get region)

aws ssm put-parameter \
  --name "/openclaw/dev/telegram-bot-token" \
  --type "SecureString" \
  --value "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" \
  --region $REGION
```

Replace the value with your actual bot token.

### Step 3: SSM into the Instance and Configure

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)

aws ssm start-session --target $INSTANCE_ID --region $REGION
```

Once connected:

```bash
# Switch to ubuntu user
sudo su - ubuntu

# Retrieve the bot token from SSM
TELEGRAM_TOKEN=$(aws ssm get-parameter \
  --name "/openclaw/dev/telegram-bot-token" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Edit the OpenClaw config to add Telegram channel
# Add a channels.telegram section to ~/.openclaw/openclaw.json:
cat ~/.openclaw/openclaw.json | jq '.channels.telegram = {
  "enabled": true,
  "botToken": "'"$TELEGRAM_TOKEN"'",
  "dmPolicy": "pairing",
  "groups": { "*": { "requireMention": true } }
}' > /tmp/openclaw-config.json && mv /tmp/openclaw-config.json ~/.openclaw/openclaw.json

# Restart OpenClaw to pick up the new config
systemctl --user restart openclaw
```

### Step 4: Verify Telegram is Working

```bash
# Check service status
systemctl --user status openclaw

# Watch logs for Telegram connection
journalctl --user -u openclaw -f
```

You should see Telegram connection messages in the logs.

### Step 5: Approve Your First DM

1. Send a message to your bot on Telegram
2. On the instance, run:

```bash
openclaw pairing list telegram
openclaw pairing approve telegram <CODE>
```

Pairing codes expire after 1 hour.

### Telegram Troubleshooting

```bash
# Check if Telegram plugin is enabled
openclaw plugins list

# Check channel status
openclaw channels status

# View Telegram-specific logs
journalctl --user -u openclaw --no-pager | grep -i telegram

# Test outbound connectivity to Telegram API
curl -s https://api.telegram.org/bot<TOKEN>/getMe
```

See also: [OpenClaw Telegram docs](https://docs.molt.bot/channels/telegram)

## Debug and Restart OpenClaw

### Check Service Status

```bash
# SSM into the instance first
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)
aws ssm start-session --target $INSTANCE_ID --region $REGION

# Switch to ubuntu user (required for user-level systemd)
sudo su - ubuntu

# Check service status
systemctl --user status openclaw

# View recent logs
journalctl --user -u openclaw --no-pager -n 50

# Follow logs in real-time
journalctl --user -u openclaw -f
```

### Restart OpenClaw

```bash
sudo su - ubuntu
systemctl --user restart openclaw
```

### Stop / Start

```bash
sudo su - ubuntu
systemctl --user stop openclaw
systemctl --user start openclaw
```

### From Root (without switching user)

```bash
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 systemctl --user status openclaw
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 journalctl --user -u openclaw --no-pager -n 50
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 systemctl --user restart openclaw
```

## Verify Setup Completion

```bash
# Check setup status
cat /home/ubuntu/.openclaw/setup_complete.txt

# View full setup log
cat /var/log/openclaw-setup.log

# Check if OpenClaw is listening
ss -tlnp | grep 18789
```

## Update OpenClaw

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)
aws ssm start-session --target $INSTANCE_ID --region $REGION

sudo su - ubuntu

# Update OpenClaw to latest version
npm install -g openclaw@latest

# Restart the service
systemctl --user restart openclaw

# Verify
systemctl --user status openclaw
```

## Managing Integration Secrets

### Store a Secret in SSM

```bash
REGION=$(aws configure get region)

aws ssm put-parameter \
  --name "/openclaw/dev/<secret-name>" \
  --type "SecureString" \
  --value "YOUR_SECRET_VALUE" \
  --region $REGION
```

### Retrieve a Secret from SSM

```bash
aws ssm get-parameter \
  --name "/openclaw/dev/<secret-name>" \
  --with-decryption \
  --region $REGION \
  --query 'Parameter.Value' \
  --output text
```

### Common Secrets

| Secret | SSM Path | Purpose |
|--------|----------|---------|
| Gateway Token | `/openclaw/dev/gateway-token` | Web UI auth (auto-generated) |
| OpenRouter Key | `/openclaw/dev/openrouter-api-key` | OpenRouter provider |
| Telegram Token | `/openclaw/dev/telegram-bot-token` | Telegram bot |
| Discord Token | `/openclaw/dev/discord-bot-token` | Discord bot |
| Slack Token | `/openclaw/dev/slack-bot-token` | Slack bot |

## Cost Optimization

### Current Costs (with defaults)

| Component | Cost | Notes |
|-----------|------|-------|
| EC2 t4g.small | ~$12.60/month | Cheapest option |
| EBS 30GB gp3 | ~$2.40/month | Root volume |
| Data Transfer | ~$1-5/month | Depends on usage |
| Bedrock | ~$5-8/month | Pay-per-use (Nova Lite) |
| **Total (no VPC endpoints)** | **~$21-28/month** | Default configuration |

### Optional: Enable VPC Endpoints (+$22/month)

For production or compliance requirements:

```hcl
# Edit terraform.tfvars
enable_vpc_endpoints = true
```

```bash
terraform apply
```

**Benefits**:
- Private network access (no internet for SSM/Bedrock)
- Compliance-friendly (HIPAA, SOC2)
- Lower latency

## Troubleshooting

### Instance Won't Start

```bash
# Check instance console logs
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(aws configure get region)
aws ec2 get-console-output --instance-id $INSTANCE_ID --region $REGION

# Check CloudWatch logs
aws logs tail /openclaw/dev/user-data --region $REGION
```

### OpenClaw Service Not Running

```bash
aws ssm start-session --target $INSTANCE_ID --region $REGION

sudo su - ubuntu

# Check service status
systemctl --user status openclaw

# Check if daemon was installed
systemctl --user list-unit-files | grep openclaw

# View logs
journalctl --user -u openclaw --no-pager -n 100

# Check setup log
cat /var/log/openclaw-setup.log | tail -100
```

### Can't Access Web UI

1. **Verify port forwarding is running**:
   ```bash
   # Should see "Waiting for connections..."
   # If not, restart the port forwarding command
   ```

2. **Check gateway token**:
   ```bash
   REGION=$(aws configure get region)
   aws ssm get-parameter \
     --name "/openclaw/dev/gateway-token" \
     --with-decryption \
     --region $REGION \
     --query 'Parameter.Value' \
     --output text
   ```

3. **Verify OpenClaw is listening**:
   ```bash
   aws ssm start-session --target $INSTANCE_ID --region $REGION
   ss -tlnp | grep 18789
   ```

### SSM Connection Issues

```bash
# Verify SSM agent is running on instance
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region $REGION

# Check IAM permissions
aws iam get-role --role-name openclaw-dev-role
```

### Model Provider Issues

**Bedrock not working**:
```bash
# Verify IAM role has Bedrock permissions
aws iam get-role-policy \
  --role-name openclaw-dev-role \
  --policy-name bedrock-access

# Test Bedrock access from instance
aws ssm start-session --target $INSTANCE_ID --region $REGION
aws bedrock-runtime invoke-model \
  --model-id amazon.nova-lite-v1:0 \
  --body '{"messages":[{"role":"user","content":[{"text":"Hello"}]}],"inferenceConfig":{"maxTokens":10}}' \
  --region $REGION \
  output.json && echo "Bedrock OK"
```

**OpenRouter not working**:
```bash
# Verify API key is stored in SSM
aws ssm get-parameter \
  --name "/openclaw/dev/openrouter-api-key" \
  --with-decryption \
  --region $REGION

# Check OpenClaw logs for API errors
aws ssm start-session --target $INSTANCE_ID --region $REGION
sudo su - ubuntu
journalctl --user -u openclaw --no-pager | grep -i error
```

## Cleanup / Destroy

**WARNING**: This will permanently delete all resources!

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy everything
terraform destroy

# Type 'yes' to confirm
```

**Note**: SSM parameters created by the instance (gateway token) are not managed by Terraform and must be cleaned up manually:

```bash
REGION=$(aws configure get region)
aws ssm delete-parameter --name "/openclaw/dev/gateway-token" --region $REGION
```

**Data preservation**: OpenClaw data is stored on the EBS volume. The destroy command will delete this. To preserve data:
1. Create an AMI snapshot before destroying
2. Or backup `/home/ubuntu/.openclaw/` from the instance

## Architecture Notes

### SSM-Only Access (No SSH)

This deployment uses **no SSH keys** and **no port 22 ingress**. Access is exclusively via AWS Systems Manager Session Manager:

- **Benefits**: No SSH key management, audit logging, no open ports
- **Requirements**: IAM permissions for SSM, SSM agent pre-installed (Ubuntu 24.04 has it)

### Default VPC Usage

Using AWS Default VPC instead of custom VPC:
- **Pros**: Zero cost, no NAT Gateway needed, faster deployment, SSM works over internet
- **Cons**: Less network isolation, shares VPC with other default VPC resources
- **When to use custom VPC**: Compliance requirements, multi-tier applications, complex networking

### Native Host Install

This deployment installs Node.js + OpenClaw directly on the host (no Docker):
- **Pros**: Simpler, lower resource overhead, faster startup, matches upstream aws-samples pattern
- **Cons**: Dependencies installed on host (managed by NVM)
- **Service management**: systemd user service via `openclaw daemon install`
- **Updates**: `npm install -g openclaw@latest && systemctl --user restart openclaw`

### Gateway Token Lifecycle

The gateway token is generated at boot by the instance and stored in SSM SecureString. It is **not** managed by Terraform. This means:
- Token never appears in Terraform state
- Token is regenerated on instance replacement (e.g., `terraform apply` with user_data changes)
- After instance replacement, retrieve the new token from SSM

## Security Considerations

1. **No SSH access**: Only SSM Session Manager
2. **Security group**: No inbound rules, only HTTPS/HTTP/DNS/NTP egress
3. **No secrets in Terraform state**: Gateway token and API keys managed outside Terraform
4. **Encryption**: EBS volumes encrypted by default
5. **IAM**: Bedrock + SSM permissions always present (least-privilege within scope)
6. **Gateway binding**: Loopback only (127.0.0.1:18789) -- requires SSM port-forward
7. **Token auth**: controlUi requires token, `allowInsecureAuth: false`

## Support

- **OpenClaw Issues**: https://github.com/openclaw/openclaw/issues
- **OpenClaw Docs**: https://docs.molt.bot/
- **AWS SSM**: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- **OpenRouter**: https://openrouter.ai/docs
- **Bedrock**: https://docs.aws.amazon.com/bedrock/
