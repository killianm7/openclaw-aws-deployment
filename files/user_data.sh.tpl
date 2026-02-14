#!/bin/bash
# OpenClaw Setup Script for Ubuntu 24.04 LTS
# Runs as root on first boot

set -e

exec > >(tee /var/log/openclaw-setup.log)
exec 2>&1

echo "=========================================="
echo "OpenClaw Setup Starting: $(date)"
echo "=========================================="

export AWS_REGION="${region}"
export DEBIAN_FRONTEND=noninteractive

# Update system
echo "[1/8] Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common unzip

# Install Docker
echo "[2/8] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install Docker Compose standalone (v2)
echo "[3/8] Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.24.0"
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "arm64" ]; then
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
else
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
fi
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Create OpenClaw directory structure
echo "[4/8] Setting up OpenClaw directories..."
mkdir -p /opt/openclaw/{data,config}
cd /opt/openclaw
chown -R ubuntu:ubuntu /opt/openclaw

# Install AWS CLI v2
echo "[4.5/8] Installing AWS CLI v2..."
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
./aws/install --update
rm -rf aws awscliv2.zip

# Fetch secrets from SSM Parameter Store
echo "[5/8] Retrieving secrets from SSM..."
GATEWAY_TOKEN=$(aws ssm get-parameter --name "${gateway_token_param}" --with-decryption --query 'Parameter.Value' --output text --region ${region} 2>/dev/null || echo "")

%{ if model_provider == "openrouter" ~}
OPENROUTER_API_KEY=$(aws ssm get-parameter --name "${openrouter_key_param}" --with-decryption --query 'Parameter.Value' --output text --region ${region} 2>/dev/null || echo "")
%{ endif ~}

# Generate gateway token if not retrieved (fallback)
if [ -z "$GATEWAY_TOKEN" ]; then
    GATEWAY_TOKEN=$(openssl rand -hex 24)
    echo "Warning: Could not retrieve gateway token from SSM, generated new one"
fi

# Save gateway token locally for reference
echo "$GATEWAY_TOKEN" > /opt/openclaw/gateway_token.txt
chown ubuntu:ubuntu /opt/openclaw/gateway_token.txt
chmod 600 /opt/openclaw/gateway_token.txt

# Create docker-compose.yml
echo "[6/8] Creating Docker Compose configuration..."
cat > /opt/openclaw/docker-compose.yml << COMPOSEEOF
version: '3.8'

services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "127.0.0.1:18789:18789"
    environment:
      - GATEWAY_TOKEN=$GATEWAY_TOKEN
%{ if model_provider == "openrouter" ~}
      - OPENROUTER_API_KEY=$OPENROUTER_API_KEY
      - MODEL_PROVIDER=openrouter
      - MODEL_NAME=openai/gpt-4o-mini
%{ else ~}
      - MODEL_PROVIDER=bedrock
      - BEDROCK_MODEL_ID=${bedrock_model_id}
      - AWS_REGION=${region}
%{ endif ~}
    volumes:
      - /opt/openclaw/data:/app/data
      - /opt/openclaw/config:/app/config
    logging:
      driver: "awslogs"
      options:
        awslogs-region: "${region}"
        awslogs-group: "${log_group}"
        awslogs-stream-prefix: "openclaw"
COMPOSEEOF

chown ubuntu:ubuntu /opt/openclaw/docker-compose.yml

# Create systemd service for Docker Compose
echo "[7/8] Creating systemd service..."
cat > /etc/systemd/system/openclaw.service << 'SERVICEEOF'
[Unit]
Description=OpenClaw Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openclaw
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable openclaw

# Start OpenClaw
echo "[8/8] Starting OpenClaw..."
systemctl start openclaw

# Wait for container to be healthy
echo "Waiting for OpenClaw to start..."
sleep 15

if docker ps | grep -q openclaw; then
    echo "✓ OpenClaw container is running"
    
    # Get instance metadata
    TOKEN_IMDS=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
    if [ -n "$TOKEN_IMDS" ]; then
        INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN_IMDS" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
    else
        INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
    fi
    
    # Create access instructions
    cat > /opt/openclaw/ACCESS.txt << EOF
==========================================
OpenClaw Access Information
==========================================
Instance ID: $INSTANCE_ID
Region: ${region}
Model Provider: ${model_provider}

To access the Web UI:
1. Port forward from your local machine:
   aws ssm start-session --target $INSTANCE_ID --region ${region} --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

2. Open in browser:
   http://localhost:18789/?token=$GATEWAY_TOKEN

Gateway token location (on instance):
   /opt/openclaw/gateway_token.txt

==========================================
EOF
    
    chown ubuntu:ubuntu /opt/openclaw/ACCESS.txt
    echo "SUCCESS: $(date)" > /opt/openclaw/setup_complete.txt
    echo "✓ Setup complete!"
else
    echo "✗ OpenClaw container failed to start"
    echo "Checking logs..."
    docker logs openclaw 2>&1 || echo "No logs available"
    echo "FAILED: $(date)" > /opt/openclaw/setup_complete.txt
    exit 1
fi

echo "=========================================="
echo "Setup Complete: $(date)"
echo "=========================================="
echo ""
echo "To verify OpenClaw is running:"
echo "  docker ps"
echo ""
echo "To view logs:"
echo "  docker logs -f openclaw"
echo ""
echo "To view access instructions:"
echo "  cat /opt/openclaw/ACCESS.txt"
