# CloudFormation to Terraform - Diff Summary

## Overview

This document explains the key differences between the original CloudFormation template and the new Terraform implementation.

## Major Changes

### 1. Operating System

**CloudFormation**: Ubuntu 24.04 LTS (ssm parameter lookup)
**Terraform**: Ubuntu 24.04 LTS (AMI lookup via data source)

**Why**: Maintained Ubuntu for consistency with CloudFormation's battle-tested configuration. Using data source instead of SSM lookup is more Terraform-idiomatic.

### 2. Instance Type & Cost

**CloudFormation**: Default c7g.large (~$40/month)
**Terraform**: Default t4g.small (~$13/month)

**Why**: Cheapest instance type for cost-conscious deployments. Users can easily upgrade via `instance_type` variable.

### 3. VPC Architecture

**CloudFormation**: 
- Creates custom VPC with public + private subnets
- Two subnets (10.0.1.0/24 and 10.0.2.0/24)
- Complex routing

**Terraform**: 
- Uses AWS Default VPC
- Single public subnet
- Simple, no NAT Gateway

**Why**: 
- Zero additional cost (no NAT Gateway at ~$30-50/month)
- Faster deployment (no VPC creation)
- SSM works via internet gateway (no VPC endpoints required)
- Adequate for single-instance workloads

### 4. VPC Endpoints

**CloudFormation**: Enabled by default (~$22/month)
**Terraform**: Disabled by default (variable `enable_vpc_endpoints = false`)

**Why**: Cost savings for dev/test. Can be enabled for production/compliance.

### 5. Access Method

**CloudFormation**: 
- SSH optional (configurable via `AllowedSSHCIDR`)
- Key pair required parameter

**Terraform**: 
- **SSM-only (no SSH at all)**
- No SSH key pairs
- No port 22 ingress rules

**Why**: 
- More secure: No SSH key management
- AWS best practice for EC2 access
- Complete audit logging via CloudTrail
- No attack surface on port 22

### 6. Model Provider Flexibility

**CloudFormation**: 
- Hardcoded Bedrock only
- Bedrock model ID parameter

**Terraform**: 
- Bedrock default (matches CloudFormation)
- Optional OpenRouter support via Terraform variable
- OpenRouter API key stored in SSM SecureString (set via CLI, never in Terraform state)
- Conditional IAM permissions always include Bedrock (fallback)

**Why**: 
- Bedrock is the natural fit for AWS-native deployment
- OpenRouter available for users who prefer it
- No secrets in Terraform state

### 7. Deployment Method

**CloudFormation**: 
- Native Node.js installation via npm
- ~300 line bash script
- Uses NVM for Node version management

**Terraform**: 
- Native Node.js host install (same as CloudFormation)
- NVM + Node.js 22 + openclaw via npm
- systemd user service via `openclaw daemon install`
- No Docker

**Why**: 
- Aligned with upstream aws-samples pattern
- Lower resource overhead than containers
- Simpler dependency chain

### 8. Wait Conditions

**CloudFormation**: 
- WaitCondition + WaitConditionHandle
- 15-minute timeout
- cfn-signal on completion

**Terraform**: 
- **Removed entirely**
- User data runs asynchronously
- Verification via Runbook commands

**Why**: 
- Terraform doesn't need synchronous completion
- Instance readiness can be verified post-deployment
- Reduces complexity

### 9. Secret Management

**CloudFormation**: 
- Gateway token generated in user data
- Saved to SSM Parameter Store
- Hardcoded parameter paths

**Terraform**: 
- Gateway token generated at boot by the instance
- Written to SSM SecureString via `aws ssm put-parameter`
- OpenRouter API key set via CLI (never in Terraform state)
- Configurable parameter prefixes

**Why**: 
- No secrets in Terraform state
- Matches CloudFormation's generate-at-boot pattern
- Better security posture

### 10. IAM Permissions

**CloudFormation**: 
- Wildcard Bedrock permissions
- Wildcard SSM parameter access
- S3 wildcard permissions (if present)

**Terraform**: 
- Scoped SSM parameter access: `/openclaw/${environment}/*`
- Conditional Bedrock permissions (only if model_provider = "bedrock")
- Least-privilege principle

**Why**: 
- Better security posture
- Follows AWS best practices
- Demonstrates proper IAM design

### 11. Outputs

**CloudFormation**: 
- Complex output construction for access URL
- WaitCondition data parsing
- Multi-step output references

**Terraform**: 
- Clean, direct outputs
- Commands ready to copy-paste
- Verification commands included

**Why**: 
- Better user experience
- Terraform's output system is more straightforward

### 12. Messaging Channel Setup

**CloudFormation**: 
- Auto-enables WhatsApp, Telegram, Discord, Slack, iMessage, Google Chat
- All plugins enabled in user data

**Terraform**: 
- Docker container starts with basic configuration
- Channel setup via Web UI or manual configuration
- Secrets stored in SSM for channels

**Why**: 
- More flexible
- Users configure only what they need
- Secrets properly managed

## Cost Comparison

| Component | CloudFormation (Default) | Terraform (Default) | Savings |
|-----------|-------------------------|---------------------|---------|
| EC2 Instance | c7g.large (~$40/mo) | t4g.small (~$13/mo) | ~$27/mo |
| VPC Endpoints | Enabled (~$22/mo) | Disabled ($0) | ~$22/mo |
| NAT Gateway | N/A (not used) | N/A (default VPC) | $0 |
| **Total** | **~$62-67/mo** | **~$16-20/mo** | **~$46-47/mo** |

**Terraform with production settings** (t4g.medium + VPC endpoints): ~$35-40/month

## Files Removed

Not present in Terraform version:
- Private subnet (not needed with default VPC)
- NAT Gateway (not needed)
- Custom route tables (default VPC handles this)
- WaitCondition/WaitConditionHandle (not needed)
- SSH ingress rules (SSM-only)
- Key pair references (SSM-only)

## Files Added

New in Terraform version:
- Modular structure (iam/, network/, ec2/, vpc_endpoints/)
- Data sources for dynamic AMI lookup
- Conditional resource creation (count)
- Comprehensive Runbook.md with Telegram setup guide

## Operational Differences

| Operation | CloudFormation | Terraform |
|-----------|---------------|-----------|
| Deploy | AWS Console or CLI | `terraform apply` |
| Update | Stack update | `terraform apply` |
| Destroy | Stack delete | `terraform destroy` |
| View config | Stack parameters | `terraform show` |
| Get outputs | Stack outputs tab | `terraform output` |
| Access instance | SSH or SSM | SSM only |
| Update OpenClaw | SSH + npm update | SSM + npm update |

## Migration Notes

If migrating from CloudFormation to Terraform:

1. **Data migration**: Backup `/home/ubuntu/.openclaw/` from CF instance
2. **Secrets**: Copy values from CF SSM parameters to new paths
3. **Downtime**: Plan for brief downtime during cutover
4. **Testing**: Deploy Terraform side-by-side first
5. **DNS**: Update any DNS records to new instance

## Architectural Decisions Summary

1. **Default VPC**: Acceptable for single-instance workloads; easy to switch to custom VPC later
2. **SSM-only**: More secure than SSH; AWS recommended approach
3. **Native host install**: Aligned with upstream aws-samples pattern; lower overhead than Docker
4. **Bedrock default**: AWS-native, no API key management; OpenRouter available as option
5. **No secrets in state**: Gateway token generated at boot; API keys set via CLI
6. **Modular structure**: Easier to maintain and extend
7. **Cost-first defaults**: Cheapest working configuration; users scale up as needed
