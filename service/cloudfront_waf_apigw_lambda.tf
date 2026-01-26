# -----------------------------------------------------------------------------
# CloudFront -> WAF -> API Gateway -> Lambda のモックテスト環境
# -----------------------------------------------------------------------------
# 注意: data "aws_region" "current" は ecs.tf で定義済み
# 注意: data "aws_caller_identity" "me" は main.tf で定義済み

locals {
  api_name                 = "wiz-dev-mock-api"
  lambda_name              = "wiz-dev-mock-lambda"
  waf_name                 = "wiz-dev-mock-waf"
  cloudfront_name          = "wiz-dev-mock-cf"
  waf_log_bucket_name      = "wiz-dev-waf-logs-${data.aws_caller_identity.me.account_id}"
  cloudfront_log_bucket_name = "wiz-dev-cloudfront-logs-${data.aws_caller_identity.me.account_id}"
}

# -----------------------------------------------------------------------------
# Lambda Function (モックレスポンス)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${local.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${local.lambda_name}-role"
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda関数のコード（インライン）
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content  = <<EOF
exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            message: 'Hello from Lambda!',
            timestamp: new Date().toISOString(),
            path: event.path,
            method: event.httpMethod,
            queryParams: event.queryStringParameters || {},
            headers: event.headers
        })
    };
};
EOF
    filename = "index.js"
  }
}

resource "aws_lambda_function" "mock" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name    = local.lambda_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# -----------------------------------------------------------------------------
# API Gateway (REST API)
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "mock" {
  name        = local.api_name
  description = "Mock API for CloudFront -> WAF -> API Gateway -> Lambda test"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # CloudFrontからのアクセスを許可するリソースポリシー
  # テスト環境のため、すべてのアクセスを許可
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Principal = "*"
        Action   = "execute-api:Invoke"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = local.api_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.mock.id
  parent_id   = aws_api_gateway_rest_api.mock.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.mock.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.mock.id
  resource_id   = aws_api_gateway_rest_api.mock.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.mock.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mock.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.mock.id
  resource_id = aws_api_gateway_rest_api.mock.root_resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mock.invoke_arn
}

resource "aws_api_gateway_deployment" "mock" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.mock.id

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda に API Gateway からの呼び出しを許可
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mock.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.mock.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# WAF Web ACL (API Gateway用)
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "apigw" {
  name        = local.waf_name
  description = "WAF for API Gateway mock test"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 基本的なルール: Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule: Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.waf_name
    sampled_requests_enabled   = true
  }

  tags = {
    Name    = local.waf_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# API Gateway Stage (WAF アタッチ用)
# 注意: 既存のステージが存在する場合は、terraform import でインポートするか、
# または既存のステージを手動で削除してください
resource "aws_api_gateway_stage" "mock" {
  deployment_id = aws_api_gateway_deployment.mock.id
  rest_api_id   = aws_api_gateway_rest_api.mock.id
  stage_name    = "test"

  lifecycle {
    # 既存のステージが存在する場合、deployment_id の変更を無視
    ignore_changes = [deployment_id]
  }
}

# WAF を API Gateway にアタッチ
resource "aws_wafv2_web_acl_association" "apigw" {
  resource_arn = aws_api_gateway_stage.mock.arn
  web_acl_arn  = aws_wafv2_web_acl.apigw.arn
}

# -----------------------------------------------------------------------------
# S3 Bucket for WAF Logs (オプション)
# 注意: REGIONALスコープのWAFはS3に直接書き込めません。
# CloudWatch LogsからKinesis Data Firehose経由でS3に送る場合は使用可能です。
# 現在はCloudWatch Logsを使用しているため、このバケットは将来の拡張用です。
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "waf_logs" {
  bucket        = local.waf_log_bucket_name
  force_destroy = true # テスト環境のため、削除時に中身も削除

  tags = {
    Name    = local.waf_log_bucket_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# S3バケットのバージョニング
resource "aws_s3_bucket_versioning" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3バケットの暗号化
resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3バケットのパブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# WAFサービスがS3バケットにログを書き込むためのバケットポリシー
resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${data.aws_caller_identity.me.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.waf_logs.arn
      }
    ]
  })
}

# CloudWatch Logs Log Group for WAF Logs
# 注意: REGIONALスコープのWAFはS3に直接書き込めないため、CloudWatch Logsを使用
# 重要: WAFv2のロググループ名は "aws-waf-logs-" で始まる必要がある
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-${local.waf_name}"
  retention_in_days = 7

  tags = {
    Name    = "${local.waf_name}-logs"
    Project = "tf-aws"
    Env     = "dev"
  }
}

