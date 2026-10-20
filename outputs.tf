output "bucket_name" {
  value = aws_s3_bucket.reportes.bucket
}

output "lambda_name" {
  value = aws_lambda_function.auditor.function_name
}