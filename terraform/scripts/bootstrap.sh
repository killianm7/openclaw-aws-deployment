#!/bin/bash
# OpenClaw EC2 Bootstrap Script
# This script installs Docker, Docker Compose, and sets up OpenClaw

set -e
exec > >(tee /var/log/openclaw-bootstrap.log)
exec 2>&1

echo "=========================================="
echo "OpenClaw Bootstrap Starting"
echo "Date: $(date)"
echo "=========================================="

# Update system
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y \
    docker \
    git \
    jq \
    aws-cli \
    amazon-cloudwatch-agent

# Start and enable Docker
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
echo "Adding ec2-user to docker group..."
usermod -aG docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="2.23.3"
curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Create OpenClaw directories
echo "Creating OpenClaw directories..."
mkdir -p /opt/openclaw/{config,data,logs}
chown -R ec2-user:ec2-user /opt/openclaw

# Fetch secrets from SSM if not provided
AWS_REGION="${aws_region}"
OPENCLAW_TOKEN="${openclaw_gateway_token}"

# Write OpenClaw configuration
echo "Writing OpenClaw configuration..."
cat > /opt/openclaw/config/openclaw.json << 'EOFCONFIG'
{
  "gateway": {
    "mode": "local",
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_TOKEN}"
    },
    "logging": {
      "level": "info",
      "redactSensitive": "tools",
      "file": "/app/logs/openclaw.log"
    },
    "discovery": {
      "mdns": {
        "mode": "off"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "provider": "ollama",
        "model": "llama3.2:3b"
      },
      "sandbox": {
        "mode": "all",
        "scope": "agent",
        "workspaceAccess": "ro"
      }
    },
    "list": [
      {
        "id": "main",
        "name": "OpenClaw Assistant",
        "description": "Main OpenClaw agent"
      }
    ]
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "mode": "webhook",
      "webhook": {
        "url": "http://localhost:18789/webhook/telegram"
      },
      "dmPolicy": "pairing",
      "groups": {
        "*": {
          "requireMention": true
        }
      }
    }
  },
  "tools": {
    "profile": "standard",
    "elevated": {
      "allowFrom": []
    }
  }
}
EOFCONFIG

# Replace token in config
sed -i "s/\${OPENCLAW_TOKEN}/$OPENCLAW_TOKEN/g" /opt/openclaw/config/openclaw.json

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /opt/openclaw/docker-compose.yml << 'EOFCOMPOSE'
services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "127.0.0.1:18789:18789"
    volumes:
      - ./config:/app/config:ro
      - ./data:/app/data
      - ./logs:/app/logs
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - OPENCLAW_CONFIG=/app/config/openclaw.json
      - OPENCLAW_DATA_DIR=/app/data
      - AWS_REGION=${AWS_REGION}
    networks:
      - openclaw-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "awslogs"
      options:
        awslogs-region: "${AWS_REGION}"
        awslogs-group: "${openclaw_log_group}"
        awslogs-stream: "openclaw"

  # Ollama for local model inference (optional, lightweight)
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          memory: 2G
    profiles:
      - ollama

networks:
  openclaw-network:
    driver: bridge

volumes:
  ollama-data:
EOFCOMPOSE

# Replace variables in docker-compose
sed -i "s/\${AWS_REGION}/$AWS_REGION/g" /opt/openclaw/docker-compose.yml
sed -i "s/\${openclaw_log_group}/${openclaw_log_group}/g" /opt/openclaw/docker-compose.yml

# Create startup script
echo "Creating startup script..."
cat > /opt/openclaw/start.sh << 'EOFSTART'
#!/bin/bash
cd /opt/openclaw

# Pull latest images
docker-compose pull

# Start OpenClaw
docker-compose up -d

echo "OpenClaw started!"
echo "Logs: docker-compose logs -f"
EOFSTART

chmod +x /opt/openclaw/start.sh

# Create systemd service for OpenClaw
echo "Creating systemd service..."
cat > /etc/systemd/system/openclaw.service << 'EOFSERVICE'
[Unit]
Description=OpenClaw AI Agent
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openclaw
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=ec2-user
Group=docker

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Configure CloudWatch agent
echo "Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOFCW'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/openclaw-bootstrap.log",
            "log_group_name": "/openclaw/ec2-bootstrap",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/openclaw/logs/openclaw.log",
            "log_group_name": "/openclaw/application",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "OpenClaw",
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["*"],
        "drop_device": true
      },
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu": true,
        "drop_original_metrics": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
      }
    },
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}",
      "InstanceType": "$${aws:InstanceType}"
    }
  }
}
EOFCW

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable and start OpenClaw service
echo "Enabling OpenClaw service..."
systemctl daemon-reload
systemctl enable openclaw.service

# Pull Docker images in background
echo "Pulling Docker images..."
cd /opt/openclaw
su - ec2-user -c "cd /opt/openclaw && docker-compose pull" || true

# Set proper permissions
chown -R ec2-user:ec2-user /opt/openclaw
chmod 600 /opt/openclaw/config/openclaw.json

echo "=========================================="
echo "Bootstrap Complete!"
echo "Date: $(date)"
echo "=========================================="
echo ""
echo "To start OpenClaw manually:"
echo "  sudo systemctl start openclaw"
echo ""
echo "To check status:"
echo "  sudo systemctl status openclaw"
echo ""
echo "To view logs:"
echo "  docker-compose -f /opt/openclaw/docker-compose.yml logs -f"
echo ""
