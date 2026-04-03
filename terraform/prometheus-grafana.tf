# =============================================================================
# PROMETHEUS-GRAFANA.TF - Monitoring Stack for EKS
# =============================================================================
# Cài đặt kube-prometheus-stack bao gồm:
# - Prometheus (thu thập metrics)
# - Grafana (visualization)
# - Alertmanager (alerting)
# - Node Exporter (node metrics)
# - Kube State Metrics (K8s metrics)
# =============================================================================

# =============================================================================
# HELM RELEASE - kube-prometheus-stack
# =============================================================================
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "56.0.0"

  create_namespace = true

  # =============================================================================
  # PROMETHEUS CONFIGURATION
  # =============================================================================
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }

  set {
    name  = "prometheus.prometheusSpec.scrapeInterval"
    value = "30s"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "50Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "2Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.cpu"
    value = "2000m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "4Gi"
  }

  # =============================================================================
  # GRAFANA CONFIGURATION
  # =============================================================================
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = "admin123"
  }

  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "grafana.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "grafana.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "grafana.resources.limits.memory"
    value = "512Mi"
  }

  # Grafana Ingress (optional - expose via ALB)
  set {
    name  = "grafana.ingress.enabled"
    value = "false"
  }

  # =============================================================================
  # ALERTMANAGER CONFIGURATION
  # =============================================================================
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage"
    value = "10Gi"
  }

  # =============================================================================
  # NODE EXPORTER (thu thập node metrics)
  # =============================================================================
  set {
    name  = "nodeExporter.enabled"
    value = "true"
  }

  # =============================================================================
  # KUBE STATE METRICS (thu thập K8s object metrics)
  # =============================================================================
  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  # =============================================================================
  # PROMETHEUS OPERATOR
  # =============================================================================
  set {
    name  = "prometheusOperator.enabled"
    value = "true"
  }

  depends_on = [
    module.eks,
    helm_release.metrics_server
  ]
}

