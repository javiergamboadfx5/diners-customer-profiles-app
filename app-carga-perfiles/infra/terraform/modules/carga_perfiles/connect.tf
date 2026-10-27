# Registro de la app como integracion de Amazon Connect (tipo Standard application).
# La pagina del workspace y la view se configuran en el admin website (UI Management > Workspaces).

resource "awscc_appintegrations_application" "app" {
  count       = var.connect_instance_arn == "" ? 0 : 1
  name        = local.prefijo
  namespace   = local.prefijo
  description = "Carga y validación de la base de socios en Customer Profiles."
  application_source_config = {
    external_url_config = {
      access_url       = "https://${aws_cloudfront_distribution.app.domain_name}"
      approved_origins = ["https://${aws_cloudfront_distribution.app.domain_name}"]
    }
  }
}

resource "awscc_connect_integration_association" "app" {
  count            = var.connect_instance_arn == "" ? 0 : 1
  instance_id      = var.connect_instance_arn
  integration_type = "APPLICATION"
  integration_arn  = awscc_appintegrations_application.app[0].application_arn
}

# ---------- Alarmas ----------

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.prefijo}-escritura-dlq"
  alarm_description   = "Hay lotes de perfiles que no se pudieron escribir tras 8 intentos. La carga queda en 'escribiendo'."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_alarmas_arn == "" ? [] : [var.sns_alarmas_arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "errores" {
  for_each            = toset(["api", "validador", "encolador", "escritor"])
  alarm_name          = "${local.prefijo}-${each.key}-errores"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn[each.key].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_alarmas_arn == "" ? [] : [var.sns_alarmas_arn]
  tags                = local.tags
}
