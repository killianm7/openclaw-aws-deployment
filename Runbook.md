# OpenClaw Terraform Runbook

Complete operational guide for the OpenClaw Terraform deployment.

## Prerequisites

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.5.0 installed
3. **SSM Session Manager Plugin** installed for secure instance access

## Quick Start

### 1. Configure Variables

```bash
cd terraform-openclaw
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
- Set `openrouter_api_key` (get from https://openrouter.ai/keys)
- Adjust `instance_type` if needed (default: t4g.small is cheapest)
- Set `aws_region` to your preferred region

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
- 2 SSM parameters (secure strings)
- Optional: VPC endpoints (if enabled)

### 4. Apply Deployment

```bash
terraform apply
```

Type `yes` to confirm. Deployment takes ~5-8 minutes for the instance to be ready.

## Post-Deployment: Verify and Access

### Step 1: Verify Instance Status

```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw instance_id)

# Check instance status
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name'

# Should return: "running"
```

### Step 2: Verify Setup Completion

```bash
# Connect to instance via SSM
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Check setup status
sudo cat /opt/openclaw/setup_complete.txt

# View setup logs
sudo cat /var/log/openclaw-setup.log | tail -50

# Check if OpenClaw container is running
sudo docker ps

# View OpenClaw logs
sudo docker logs openclaw --tail 50

# Exit SSM session
exit
```

**Expected output**: Should see "SUCCESS" in setup_complete.txt and openclaw container running.

### Step 3: Access OpenClaw Web UI

```bash
# Start port forwarding (keep this terminal open)
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

# Expected output: "Waiting for connections..."
```

In a **new terminal window**, get the gateway token:

```bash
# Retrieve gateway token from SSM
GATEWAY_TOKEN=$(aws ssm get-parameter \
  --name "/openclaw/dev/gateway-token" \
  --with-decryption \
  --region us-west-2 \
  --query 'Parameter.Value' \
  --output text)

echo "Gateway Token: $GATEWAY_TOKEN"
```

Open your browser:
```
http://localhost:18789/?token=<GATEWAY_TOKEN>
```

Replace `<GATEWAY_TOKEN>` with the token from the command above.

## Managing Integration Secrets

### Telegram Bot Token

```bash
# Store Telegram bot token in SSM
aws ssm put-parameter \
  --name "/openclaw/dev/telegram-bot-token" \
  --type "SecureString" \
  --value "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" \
  --region us-west-2

# Instance will automatically pick this up (restart container if needed)
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo docker restart openclaw
```

### Discord Bot Token

```bash
aws ssm put-parameter \
  --name "/openclaw/dev/discord-bot-token" \
  --type "SecureString" \
  --value "YOUR_DISCORD_BOT_TOKEN" \
  --region us-west-2
```

### Slack Bot Token

```bash
aws ssm put-parameter \
  --name "/openclaw/dev/slack-bot-token" \
  --type "SecureString" \
  --value "xoxb-YOUR-SLACK-TOKEN" \
  --region us-west-2
```

### WhatsApp Session

```bash
aws ssm put-parameter \
  --name "/openclaw/dev/whatsapp-session" \
  --type "SecureString" \
  --value "YOUR_WHATSAPP_SESSION_DATA" \
  --region us-west-2
```

## Common Operations

### Connect to Instance Shell

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Switch to ubuntu user
sudo su - ubuntu

# View OpenClaw files
cd /opt/openclaw
cat ACCESS.txt
cat docker-compose.yml
cat gateway_token.txt
```

### Restart OpenClaw

```bash
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo systemctl restart openclaw
# OR
sudo docker restart openclaw
```

### View Logs

```bash
# Real-time logs
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo docker logs -f openclaw

# User data (setup) logs
sudo cat /var/log/openclaw-setup.log

# CloudWatch Logs
aws logs tail /openclaw/dev/user-data --region us-west-2 --follow
```

### Update OpenClaw

```bash
aws ssm start-session --target $INSTANCE_ID --region us-west-2

cd /opt/openclaw

# Pull latest image
sudo docker-compose pull

# Restart with new image
sudo docker-compose down
sudo docker-compose up -d

# Verify
sudo docker ps
```

### Change Model Provider

Edit `terraform.tfvars`:
```hcl
# From OpenRouter to Bedrock
model_provider = "bedrock"
bedrock_model_id = "amazon.nova-lite-v1:0"
```

Apply changes:
```bash
terraform apply
```

**Note**: Changing model provider will recreate the IAM role (to add/remove Bedrock permissions) and update the instance user_data. The instance may be recreated if necessary.

## Cost Optimization

