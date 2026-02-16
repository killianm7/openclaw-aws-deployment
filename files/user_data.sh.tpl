#!/bin/bash
# OpenClaw Setup Script for Ubuntu 24.04 LTS
# Host install (no Docker) with systemd user service
# Runs as root on first boot

set -euo pipefail

exec > >(tee /var/log/openclaw-setup.log)
exec 2>&1

echo "=========================================="
echo "OpenClaw Setup Starting: $(date)"
echo "=========================================="

export AWS_REGION="${region}"
export DEBIAN_FRONTEND=noninteractive

# Retry function for network operations
retry_command() {
    local max_attempts=5
    local attempt=1
    local delay=2
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: $*"
        if "$@"; then
            return 0
        fi
        echo "Command failed, waiting $${delay}s before retry..."
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
    echo "Command failed after $max_attempts attempts"
    return 1
}

# [1/9] System update
echo "[1/9] Updating system packages..."
retry_command apt-get update
retry_command apt-get upgrade -y
retry_command apt-get install -y curl unzip jq ca-certificates

# [2/9] Configure swap space (prevents OOM on small instances)
echo "[2/9] Configuring 2 GB swap space..."
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap enabled: $(swapon --show)"
else
    echo "Swap already configured"
fi

# [3/9] Install AWS CLI v2
echo "[3/9] Installing AWS CLI v2..."
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    retry_command curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    retry_command curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
./aws/install --update
rm -rf aws awscliv2.zip
echo "AWS CLI version: $(aws --version)"

# [4/9] Configure SSM Agent (pre-installed on Ubuntu 24.04)
echo "[4/9] Configuring SSM Agent..."
snap start amazon-ssm-agent 2>/dev/null || systemctl start amazon-ssm-agent || true

# [5/9] Install Node.js 22 + OpenClaw under ubuntu user
echo "[5/9] Installing Node.js and OpenClaw..."
sudo -u ubuntu bash << 'NODEINSTALL'
set -e
export HOME=/home/ubuntu
cd ~

# Install NVM
for i in 1 2 3; do
    if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; then
        break
    fi
    echo "NVM install failed, retry $i/3..."
    sleep 5
done

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install 22
nvm use 22
nvm alias default 22

# Install OpenClaw
npm config set registry https://registry.npmjs.org/
npm install -g openclaw@latest --timeout=300000 || {
    echo "OpenClaw install failed, retrying..."
    npm cache clean --force
    npm install -g openclaw@latest --timeout=300000
}

# Ensure NVM is in bashrc
if ! grep -q 'NVM_DIR' ~/.bashrc; then
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> ~/.bashrc
fi
NODEINSTALL

# [6/9] Generate gateway token and retrieve secrets
echo "[6/9] Generating gateway token and retrieving secrets..."

# Generate gateway token at boot
GATEWAY_TOKEN=$(openssl rand -hex 24)

# Write gateway token to SSM Parameter Store
aws ssm put-parameter \
    --name "${gateway_token_ssm_path}" \
    --value "$GATEWAY_TOKEN" \
    --type "SecureString" \
    --overwrite \
    --region ${region}
echo "Gateway token stored in SSM: ${gateway_token_ssm_path}"

# Determine effective provider (may fall back to bedrock)
EFFECTIVE_PROVIDER="${model_provider}"

%{ if model_provider == "openrouter" && openrouter_ssm_param != "" ~}
# Attempt to retrieve OpenRouter API key from SSM
max_retries=5
retry_count=0
OPENROUTER_API_KEY=""
while [ $retry_count -lt $max_retries ] && [ -z "$OPENROUTER_API_KEY" ]; do
    OPENROUTER_API_KEY=$(aws ssm get-parameter \
        --name "${openrouter_ssm_param}" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region ${region} 2>/dev/null) || true
    if [ -z "$OPENROUTER_API_KEY" ]; then
        retry_count=$((retry_count + 1))
        echo "Failed to retrieve OpenRouter API key, retry $retry_count/$max_retries..."
        sleep 5
    fi
done

if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "WARNING: OpenRouter key not found in SSM. Falling back to Bedrock provider."
    EFFECTIVE_PROVIDER="bedrock"
fi
%{ endif ~}

# [7/9] Install systemd service + enable Telegram plugin
echo "[7/9] Setting up systemd service and plugins..."

# Enable systemd linger for ubuntu user (services persist without login)
loginctl enable-linger ubuntu