# WAFサービスがCloudWatch Logsに書き込むためのリソースポリシー
resource "aws_cloudwatch_log_resource_policy" "waf_logs" {
  policy_name = "${local.waf_name}-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "wafv2.amazonaws.com"
        }
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.waf_logs.arn}:*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_wafv2_web_acl.apigw.arn
          }
        }
      }
    ]
  })
}

# WAFログ設定（CloudWatch Logsを使用）
# 注意: WAFv2のログ設定では、CloudWatch LogsのARNに :* サフィックスが必要
resource "aws_wafv2_web_acl_logging_configuration" "apigw" {
  resource_arn            = aws_wafv2_web_acl.apigw.arn
  log_destination_configs = ["${aws_cloudwatch_log_group.waf_logs.arn}:*"]

  # ログに含めるフィールドを指定（オプション）
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf_logs]
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# -----------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "mock" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for WAF -> API Gateway -> Lambda test"
  default_root_object = ""

  origin {
    domain_name = "${aws_api_gateway_rest_api.mock.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_id   = "apigw-${aws_api_gateway_rest_api.mock.id}"
    origin_path = "/${aws_api_gateway_stage.mock.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # API Gatewayが正しくリクエストを処理できるようにヘッダーを設定
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
    # HostヘッダーをAPI Gatewayのドメイン名に設定
    custom_header {
      name  = "Host"
      value = "${aws_api_gateway_rest_api.mock.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "apigw-${aws_api_gateway_rest_api.mock.id}"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto", "X-Forwarded-For"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # WAF Web ACL を CloudFront にアタッチ（CloudFront スコープが必要）
  # 注意: API Gateway に既に WAF をアタッチしているため、CloudFront レベルではオプション
  # CloudFront 用の WAF を作成する場合は scope = "CLOUDFRONT" が必要

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # CloudFrontアクセスログ設定
  logging_config {
    bucket          = aws_s3_bucket.cloudfront_logs.id
    include_cookies = false
    prefix          = "cloudfront-logs"
  }

  tags = {
    Name    = local.cloudfront_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket for CloudFront Access Logs
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudfront_logs" {
  bucket        = local.cloudfront_log_bucket_name
  force_destroy = true # テスト環境のため、削除時に中身も削除

  tags = {
    Name    = local.cloudfront_log_bucket_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# S3バケットのバージョニング
resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3バケットの暗号化
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3バケットのパブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFrontサービスがS3バケットにログを書き込むためのバケットポリシー
resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudfront_logs.arn}/cloudfront-logs/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.me.account_id}:distribution/${aws_cloudfront_distribution.mock.id}"
          }
        }
      },
      {
        Sid    = "AllowCloudFrontServicePrincipalGetBucketAcl"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudfront_logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.me.account_id}:distribution/${aws_cloudfront_distribution.mock.id}"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "lambda_function_name" {
  value       = aws_lambda_function.mock.function_name
  description = "Lambda function name"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.mock.arn
  description = "Lambda function ARN"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.mock.id
  description = "API Gateway REST API ID"
}

output "api_gateway_url" {
  value       = "https://${aws_api_gateway_rest_api.mock.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.mock.stage_name}"
  description = "API Gateway endpoint URL"
}

output "waf_web_acl_id" {
  value       = aws_wafv2_web_acl.apigw.id
  description = "WAF Web ACL ID"
}

output "waf_web_acl_arn" {
  value       = aws_wafv2_web_acl.apigw.arn
  description = "WAF Web ACL ARN"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.mock.id
  description = "CloudFront distribution ID"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.mock.domain_name
  description = "CloudFront distribution domain name"
}

output "cloudfront_url" {
  value       = "https://${aws_cloudfront_distribution.mock.domain_name}"
  description = "CloudFront distribution URL (use this to test)"
}

output "waf_log_bucket_name" {
  value       = aws_s3_bucket.waf_logs.id
  description = "S3 bucket name for WAF logs (optional, for future use)"
}

output "waf_log_bucket_arn" {
  value       = aws_s3_bucket.waf_logs.arn
  description = "S3 bucket ARN for WAF logs (optional, for future use)"
}

output "waf_cloudwatch_log_group_name" {
  value       = aws_cloudwatch_log_group.waf_logs.name
  description = "CloudWatch Logs group name for WAF logs"
}

output "waf_cloudwatch_log_group_arn" {
  value       = aws_cloudwatch_log_group.waf_logs.arn
  description = "CloudWatch Logs group ARN for WAF logs"
}

output "cloudfront_log_bucket_name" {
  value       = aws_s3_bucket.cloudfront_logs.id
  description = "S3 bucket name for CloudFront access logs"
}

output "cloudfront_log_bucket_arn" {
  value       = aws_s3_bucket.cloudfront_logs.arn
  description = "S3 bucket ARN for CloudFront access logs"
}