### Current Costs (with defaults)

| Component | Cost | Notes |
|-----------|------|-------|
| EC2 t4g.small | ~$12.60/month | Cheapest option |
| EBS 30GB gp3 | ~$2.40/month | Root volume |
| Data Transfer | ~$1-5/month | Depends on usage |
| **Total (no VPC endpoints)** | **~$16-20/month** | Default configuration |

### Optional: Enable VPC Endpoints (+$22/month)

For production or compliance requirements:

```bash
# Edit terraform.tfvars
enable_vpc_endpoints = true

# Apply
terraform apply
```

**Benefits**:
- Private network access (no internet for SSM/Bedrock)
- Compliance-friendly (HIPAA, SOC2)
- Lower latency

### Reducing Costs Further

1. **Use Spot Instances** (not implemented here, but possible):
   - ~70% cheaper than on-demand
   - Instance can be interrupted

2. **Smaller EBS volume**:
   ```hcl
   root_volume_size = 20  # Minimum recommended
   ```

3. **Enable S3 VPC endpoint** for logs (if using VPC endpoints):
   - Reduces data transfer costs

## Troubleshooting

### Instance Won't Start

```bash
# Check instance console logs
aws ec2 get-console-output --instance-id $INSTANCE_ID --region us-west-2

# Check CloudWatch logs
aws logs tail /openclaw/dev/user-data --region us-west-2
```

### OpenClaw Container Not Running

```bash
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Check Docker status
sudo systemctl status docker

# Check OpenClaw service
sudo systemctl status openclaw

# View logs
sudo docker logs openclaw

# Check setup completion
sudo cat /opt/openclaw/setup_complete.txt
sudo cat /var/log/openclaw-setup.log | tail -100
```

### Can't Access Web UI

1. **Verify port forwarding is running**:
   ```bash
   # Should see "Waiting for connections..."
   # If not, restart the port forwarding command
   ```

2. **Check gateway token**:
   ```bash
   aws ssm get-parameter \
     --name "/openclaw/dev/gateway-token" \
     --with-decryption \
     --region us-west-2 \
     --query 'Parameter.Value' \
     --output text
   ```

3. **Verify OpenClaw is listening**:
   ```bash
   aws ssm start-session --target $INSTANCE_ID --region us-west-2
   sudo docker ps
   sudo netstat -tlnp | grep 18789
   ```

### SSM Connection Issues

```bash
# Verify SSM agent is running on instance
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region us-west-2

# Check IAM permissions
aws iam get-role --role-name openclaw-dev-role
```

### Model Provider Issues

**OpenRouter not working**:
```bash
# Verify API key is set
aws ssm get-parameter \
  --name "/openclaw/dev/openrouter-api-key" \
  --with-decryption \
  --region us-west-2

# Check OpenClaw logs for API errors
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo docker logs openclaw | grep -i error
```

**Bedrock not working**:
```bash
# Verify IAM role has Bedrock permissions
aws iam get-role-policy \
  --role-name openclaw-dev-role \
  --policy-name bedrock-access

# Test Bedrock access from instance
aws ssm start-session --target $INSTANCE_ID --region us-west-2
aws bedrock-runtime invoke-model \
  --model-id amazon.nova-lite-v1:0 \
  --body '{"messages":[{"role":"user","content":[{"text":"Hello"}]}],"inferenceConfig":{"maxTokens":10}}' \
  --region us-west-2 \
  output.json && echo "Bedrock OK"
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

**Data preservation**: OpenClaw data is stored in the EBS volume. The destroy command will delete this. To preserve data:
1. Create an AMI snapshot before destroying
2. Or backup `/opt/openclaw/data` from the instance

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

### Docker vs Native Install

This deployment uses Docker Compose instead of native Node.js installation:
- **Pros**: Cleaner deployment, easier updates, proper restart policies, isolated dependencies
- **Cons**: Slightly more resource overhead (~100MB RAM)

## Security Considerations

1. **No SSH access**: Only SSM Session Manager
2. **Security group**: No inbound rules, only HTTPS/HTTP/DNS egress
3. **Secrets**: Stored in SSM Parameter Store (SecureString), never in code
4. **Encryption**: EBS volumes encrypted by default
5. **IAM**: Least-privilege access, Bedrock permissions only if needed
6. **Gateway token**: Auto-generated, stored in SSM, never logged

## Support

- **OpenClaw Issues**: https://github.com/openclaw/openclaw/issues
- **AWS SSM**: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- **OpenRouter**: https://openrouter.ai/docs
- **Bedrock**: https://docs.aws.amazon.com/bedrock/
