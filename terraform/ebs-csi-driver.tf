# =============================================================================
# EBS-CSI-DRIVER.TF - AWS EBS CSI Driver for EKS
# =============================================================================
# Required for PersistentVolumes to work on Kubernetes 1.23+
# The old in-tree provisioner (kubernetes.io/aws-ebs) is deprecated
# =============================================================================

# =============================================================================
# IAM ROLE - Service Account for EBS CSI Driver
# =============================================================================
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Name        = "${var.cluster_name}-ebs-csi-driver-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# =============================================================================
# DATA SOURCE - Get latest EBS CSI Driver version
# =============================================================================
data "aws_eks_addon_version" "ebs_csi_driver" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

# =============================================================================
# EKS ADDON - AWS EBS CSI Driver
# =============================================================================
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi_driver.version
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn

  # Resolve conflicts by overwriting
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name        = "${var.cluster_name}-ebs-csi-driver"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [
    module.eks,
    module.ebs_csi_driver_irsa
  ]
}

# =============================================================================
# STORAGECLASS - gp3 (Modern, faster, cheaper than gp2)
# =============================================================================
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [
    aws_eks_addon.ebs_csi_driver
  ]
}
