terraform {
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
    random  = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.region
}

# --- S3 privado para los reportes ---
resource "random_id" "sufijo" {
  byte_length = 4
}

resource "aws_s3_bucket" "reportes" {
  bucket        = "iam-auditor-reportes-${random_id.sufijo.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "reportes" {
  bucket                  = aws_s3_bucket.reportes.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- SNS: aviso por email ---
resource "aws_sns_topic" "alertas" {
  name = "iam-auditor-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.email
}

# --- Rol de IAM con permisos mínimos ---
resource "aws_iam_role" "lambda" {
  name = "iam-auditor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "iam-auditor-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:GenerateCredentialReport", "iam:GetCredentialReport"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.reportes.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alertas.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# --- Lambda ---
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "auditor" {
  function_name    = "iam-auditor"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      BUCKET           = aws_s3_bucket.reportes.bucket
      TOPIC_ARN        = aws_sns_topic.alertas.arn
      MAX_KEY_AGE_DAYS = tostring(var.max_key_age_days)
    }
  }
}

# --- EventBridge: corrida semanal ---
resource "aws_cloudwatch_event_rule" "semanal" {
  name                = "iam-auditor-semanal"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "semanal" {
  rule = aws_cloudwatch_event_rule.semanal.name
  arn  = aws_lambda_function.auditor.arn
}

resource "aws_lambda_permission" "semanal" {
  statement_id  = "AllowWeeklyRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auditor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.semanal.arn
}