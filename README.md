# OpenClaw AWS Deployment

Secure, low-cost OpenClaw deployment on AWS using Docker, Terraform, and API Gateway.

## 📁 Project Structure

```
openclaw-aws-deployment/
├── terraform/
│   ├── main.tf              # Main Terraform configuration
│   └── scripts/
│       └── bootstrap.sh     # EC2 user-data bootstrap script
├── lambda/
│   └── webhook_handler.py   # Lambda function for webhook forwarding
├── config/
│   ├── docker-compose.yml   # Docker Compose for OpenClaw
│   └── openclaw.json        # OpenClaw configuration template
└── RUNBOOK.md               # Complete deployment and operations guide
```

## 🚀 Quick Start

1. **Prerequisites**
   ```bash
   # Install Terraform and AWS CLI
   brew install terraform awscli  # macOS
   # or
   sudo apt-get install terraform awscli  # Ubuntu
   ```

2. **Configure Variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

3. **Deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Configure Telegram Bot**
   - Message @BotFather on Telegram
   - Create new bot and save token
   - Update SSM parameter with token
   - Set webhook URL (from terraform output)

See [RUNBOOK.md](RUNBOOK.md) for detailed instructions.

## 🔐 Security Features

- **No Public Ports**: OpenClaw bound to localhost only
- **VPC Isolation**: Lambda → EC2 via internal network
- **IP-Restricted SSH**: Your IP only
- **Encrypted Secrets**: AWS SSM Parameter Store
- **Audit Logging**: CloudWatch Logs
- **Sandboxed Execution**: Docker container isolation

## 💰 Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| EC2 (t3.micro) | ~$8.50 |
| EIP | ~$3.65 |
| API Gateway | ~$3.50 |
| Lambda | ~$0.20 |
| CloudWatch | ~$2.00 |
| **Total** | **~$18-25** |

## 📚 Documentation

- [Complete Runbook](RUNBOOK.md) - Deployment, configuration, and operations
- [OpenClaw Docs](https://docs.openclaw.ai) - Official OpenClaw documentation

## 🔧 Architecture

```
Internet → API Gateway → Lambda → VPC → EC2 → Docker → OpenClaw
                                             ↓
                                         CloudWatch Logs
                                             ↓
                                         SSM Parameters
```

## 📝 License

MIT - See LICENSE file for details
