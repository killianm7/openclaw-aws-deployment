# AGENTS.md - Agentic Coding Guidelines

## Project Overview

Terraform deployment for OpenClaw on AWS EC2. Native host install (no Docker), Bedrock default provider, SSM-only access. Gateway token generated at boot by userdata and stored in SSM SecureString — Terraform manages no secrets.

## Build/Lint/Test Commands

```bash
# Initialize (required before any other command)
terraform init

# Format all .tf files (run before every commit)
terraform fmt -recursive

# Validate configuration syntax and module wiring
terraform validate

# Run full test suite (format + validate + plan + unit tests; needs AWS creds)
make test

# Run ONLY static analysis (no AWS credentials needed)
make test-static

# Run ONLY terraform plan analysis (needs AWS credentials)
make test-plan

# Run a single unit-test file
terraform test

# Security scan (needs tfsec: brew install tfsec)
make security

# Plan without applying
terraform plan

# Apply from saved plan
make plan && make apply
```

### Key Makefile Targets

| Target | AWS creds? | What it does |
|--------|-----------|--------------|
| `make fmt` | No | `terraform fmt -recursive` |
| `make validate` | No | `terraform validate` |
| `make security` | No | tfsec scan (HIGH+CRITICAL) |
| `make test-static` | No | fmt + validate + tfsec + structure checks |
| `make test-plan` | Yes | `terraform plan` with analysis |
| `make test-unit` | No | `terraform test` (runs `tests/*.tftest.hcl`) |
| `make test` | Yes | All of the above combined |
| `make ci` | Yes | Strict mode for CI pipelines |

## Code Style Guidelines

### File Layout per Module

Each module directory (`modules/<name>/`) and the root must contain:
- `main.tf` — resources and data sources
- `variables.tf` — input variables (every variable needs `description` and `type`)
- `outputs.tf` — output values

Root also has: `versions.tf` (provider constraints), `terraform.tfvars.example`.

### Ordering Within `main.tf`

1. Data sources (with `# Data Sources` header)
2. Locals (with `# Locals` header)
3. Resources in logical order (IAM → network → compute)
4. Module calls last

### Naming Conventions

- **All identifiers**: `snake_case` — resources, variables, outputs, locals, modules
- **Resource names**: `aws_<service>.<descriptive_name>` (e.g., `aws_iam_role.openclaw`)
- **Variable names**: prefixed by domain (e.g., `aws_region`, `bedrock_model_id`, `root_volume_size`)
- **Module directories**: lowercase, single word when possible (`iam`, `network`, `ec2`)
- **SSM paths**: `/<project>/<environment>/<key-name>` (e.g., `/openclaw/dev/gateway-token`)

### Formatting

- `terraform fmt -recursive` is the authority — always run before committing
- 2-space indentation (Terraform default)
- Align `=` signs within a block for readability
- Keep lines under 100 characters where practical

### Variables

```hcl
variable "example" {
  description = "What this variable controls"
  type        = string
  default     = "value"

  validation {
    condition     = can(regex("^pattern$", var.example))
    error_message = "Human-readable message explaining valid values."
  }
}
```

- Always specify `type` and `description`
- Add `validation` blocks with clear `error_message` for user-facing variables
- Never add `sensitive = true` to variables — this project keeps all secrets out of Terraform state

### Outputs

```hcl
output "name" {
  description = "What this output provides"
  value       = some_resource.attr
}
```

- Every output needs a `description`
- Do not mark outputs `sensitive` unless they contain actual secret values
- Prefer actionable outputs (copy-pasteable CLI commands) over raw IDs

### Security Rules (hard requirements)

- **No secrets in Terraform state** — gateway token is generated at boot; API keys are set via CLI
- **IMDSv2 enforced**: `metadata_options { http_tokens = "required" }` on all EC2 instances
- **EBS encryption**: `encrypted = true` on all volumes
- **SSM SecureString** for any parameter containing a secret
- **IAM least privilege**: scope to specific resource ARNs; `*` only where AWS requires it (e.g., Bedrock)
- **No inbound security group rules** — SSM-only access model
- **Gateway binds loopback** (`127.0.0.1`) — access via SSM port-forward only
- **`allowInsecureAuth: false`** in OpenClaw gateway config

### IAM Policy Pattern

```hcl
resource "aws_iam_role_policy" "name" {
  name = "descriptive-name"
  role = aws_iam_role.openclaw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["service:SpecificAction"]
      Resource = "arn:aws:service:${var.aws_region}:${var.aws_account_id}:resource/*"
    }]
  })
}
```

### Bash Scripts (`files/user_data.sh.tpl`)

- Start with `set -euo pipefail`
- Log everything: `exec > >(tee /var/log/openclaw-setup.log) 2>&1`
- Use numbered step markers: `echo "[3/8] Installing Node.js..."`
- Add `retry_command` wrapper for all network operations
- Use `$${var}` for bash variables (Terraform template escaping); `${var}` for template variables
- Use IMDSv2 exclusively (`curl -X PUT ... -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`)
- Never write secrets to disk — pass via environment variables or heredoc stdin
- Set `chmod 600` on any file containing access instructions

### Tagging

- Standard tags applied via `default_tags` in provider block: `Project`, `ManagedBy`, `Environment`
- Resource-specific: `tags = merge(var.tags, { Name = "openclaw-${var.environment}" })`

### Error Handling

- Prefer `validation` blocks on variables over runtime checks
- Use `count` or `for_each` for conditional resources — avoid ternary in resource bodies
- In userdata: if an optional secret (e.g., OpenRouter key) can't be retrieved, fall back gracefully — don't `exit 1`

## Architecture Invariants

- **No Docker** — OpenClaw runs as a native Node.js process via `openclaw daemon install`
- **systemd user service** — managed under the `ubuntu` user with `loginctl enable-linger`
- **Bedrock is always the fallback** — IAM Bedrock permissions are always attached
- **Gateway token lifecycle** — generated at boot, written to SSM by userdata, never in Terraform state
- **Single EC2 instance** in default VPC — no NAT gateway, no custom networking

## Pre-commit Checklist

1. `terraform fmt -recursive` (zero diff)
2. `terraform validate` (success)
3. `make security` (no HIGH/CRITICAL findings)
4. No hardcoded secrets, tokens, or API keys anywhere
5. All variables have `description` and `type`
6. IAM policies scoped to specific resources
7. `terraform plan` reviewed for unexpected changes
8. README.md / Runbook.md updated if user-facing behavior changed