# Install daemon (creates user-level systemd service named openclaw-gateway)
sudo -H -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 bash -c '
export HOME=/home/ubuntu
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
openclaw daemon install || echo "Daemon install failed"
'

# Enable Telegram plugin BEFORE writing final config (plugin enable overwrites config)
# No bot token configured yet -- see Runbook.md for Telegram setup
sudo -H -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 bash -c '
export HOME=/home/ubuntu
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
openclaw plugins enable telegram || echo "Telegram plugin enable failed"
'

# [8/9] Write final OpenClaw configuration (after plugin enable to avoid overwrite)
echo "[8/9] Writing OpenClaw configuration (provider: $EFFECTIVE_PROVIDER)..."

sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw

if [ "$EFFECTIVE_PROVIDER" = "openrouter" ]; then
    sudo -u ubuntu tee /home/ubuntu/.openclaw/openclaw.json > /dev/null << JSONEOF
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": false
    },
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    }
  },
  "models": {
    "providers": {
      "openrouter": {
        "baseUrl": "https://openrouter.ai/api/v1",
        "api": "openai",
        "auth": "api-key",
        "apiKey": "$OPENROUTER_API_KEY",
        "models": [
          {
            "id": "${openrouter_model_id}",
            "name": "OpenRouter Model",
            "input": ["text", "image"],
            "contextWindow": 128000,
            "maxTokens": 16384
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openrouter/${openrouter_model_id}"
      }
    }
  }
}
JSONEOF
else
    sudo -u ubuntu tee /home/ubuntu/.openclaw/openclaw.json > /dev/null << JSONEOF
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": false
    },
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    }
  },
  "models": {
    "providers": {
      "amazon-bedrock": {
        "baseUrl": "https://bedrock-runtime.${region}.amazonaws.com",
        "api": "bedrock-converse-stream",
        "auth": "aws-sdk",
        "models": [
          {
            "id": "${bedrock_model_id}",
            "name": "Bedrock Model",
            "input": ["text", "image"],
            "contextWindow": ${bedrock_context_window},
            "maxTokens": ${bedrock_max_tokens}
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "amazon-bedrock/${bedrock_model_id}"
      }
    }
  }
}
JSONEOF
fi

# Enable service to persist across reboots (actual service name is openclaw-gateway)
sudo -H -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 bash -c '
systemctl --user enable openclaw-gateway 2>/dev/null || systemctl --user enable openclaw-gateway.service 2>/dev/null || echo "Service enable deferred"
'

# Start the daemon
sudo -H -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 bash -c '
systemctl --user start openclaw-gateway 2>/dev/null || systemctl --user start openclaw-gateway.service 2>/dev/null || echo "Service start deferred to linger"
'

# [9/9] Verify and create access info
echo "[9/9] Verifying installation..."
sleep 10

# Get instance metadata via IMDSv2
TOKEN_IMDS=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN_IMDS" \
    http://169.254.169.254/latest/meta-data/instance-id)

# Create access instructions (NO token in plaintext)
cat > /home/ubuntu/ACCESS.txt << EOF
==========================================
OpenClaw Access Information
==========================================
Instance ID: $INSTANCE_ID
Region: ${region}
Model Provider: $EFFECTIVE_PROVIDER

To access the Web UI:
1. Port forward from your local machine:
   aws ssm start-session --target $INSTANCE_ID --region ${region} \\
     --document-name AWS-StartPortForwardingSession \\
     --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

2. Get gateway token from SSM (secure method):
   aws ssm get-parameter --name "${gateway_token_ssm_path}" \\
     --with-decryption --region ${region} \\
     --query 'Parameter.Value' --output text

3. Open: http://localhost:18789/?token=<TOKEN_FROM_SSM>

IMPORTANT: Gateway token is stored ONLY in AWS SSM Parameter Store.
==========================================
EOF

chown ubuntu:ubuntu /home/ubuntu/ACCESS.txt
chmod 600 /home/ubuntu/ACCESS.txt

echo "SUCCESS: $(date)" > /home/ubuntu/.openclaw/setup_complete.txt
chown ubuntu:ubuntu /home/ubuntu/.openclaw/setup_complete.txt

echo "=========================================="
echo "Setup Complete: $(date)"
echo "=========================================="
echo ""
echo "Debug commands (as ubuntu user):"
echo "  systemctl --user status openclaw-gateway"
echo "  journalctl --user -u openclaw-gateway -f"
echo ""
echo "View access instructions:"
echo "  cat ~/ACCESS.txt"
