# =============================================================================
# OUTPUTS.TF - Xuất thông tin sau khi triển khai
# =============================================================================
# Hiển thị các IP và thông tin cần thiết để tiếp tục cấu hình
# =============================================================================

# ==========================================
# KUBERNETES MASTER NODE
# ==========================================
output "k8s_master_public_ip" {
  description = "Elastic IP của K8s Master Node (IP cố định)"
  value       = aws_eip.k8s_eip.public_ip
}

output "k8s_master_instance_id" {
  description = "Instance ID của K8s Master"
  value       = aws_instance.k8s_master.id
}

output "k8s_master_private_ip" {
  description = "Private IP của K8s Master"
  value       = aws_instance.k8s_master.private_ip
}

# ==========================================
# SONARQUBE SERVER
# ==========================================
output "sonarqube_public_ip" {
  description = "Elastic IP của SonarQube Server (IP cố định)"
  value       = aws_eip.sonarqube_eip.public_ip
}

output "sonarqube_instance_id" {
  description = "Instance ID của SonarQube"
  value       = aws_instance.sonarqube.id
}

output "sonarqube_url" {
  description = "URL truy cập SonarQube Web UI"
  value       = "http://${aws_eip.sonarqube_eip.public_ip}:9000"
}

# ==========================================
# SSH COMMANDS
# ==========================================
output "ssh_command_k8s" {
  description = "Lệnh SSH vào K8s Master"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.k8s_eip.public_ip}"
}

output "ssh_command_sonarqube" {
  description = "Lệnh SSH vào SonarQube Server"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.sonarqube_eip.public_ip}"
}

# ==========================================
# SUMMARY
# ==========================================
output "deployment_summary" {
  description = "Tóm tắt thông tin triển khai"
  value = <<-EOT
    
    ============================================
    🚀 DEVOPS FINAL - INFRASTRUCTURE DEPLOYED
    ============================================
    
    📦 K8s Master Node:
       - Public IP:  ${aws_eip.k8s_eip.public_ip}
       - Private IP: ${aws_instance.k8s_master.private_ip}
       - SSH: ssh -i ${var.key_name}.pem ubuntu@${aws_eip.k8s_eip.public_ip}
    
    🔍 SonarQube Server:
       - Public IP:  ${aws_eip.sonarqube_eip.public_ip}
       - URL: http://${aws_eip.sonarqube_eip.public_ip}:9000
       - Default login: admin / admin
       - SSH: ssh -i ${var.key_name}.pem ubuntu@${aws_eip.sonarqube_eip.public_ip}
    
    ⏳ Lưu ý: SonarQube cần 2-3 phút để khởi động hoàn tất!
    
    ============================================
    EOT
}
