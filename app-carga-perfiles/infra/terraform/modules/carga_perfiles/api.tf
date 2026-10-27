resource "aws_apigatewayv2_api" "app" {
  name          = local.prefijo
  protocol_type = "HTTP"
  description   = "API de la app de carga de perfiles. Se consume via CloudFront (/api/*)."
  tags          = local.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.app.id
  name             = "oidc"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    issuer   = var.oidc_issuer
    audience = var.oidc_audiences
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.fn["api"].invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

locals {
  rutas = [
    "GET /api/cargas",
    "POST /api/cargas",
    "GET /api/cargas/{id}",
    "GET /api/cargas/{id}/{recurso}",
    "POST /api/cargas/{id}/{accion}",
    "GET /api/esquema",
    "PUT /api/esquema",
  ]
}

resource "aws_apigatewayv2_route" "app" {
  for_each           = toset(local.rutas)
  api_id             = aws_apigatewayv2_api.app.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.prefijo}"
  retention_in_days = var.dias_retencion_logs
  tags              = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 20
  }
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      usuario   = "$context.authorizer.claims.preferred_username"
      ruta      = "$context.routeKey"
      status    = "$context.status"
      latencia  = "$context.responseLatency"
      error     = "$context.authorizer.error"
    })
  }
  tags = local.tags
}

resource "aws_lambda_permission" "api" {
  statement_id  = "ApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["api"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app.execution_arn}/*/*"
}
