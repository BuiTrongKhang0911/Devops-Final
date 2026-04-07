# =============================================================================
# OUTPUTS.TF - Xuất thông tin sau khi triển khai
# =============================================================================

# ==========================================
# VPC INFORMATION
# ==========================================
output "vpc_id" {
  description = "ID của VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block của VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "IDs của Public Subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "IDs của Private Subnets"
  value       = module.vpc.private_subnets
}

# ==========================================
# EKS CLUSTER INFORMATION
# ==========================================
output "eks_cluster_name" {
  description = "Tên EKS Cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint của EKS Cluster"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Phiên bản Kubernetes"
  value       = module.eks.cluster_version
}

output "eks_cluster_security_group_id" {
  description = "Security Group ID của EKS Cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "Security Group ID của EKS Worker Nodes"
  value       = module.eks.node_security_group_id
}

output "eks_oidc_provider_arn" {
  description = "ARN của OIDC Provider (dùng cho AWS Load Balancer Controller)"
  value       = module.eks.oidc_provider_arn
}

# ==========================================
# KUBECONFIG COMMAND
# ==========================================
output "kubeconfig_command" {
  description = "Lệnh để cấu hình kubectl kết nối với EKS cluster"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

# ==========================================
# SONARQUBE SERVER
# ==========================================
output "sonarqube_public_ip" {
  description = "Public IP của SonarQube Server"
  value       = aws_eip.sonarqube_eip.public_ip
}

output "sonarqube_private_ip" {
  description = "Private IP của SonarQube Server"
  value       = aws_instance.sonarqube.private_ip
}

output "sonarqube_instance_id" {
  description = "Instance ID của SonarQube"
  value       = aws_instance.sonarqube.id
}

# ==========================================
# DATABASE + NFS SERVER
# ==========================================
output "db_nfs_public_ip" {
  description = "Public IP của Database + NFS Server"
  value       = aws_eip.db_nfs_eip.public_ip
}

output "db_nfs_private_ip" {
  description = "Private IP của Database + NFS Server (dùng cho cấu hình NFS)"
  value       = aws_instance.db_nfs.private_ip
}

output "db_nfs_instance_id" {
  description = "Instance ID của DB + NFS Server"
  value       = aws_instance.db_nfs.id
}

# ==========================================
# SSH COMMANDS
# ==========================================
output "ssh_sonarqube" {
  description = "Lệnh SSH vào SonarQube Server"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.sonarqube_eip.public_ip}"
}

output "ssh_db_nfs" {
  description = "Lệnh SSH vào Database + NFS Server"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.db_nfs_eip.public_ip}"
}

# ==========================================
# DEPLOYMENT SUMMARY
# ==========================================
output "deployment_summary" {
  description = "Tóm tắt thông tin triển khai"
  value = <<-EOT
    
    ============================================
    🚀 DEVOPS FINAL - EKS INFRASTRUCTURE DEPLOYED
    ============================================
    
    📦 EKS CLUSTER:
       - Cluster Name: ${module.eks.cluster_name}
       - Kubernetes Version: ${module.eks.cluster_version}
       - Endpoint: ${module.eks.cluster_endpoint}
       - OIDC Provider: ${module.eks.oidc_provider_arn}
       
       🔧 Kết nối kubectl:
       aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}
    
    🔍 SONARQUBE SERVER:
       - Public IP:  ${aws_eip.sonarqube_eip.public_ip}
       - Private IP: ${aws_instance.sonarqube.private_ip}
       - URL: http://${aws_eip.sonarqube_eip.public_ip}:9000
       - Default login: admin / admin
       - SSH: ssh -i ${var.key_name}.pem ubuntu@${aws_eip.sonarqube_eip.public_ip}
    
    💾 DATABASE + NFS SERVER:
       - Public IP:  ${aws_eip.db_nfs_eip.public_ip}
       - Private IP: ${aws_instance.db_nfs.private_ip}
       - SSH: ssh -i ${var.key_name}.pem ubuntu@${aws_eip.db_nfs_eip.public_ip}
       
       ⚠️  Cần chạy Ansible để cài PostgreSQL và NFS!
    
    🌐 VPC INFORMATION:
       - VPC ID: ${module.vpc.vpc_id}
       - CIDR: ${module.vpc.vpc_cidr_block}
       - Public Subnets: ${join(", ", module.vpc.public_subnets)}
       - Private Subnets: ${join(", ", module.vpc.private_subnets)}
    
    ⏳ Lưu ý:
       - SonarQube cần 2-3 phút để khởi động
       - EKS cluster cần 10-15 phút để hoàn tất
       - Chạy kubeconfig command ở trên để kết nối kubectl
    
    ============================================
    EOT
}

# ==========================================
# ANSIBLE INVENTORY HELPER
# ==========================================
output "ansible_inventory_snippet" {
  description = "Snippet để thêm vào Ansible inventory"
  value = <<-EOT
    
    # Thêm vào ansible/inventory/hosts.ini:
    
    [sonarqube]
    sonarqube ansible_host=${aws_eip.sonarqube_eip.public_ip} ansible_user=ubuntu
    
    [database]
    db-nfs ansible_host=${aws_eip.db_nfs_eip.public_ip} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3
    
    [nfs_server]
    db-nfs ansible_host=${aws_eip.db_nfs_eip.public_ip} ansible_user=ubuntu
    
    # Private IP cho cấu hình NFS mount trong K8s:
    # NFS_SERVER_IP=${aws_instance.db_nfs.private_ip}
    
    EOT
}

# ==========================================
# MONITORING STACK
# ==========================================
output "monitoring_info" {
  description = "Monitoring stack access information"
  value = {
    prometheus_url = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    grafana_url    = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    grafana_user   = "admin"
    grafana_pass   = "admin123"
    namespace      = "monitoring"
    message        = "✅ Monitoring stack installed - Use port-forward to access"
  }
}
