data "archive_file" "backend" {
  type        = "zip"
  source_dir  = "${local.raiz_app}/backend/src"
  output_path = "${path.root}/.build/backend.zip"
  excludes    = ["**/__pycache__/**"]
}

locals {
  funciones = {
    api       = { handler = "carga.api.handler", memoria = 512, timeout = 29 }
    validador = { handler = "carga.procesos.validador", memoria = 2048, timeout = 900 }
    encolador = { handler = "carga.procesos.encolador", memoria = 1024, timeout = 900 }
    escritor  = { handler = "carga.procesos.escritor", memoria = 256, timeout = 120 }
  }
  entorno_lambda = {
    TABLA             = aws_dynamodb_table.app.name
    BUCKET_CARGAS     = aws_s3_bucket.cargas.id
    COLA_ESCRITURA    = aws_sqs_queue.escritura.url
    DOMINIO_PERFILES  = local.dominio
    OBJECT_TYPE       = awscc_customerprofiles_object_type.socio.object_type_name
    FUNCION_ENCOLADOR = "${local.prefijo}-encolador"
    GRUPOS_CARGA      = join(",", var.grupos_carga)
    GRUPOS_ADMIN      = join(",", var.grupos_admin)
  }
}

resource "aws_iam_role" "lambda" {
  name = "${local.prefijo}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.cuenta } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "app"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for k, _ in local.funciones : "${aws_cloudwatch_log_group.fn[k].arn}:*"]
      },
      {
        Sid      = "Tabla"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = [aws_dynamodb_table.app.arn, "${aws_dynamodb_table.app.arn}/index/*"]
      },
      {
        Sid      = "Archivos"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.cargas.arn}/cargas/*"
      },
      {
        Sid      = "Cola"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
        Resource = aws_sqs_queue.escritura.arn
      },
      {
        Sid      = "Cifrado"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:Encrypt"]
        Resource = aws_kms_key.app.arn
      },
      {
        Sid      = "Encolador"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${local.region}:${local.cuenta}:function:${local.prefijo}-encolador"
      },
      {
        Sid      = "CustomerProfiles"
        Effect   = "Allow"
        Action   = ["profile:PutProfileObject"]
        Resource = ["${local.dominio_arn}/object-types/${var.object_type_name}", local.dominio_arn]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.funciones
  name              = "/aws/lambda/${local.prefijo}-${each.key}"
  retention_in_days = var.dias_retencion_logs
  tags              = local.tags
}

resource "aws_lambda_function" "fn" {
  for_each         = local.funciones
  function_name    = "${local.prefijo}-${each.key}"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = each.value.handler
  memory_size      = each.value.memoria
  timeout          = each.value.timeout
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  environment {
    variables = local.entorno_lambda
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.fn[each.key].name
  }
  tracing_config {
    mode = "Active"
  }
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_permission" "s3_validador" {
  statement_id   = "S3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.fn["validador"].function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.cargas.arn
  source_account = local.cuenta
}

resource "aws_lambda_event_source_mapping" "escritor" {
  event_source_arn        = aws_sqs_queue.escritura.arn
  function_name           = aws_lambda_function.fn["escritor"].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config {
    maximum_concurrency = var.concurrencia_escritura
  }
}
