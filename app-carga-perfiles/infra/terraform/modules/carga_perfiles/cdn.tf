locals {
  origen_connect = "https://${var.connect_instance_alias}.my.connect.aws"
  host_oidc      = regex("^https://[^/]+", var.oidc_issuer)
  host_cargas    = "https://${aws_s3_bucket.cargas.bucket}.s3.${local.region}.amazonaws.com"
  csp = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    # Cloudscape inyecta estilos en linea.
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self' data:",
    "connect-src 'self' ${local.host_oidc} ${local.host_cargas}",
    "frame-src ${local.host_oidc}",
    # Solo el sitio de la instancia de Connect puede embeber la app.
    "frame-ancestors 'self' ${local.origen_connect} https://${var.connect_instance_alias}.awsapps.com",
    "base-uri 'self'",
    "form-action 'self' ${local.host_oidc}",
  ])
}

resource "aws_cloudfront_origin_access_control" "sitio" {
  name                              = "${local.prefijo}-sitio"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "seguridad" {
  name = "${local.prefijo}-seguridad"
  security_headers_config {
    content_security_policy {
      content_security_policy = local.csp
      override                = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    # Sin X-Frame-Options: la app se embebe en Connect; lo controla frame-ancestors.
  }
}

# SPA: rutas sin extension sirven index.html. No se usan error pages globales para no tapar errores de /api.
resource "aws_cloudfront_function" "spa" {
  name    = "${local.prefijo}-spa"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var req = event.request;
      if (!req.uri.includes('.')) { req.uri = '/index.html'; }
      return req;
    }
  JS
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  comment             = "Diners carga de perfiles (${var.ambiente})"
  default_root_object = "index.html"
  http_version        = "http2and3"
  price_class         = "PriceClass_100"
  tags                = local.tags

  origin {
    origin_id                = "sitio"
    domain_name              = aws_s3_bucket.sitio.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.sitio.id
  }

  origin {
    origin_id   = "api"
    domain_name = replace(aws_apigatewayv2_api.app.api_endpoint, "https://", "")
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = "sitio"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.seguridad.id
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id   = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
    response_headers_policy_id = aws_cloudfront_response_headers_policy.seguridad.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
