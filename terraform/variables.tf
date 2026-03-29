# =============================================================================
# VARIABLES.TF - Khai báo biến số cho Infrastructure
# =============================================================================

# Biến BẮT BUỘC người dùng cung cấp (qua -var hoặc TF_VAR_)
variable "key_name" {
  description = "Tên khóa SSH (.pem) trên AWS"
  type        = string
}

# Các giá trị MẶC ĐỊNH - không cần thay đổi
variable "aws_region" {
  description = "Khu vực triển khai AWS"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type_k8s" {
  description = "Cấu hình máy chủ K8s Master"
  type        = string
  default     = "c7i-flex.large"
}

variable "instance_type_sonarqube" {
  description = "Cấu hình máy chủ SonarQube"
  type        = string
  default     = "c7i-flex.large"
}

variable "project_name" {
  description = "Tên dự án"
  type        = string
  default     = "devops-final"
}

variable "environment" {
  description = "Môi trường triển khai"
  type        = string
  default     = "production"
}
