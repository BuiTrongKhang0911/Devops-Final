# =============================================================================
# ACM-ROUTE53.TF - HTTPS Certificate Configuration (OPTIONAL)
# =============================================================================
# Mục đích:
#   - Tự động xin chứng chỉ SSL/TLS từ AWS Certificate Manager (ACM)
#   - Tự động validate qua DNS trên Route53
#   - Chỉ tạo khi enable_https = true và domain_name được cung cấp
#
# Yêu cầu:
#   1. Domain đã được mua
#   2. Hosted Zone đã được tạo trên Route53
#   3. Nameserver của domain đã trỏ về Route53
#
# Sử dụng:
#   - Cập nhật .env: DOMAIN_NAME=your-domain.com, ENABLE_HTTPS=true
#   - Chạy: ./setup.sh
#   - Lấy certificate ARN từ output và cập nhật kubernetes/ingress.yaml
# =============================================================================

locals {
  # Chỉ tạo HTTPS resources khi cả 2 điều kiện đều đúng
  create_https = var.enable_https && var.domain_name != ""
}

# =============================================================================
# DATA SOURCE: Tìm Hosted Zone trên Route53
# =============================================================================
data "aws_route53_zone" "domain" {
  count = local.create_https ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

# =============================================================================
# ACM CERTIFICATE: Xin chứng chỉ SSL/TLS
# =============================================================================
resource "aws_acm_certificate" "cert" {
  count = local.create_https ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-https-cert"
    Environment = var.environment
    Domain      = var.domain_name
  }
}

# =============================================================================
# ROUTE53 RECORDS: Tự động tạo DNS records để validate certificate
# =============================================================================
resource "aws_route53_record" "cert_validation" {
  for_each = local.create_https ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain[0].zone_id
}

# =============================================================================
# CERTIFICATE VALIDATION: Đợi certificate được AWS validate
# =============================================================================
resource "aws_acm_certificate_validation" "cert" {
  count = local.create_https ? 1 : 0

  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "15m" # Đợi tối đa 15 phút cho DNS propagation
  }
}

# =============================================================================
# DNS RECORD FOR SONARQUBE (sonar.domain.com)
# =============================================================================
resource "aws_route53_record" "sonarqube_dns" {
  count = local.create_https ? 1 : 0

  zone_id = data.aws_route53_zone.domain[0].zone_id
  name    = "sonar"
  type    = "A"
  ttl     = 300
  records = [aws_eip.sonarqube_eip.public_ip]

  depends_on = [aws_eip.sonarqube_eip]
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "https_certificate_arn" {
  description = "ARN của HTTPS certificate (dùng trong Kubernetes Ingress annotation)"
  value       = local.create_https ? aws_acm_certificate.cert[0].arn : "N/A - HTTPS not enabled"
}

output "https_status" {
  description = "Trạng thái HTTPS configuration"
  value = local.create_https ? {
    enabled     = true
    domain      = var.domain_name
    wildcard    = "*.${var.domain_name}"
    cert_arn    = aws_acm_certificate.cert[0].arn
    hosted_zone = data.aws_route53_zone.domain[0].zone_id
    message     = "✅ HTTPS enabled - Certificate ARN ready for Ingress"
    } : {
    enabled = false
    message = "⚠️  HTTPS disabled - Set ENABLE_HTTPS=true and DOMAIN_NAME in .env to enable"
  }
}

output "route53_nameservers" {
  description = "Route53 nameservers (cần cập nhật ở domain registrar)"
  value       = local.create_https ? data.aws_route53_zone.domain[0].name_servers : []
}

output "sonarqube_url" {
  description = "SonarQube URL"
  value = local.create_https ? "https://sonar.${var.domain_name}" : "http://${aws_eip.sonarqube_eip.public_ip}:9000"
}
