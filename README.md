# DevOps Final Project - Document Management System

Hệ thống quản lý tài liệu với kiến trúc microservices triển khai trên Amazon EKS.

## 🏗️ Kiến trúc

- **Frontend**: React + Vite + TailwindCSS
- **Backend**: Spring Boot + PostgreSQL
- **Infrastructure**: Amazon EKS (Kubernetes)
- **CI/CD**: GitHub Actions
- **Monitoring**: Prometheus + Grafana (planned)
- **Storage**: NFS Persistent Volume

## 📋 Yêu cầu

- AWS Account với IAM user có quyền tạo EKS, EC2, VPC
- AWS CLI đã cài đặt và cấu hình
- Terraform >= 1.7
- Ansible >= 2.9
- SSH key pair trên AWS
- Docker Hub account
- Domain name (optional, cho HTTPS)

## 🚀 Cài đặt nhanh

### 1. Clone repository

```bash
git clone <your-repo-url>
cd Devops-Final
```

### 2. Cấu hình môi trường

```bash
# Copy file .env.example thành .env
cp .env.example .env

# Chỉnh sửa file .env
nano .env
```

Điền các thông tin:
```bash
AWS_KEY_NAME=your-key-name-here    # Tên SSH key (không có .pem)
DB_PASSWORD=SecurePassword123!      # Password cho PostgreSQL

# Optional - Chỉ điền nếu có domain
DOMAIN_NAME=                        # VD: example.com
ENABLE_HTTPS=false                  # Đặt true khi có domain
```

### 3. Đặt file SSH key

Đảm bảo file `.pem` nằm trong thư mục gốc:
```bash
# VD: Devops_Final.pem
chmod 400 your-key-name.pem
```

### 4. Chạy setup tự động

```bash
chmod +x setup.sh
./setup.sh
```

Script sẽ tự động:
- Cài đặt Terraform, AWS CLI, Ansible (nếu chưa có)
- Tạo EKS cluster với managed node groups
- Tạo EC2 instances cho SonarQube, Database, NFS
- Cấu hình servers qua Ansible
- Hiển thị thông tin để cấu hình GitHub Actions

### 5. Cấu hình GitHub Actions Secrets

Vào GitHub repo → Settings → Secrets and variables → Actions → New repository secret

Thêm các secrets sau:
```
AWS_ACCESS_KEY_ID=<your-aws-access-key>
AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>
EKS_CLUSTER_NAME=<from-setup-output>
DATA_SERVER_IP=<from-setup-output>
SONAR_HOST_URL=http://<sonarqube-ip>:9000
SONAR_TOKEN=<generate-from-sonarqube>
DOCKER_USERNAME=<your-dockerhub-username>
DOCKER_PASSWORD=<your-dockerhub-password>
DB_PASSWORD=<same-as-env-file>
```

### 6. Deploy ứng dụng

```bash
# Push code lên GitHub để trigger CI/CD
git add .
git commit -m "Initial deployment"
git push origin main
```

## 🔒 HTTPS Configuration (Optional)

Nếu bạn có domain và muốn bật HTTPS:

### Bước 1: Chuẩn bị domain

1. Mua domain từ Namecheap, Hostinger, GoDaddy, etc.
2. Tạo Hosted Zone trên AWS Route53:
   ```bash
   aws route53 create-hosted-zone --name your-domain.com --caller-reference $(date +%s)
   ```
3. Lấy nameservers từ Route53 và cập nhật ở domain registrar

### Bước 2: Bật HTTPS trong Terraform

Cập nhật file `.env`:
```bash
DOMAIN_NAME=your-domain.com
ENABLE_HTTPS=true
```

Chạy lại setup:
```bash
./setup.sh
```

⏳ **Lưu ý**: Certificate validation có thể mất 5-15 phút cho DNS propagation.

### Bước 3: Cập nhật Kubernetes Ingress

Sau khi Terraform hoàn tất, lấy Certificate ARN từ output:
```bash
cd terraform
terraform output https_certificate_arn
```

Cập nhật `kubernetes/ingress.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: devops-final
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: 'arn:aws:acm:...'  # Thêm dòng này
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'  # Thêm dòng này
    alb.ingress.kubernetes.io/ssl-redirect: '443'  # Optional: redirect HTTP -> HTTPS
spec:
  ingressClassName: alb
  rules:
    - host: app.your-domain.com  # Thay đổi từ * thành domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 8080
```

Apply changes:
```bash
kubectl apply -f kubernetes/ingress.yaml
```

### Bước 4: Tạo DNS record

Lấy ALB URL:
```bash
kubectl get ingress -n devops-final
```

Tạo CNAME record trên Route53:
```bash
# Hoặc qua AWS Console
# Record name: app
# Record type: CNAME
# Value: <ALB-URL>
```

Truy cập: `https://app.your-domain.com` 🔒

## 📊 Monitoring (Planned)

- Prometheus: Metrics collection
- Grafana: Visualization dashboards
- AlertManager: Alert notifications

## 🧪 Testing

### Test Horizontal Pod Autoscaling

```bash
# Tạo load generator pod
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh

# Trong pod, chạy:
while true; do wget -q -O- http://backend.devops-final.svc.cluster.local:8080/api/documents; done

# Xem HPA scaling (terminal khác):
kubectl get hpa -n devops-final -w
```

### Test Self-healing

```bash
# Xóa một pod
kubectl delete pod <pod-name> -n devops-final

# Kubernetes sẽ tự động tạo pod mới
kubectl get pods -n devops-final -w
```

## 🗑️ Cleanup

```bash
# Xóa Kubernetes resources
kubectl delete namespace devops-final

# Xóa infrastructure
cd terraform
terraform destroy -var="key_name=$AWS_KEY_NAME"
```

## 📝 Troubleshooting

### Pod không start

```bash
# Xem logs
kubectl logs -l app=backend -n devops-final --tail=100

# Xem events
kubectl describe pod <pod-name> -n devops-final
```

### Database connection failed

```bash
# SSH vào DB server
ssh -i your-key.pem ubuntu@<DB_PUBLIC_IP>

# Check PostgreSQL
sudo systemctl status postgresql
sudo -u postgres psql -c "\l"
```

### NFS mount failed

```bash
# SSH vào DB server
ssh -i your-key.pem ubuntu@<DB_PUBLIC_IP>

# Check NFS
sudo systemctl status nfs-kernel-server
sudo exportfs -v
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## 📄 License

This project is for educational purposes (DevOps Final Exam).

## 👥 Authors

- Your Name - DevOps Engineer

## 🙏 Acknowledgments

- AWS Documentation
- Kubernetes Documentation
- Terraform AWS Provider
- Spring Boot Documentation
