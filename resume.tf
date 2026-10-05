provider "aws" {
  region = "us-east-1"
}

# 1. S3 Bucket Banayein
resource "aws_s3_bucket" "resume_bucket" {
  bucket = "navneet-cloud-resume-bucket-2026" 
}

# 2. Bucket ko Website Mode me Dalein
resource "aws_s3_bucket_website_configuration" "resume_site" {
  bucket = aws_s3_bucket.resume_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# 3. Public Access Block settings hatayein
resource "aws_s3_bucket_public_access_block" "public_check" {
  bucket = aws_s3_bucket.resume_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Bucket Policy lagayein taki public ise read kar sake
resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.resume_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.public_check]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.resume_bucket.arn}/*"
      }
    ]
  })
}

# 5. DynamoDB Table - Visitor Count Store Karne Ke Liye
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "resume-visitor-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "Resume-Database"
  }
}

# 6. Initial Data Insert
resource "aws_dynamodb_table_item" "init_item" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key   = aws_dynamodb_table.visitor_counter.hash_key

  item = <<ITEM
{
  "id": {"S": "visitors"},
  "count": {"N": "0"}
}
ITEM
}

# 7. INLINE PYTHON COMPRESSION (No manual directory dependencies)
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<EOF
import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('resume-visitor-counter')

def lambda_handler(event, context):
    response = table.update_item(
        Key={'id': 'visitors'},
        UpdateExpression='ADD #c :val',
        ExpressionAttributeNames={'#c': 'count'},
        ExpressionAttributeValues={':val': 1},
        ReturnValues="UPDATED_NEW"
    )
    updated_count = int(response['Attributes']['count'])
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps({'count': updated_count})
    }
EOF
    filename = "func.py"
  }
}

# 8. Lambda Function Create Karein
resource "aws_lambda_function" "resume_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "resume-visitor-counter-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "func.lambda_handler"
  runtime          = "python3.11"
}

# 9. IAM Role 
resource "aws_iam_role" "lambda_role" {
  name = "resume-lambda-db-role-final-v3"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# 10. IAM Policy Connect Karein
resource "aws_iam_role_policy" "lambda_policy" {
  name = "resume-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 11. API Gateway
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "resume-counter-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

# 12. API Gateway Aur Lambda Integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.lambda_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.resume_counter.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# 13. Route Define Karein
resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "GET /counter"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# 14. API Ko Deploy Karein Live Stage Me
resource "aws_apigatewayv2_stage" "lambda_stage" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "$default"
  auto_deploy = true
}

# 15. API Gateway Ko Permission Dein Lambda Ko Trigger Karne Ki
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# 16. Outputs
output "s3_website_endpoint" {
  value = aws_s3_bucket_website_configuration.resume_site.website_endpoint
}

output "api_url" {
  value       = "${aws_apigatewayv2_api.lambda_api.api_endpoint}/counter"
  description = "Aapke counter API ka web endpoint link"
}
