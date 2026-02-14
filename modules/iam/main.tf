# IAM Role for EC2 Instance
resource "aws_iam_role" "openclaw" {
  name = "openclaw-${var.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "openclaw-${var.environment}-role"
  }
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.openclaw.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.openclaw.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for SSM Parameter Store access
resource "aws_iam_role_policy" "ssm_parameters" {
  name = "ssm-parameter-access"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter${var.ssm_parameter_prefix}/*"
      }
    ]
  })
}

# Conditional Bedrock policy (only if using Bedrock)
resource "aws_iam_role_policy" "bedrock" {
  count = var.model_provider == "bedrock" ? 1 : 0

  name = "bedrock-access"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
        # Note: Bedrock doesn't support resource-level permissions for most actions
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "openclaw" {
  name = "openclaw-${var.environment}-profile"
  role = aws_iam_role.openclaw.name
}