#!/bin/bash
# Docker Compose Validation Script
# Tests Docker Compose configuration without building or running containers
#
# Usage: ./tests/test-docker-compose.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "Docker Compose Configuration Validator"
echo "======================================"
echo ""

cd "$(dirname "$0")/.."

ERRORS=0
WARNINGS=0

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
  ((ERRORS++)) || true
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++)) || true
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# Check if docker-compose file exists
if [ ! -f "docker-compose.yml" ]; then
  print_error "docker-compose.yml not found in root directory"
  exit 1
fi

print_success "docker-compose.yml found"

# Check Docker is available
if ! command -v docker &> /dev/null; then
  print_warning "Docker not installed. Skipping Docker-specific validation."
  echo ""
  echo "To validate Docker Compose syntax without Docker, install Docker Desktop:"
  echo "  https://docs.docker.com/desktop/"
  exit 0
fi

print_success "Docker is installed"

# Validate compose syntax
print_info "Validating Docker Compose syntax..."
if docker-compose -f docker-compose.yml config > /dev/null 2>&1; then
  print_success "Docker Compose syntax is valid"
else
  print_error "Docker Compose syntax errors detected"
  docker-compose -f docker-compose.yml config 2>&1 || true
fi

# Check for required services
print_info "Checking services..."
if grep -q "services:" docker-compose.yml; then
  print_success "Services section found"
else
  print_error "No services section found"
fi

if grep -q "openclaw:" docker-compose.yml; then
  print_success "OpenClaw service defined"
else
  print_error "OpenClaw service not found"
fi

# Validate security best practices
print_info "Checking security configurations..."

# Check image is pinned (not using 'latest')
if grep -E "image:.*:latest" docker-compose.yml > /dev/null; then
  print_error "Image uses 'latest' tag (security risk) - pin to specific version"
else
  print_success "Image is pinned to specific version"
fi

# Check if ports are bound to localhost only
if grep -E "ports:" docker-compose.yml > /dev/null; then
  if grep -E "127\.0\.0\.1:" docker-compose.yml > /dev/null; then
    print_success "Ports bound to localhost only (127.0.0.1)"
  else
    print_warning "Ports may be exposed to all interfaces (check if this is intentional)"
  fi
fi

# Check for restart policy
if grep -E "restart:" docker-compose.yml > /dev/null; then
  print_success "Restart policy configured"
else
  print_warning "No restart policy configured"
fi

# Check for volume mounts
if grep -E "volumes:" docker-compose.yml > /dev/null; then
  print_success "Volume mounts configured"
  
  # Check for persistent data
  if grep -E "/app/data" docker-compose.yml > /dev/null; then
    print_success "Data volume mounted for persistence"
  fi
  
  if grep -E "/app/config" docker-compose.yml > /dev/null; then
    print_success "Config volume mounted"
  fi
else
  print_warning "No volume mounts configured"
fi

# Check for logging configuration
if grep -E "logging:" docker-compose.yml > /dev/null; then
  print_success "Logging configuration present"
  
  if grep -E "awslogs" docker-compose.yml > /dev/null; then
    print_success "AWS CloudWatch logging configured"
  fi
else
  print_warning "No logging configuration (logs will go to default driver)"
fi

# Check for environment variables
print_info "Checking environment variables..."
ENV_VARS=$(grep -E "^\s+- [A-Z_]+=\$\{" docker-compose.yml | wc -l)
if [ "$ENV_VARS" -gt 0 ]; then
  print_success "Found $ENV_VARS environment variables using variable substitution"
  
  # List key variables
  print_info "Key environment variables detected:"
  grep -E "^\s+- [A-Z_]+=" docker-compose.yml | sed 's/^[[:space:]]*/  /' | head -10
else
  print_warning "No environment variables with substitution found"
fi

# Check for resource limits (optional but recommended)
if grep -E "deploy:" docker-compose.yml > /dev/null && \
   grep -E "resources:" docker-compose.yml > /dev/null; then
  print_success "Resource limits configured"
else
  print_info "Resource limits not configured (optional but recommended for production)"
fi

# Display parsed configuration
print_info ""
print_info "Parsed Docker Compose configuration:"
echo "-----------------------------------"
docker-compose -f docker-compose.yml config 2>/dev/null | head -50 || echo "(Could not parse configuration)"

echo ""
echo "======================================"
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ Docker Compose validation passed${NC}"
  if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}  ($WARNINGS warning(s))${NC}"
  fi
  exit 0
else
  echo -e "${RED}✗ Docker Compose validation failed with $ERRORS error(s)${NC}"
  exit 1
fi
