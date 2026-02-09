terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ------------------------
# SECURITY GROUP
# ------------------------
resource "aws_security_group" "web_sg" {
  name = "webapp-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------
# EC2 Instance
# ------------------------
resource "aws_instance" "web" {
  ami             = "ami-0c02fb55956c7d316"  # Update as needed per region
  instance_type   = var.instance_type
  security_groups = [aws_security_group.web_sg.name]
  user_data       = file("${path.module}/user_data.sh")

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "sumo-webapp"
  }
}

# ------------------------
# SNS Topic and Subscription
# ------------------------
resource "aws_sns_topic" "alerts" {
  name = "sumo-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_alert  # your email to receive alerts
}

# ------------------------
# IAM Role and Policy for EC2
# ------------------------
resource "aws_iam_role" "ec2_role" {
  name = "ec2-sumo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-sumo-profile"
  role = aws_iam_role.ec2_role.name
}

# ------------------------
# IAM Role and Policy for Lambda
# ------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-restart-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:RebootInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ------------------------
# Lambda Function
# ------------------------
resource "aws_lambda_function" "restart_ec2" {
  function_name = "sumo-restart-ec2"
  runtime       = "python3.9"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn

  filename         = "../lambda_function/lambda.zip"
  source_code_hash = filebase64sha256("../lambda_function/lambda.zip")

  environment {
    variables = {
      EC2_INSTANCE_ID = aws_instance.web.id
      SNS_TOPIC_ARN   = aws_sns_topic.alerts.arn
    }
  }
}

# ------------------------
# API Gateway HTTP API (Webhook for Sumo Logic → Lambda)
# ------------------------
resource "aws_apigatewayv2_api" "sumo_api" {
  name          = "sumo-alert-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.sumo_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.restart_ec2.invoke_arn
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.sumo_api.id
  route_key = "POST /alert"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.sumo_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.restart_ec2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sumo_api.execution_arn}/*/*"
}
