#!/bin/bash
# =============================================================================
# SETUP.SH - Automated EKS Infrastructure & Configuration Setup
# =============================================================================
# Chạy: chmod +x setup.sh && ./setup.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=============================================${NC}\n${BLUE}$1${NC}\n${BLUE}=============================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }

# =============================================================================
# INSTALL PREREQUISITES
# =============================================================================
print_header "1. Kiểm tra & Cài đặt Prerequisites"

NEED_INSTALL=false

# --- Check Terraform ---
if command -v terraform &> /dev/null; then
    print_success "Terraform: $(terraform version | head -n1)"
else
    print_warning "Terraform chưa được cài đặt. Đang cài đặt..."
    NEED_INSTALL=true
    
    sudo apt-get update -qq
    sudo apt-get install -y unzip wget
    
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
    unzip -o -q terraform_1.7.5_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm -f terraform_1.7.5_linux_amd64.zip
    cd - > /dev/null
    
    print_success "Terraform đã cài đặt: $(terraform version | head -n1)"
fi

# --- Check AWS CLI ---
if command -v aws &> /dev/null; then
    print_success "AWS CLI: $(aws --version | cut -d' ' -f1)"
else
    print_warning "AWS CLI chưa được cài đặt. Đang cài đặt..."
    NEED_INSTALL=true
    
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    cd /tmp
    unzip -q -o awscliv2.zip
    sudo ./aws/install --update
    cd - > /dev/null
    rm -rf /tmp/awscliv2.zip /tmp/aws
    
    print_success "AWS CLI đã cài đặt: $(aws --version | cut -d' ' -f1)"
fi

# --- Check Ansible ---
if command -v ansible &> /dev/null; then
    print_success "Ansible: $(ansible --version | head -n1)"
else
    print_warning "Ansible chưa được cài đặt. Đang cài đặt..."
    NEED_INSTALL=true
    
    sudo apt-get update -qq
    sudo apt-get install -y ansible
    
    print_success "Ansible đã cài đặt: $(ansible --version | head -n1)"
fi

if [ "$NEED_INSTALL" = true ]; then
    echo ""
    print_success "Tất cả prerequisites đã được cài đặt!"
fi

# =============================================================================
# CHECK AWS CREDENTIALS
# =============================================================================
print_header "2. Kiểm tra AWS Credentials"

if aws sts get-caller-identity &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
    AWS_USER=$(aws sts get-caller-identity --query "Arn" --output text | rev | cut -d'/' -f1 | rev)
    AWS_REGION=$(aws configure get region || echo "ap-southeast-1")
    print_success "AWS Account: $AWS_ACCOUNT"
    print_success "AWS User/Role: $AWS_USER"
    print_success "AWS Region: $AWS_REGION"
else
    print_error "AWS credentials chưa được cấu hình!"
    echo ""
    echo -e "${YELLOW}Bạn cần cấu hình AWS credentials trước khi tiếp tục.${NC}"
    echo ""
    echo "Cách 1 - Chạy aws configure:"
    echo "  aws configure"
    echo ""
    echo "Cách 2 - Export environment variables:"
    echo "  export AWS_ACCESS_KEY_ID=your_access_key"
    echo "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "  export AWS_DEFAULT_REGION=ap-southeast-1"
    echo ""
    exit 1
fi

# =============================================================================
# LOAD .ENV FILE
# =============================================================================
print_header "3. Đọc cấu hình từ .env"

if [ ! -f ".env" ]; then
    print_error "Không tìm thấy file .env!"
    echo ""
    echo "Tạo file .env từ template..."
    cp .env.example .env
    echo ""
    print_warning "Vui lòng chỉnh sửa file .env và điền AWS_KEY_NAME!"
    echo "Sau đó chạy lại: ./setup.sh"
    exit 1
fi

# Load .env
export $(grep -v '^#' .env | grep -v '^\s*$' | xargs)

# Validate required vars
if [ -z "$AWS_KEY_NAME" ] || [ "$AWS_KEY_NAME" = "your-key-name-here" ]; then
    print_error "AWS_KEY_NAME chưa được cấu hình trong .env"
    echo "Mở file .env và điền tên SSH key của bạn (không có đuôi .pem)"
    exit 1
fi

# Set default DB_PASSWORD if not provided
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD="SecurePassword123!"
    print_warning "DB_PASSWORD không có trong .env, dùng mặc định: $DB_PASSWORD"
fi

# Set default HTTPS configuration
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME=""
fi

if [ -z "$ENABLE_HTTPS" ]; then
    ENABLE_HTTPS="false"
fi

print_success "AWS_KEY_NAME: $AWS_KEY_NAME"
print_success "DB_PASSWORD: ${DB_PASSWORD:0:3}***${DB_PASSWORD: -3}"

# Display HTTPS status
if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
    print_success "HTTPS: Enabled for $DOMAIN_NAME"
else
    print_info "HTTPS: Disabled (App will use HTTP only)"
fi

# Check SSH key file
SSH_KEY_PATH="${AWS_KEY_NAME}.pem"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_error "Không tìm thấy SSH key: $SSH_KEY_PATH"
    echo "Đảm bảo file .pem nằm trong thư mục gốc project"
    exit 1
fi

# Fix permission cho SSH key
chmod 400 "$SSH_KEY_PATH"
print_success "SSH Key: $SSH_KEY_PATH (permission 400)"

# =============================================================================
# TERRAFORM - DEPLOY INFRASTRUCTURE
# =============================================================================
print_header "4. Terraform - Deploy EKS Infrastructure"

cd terraform

print_info "Initializing Terraform..."
terraform init -upgrade

print_info "Planning infrastructure..."
terraform plan \
  -var="key_name=$AWS_KEY_NAME" \
  -var="domain_name=$DOMAIN_NAME" \
  -var="enable_https=$ENABLE_HTTPS" \
  -out=tfplan

echo ""
read -p "Tiếp tục apply infrastructure? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Hủy deployment"
    exit 0
fi

print_info "Applying infrastructure... (15-20 phút)"
if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
    print_warning "HTTPS enabled - Certificate validation có thể mất 5-15 phút"
    print_info "Đảm bảo domain nameserver đã trỏ về Route53!"
fi
terraform apply tfplan

# Get outputs
print_info "Lấy thông tin từ Terraform outputs..."

if ! EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null); then
    print_error "Không lấy được Terraform outputs. Kiểm tra lại terraform apply!"
    exit 1
fi

EKS_CLUSTER_ENDPOINT=$(terraform output -raw eks_cluster_endpoint)
SONARQUBE_PUBLIC_IP=$(terraform output -raw sonarqube_public_ip)
SONARQUBE_PRIVATE_IP=$(terraform output -raw sonarqube_private_ip)
DB_NFS_PUBLIC_IP=$(terraform output -raw db_nfs_public_ip)
DB_NFS_PRIVATE_IP=$(terraform output -raw db_nfs_private_ip)
EKS_OIDC_PROVIDER_ARN=$(terraform output -raw eks_oidc_provider_arn)
KUBECONFIG_COMMAND=$(terraform output -raw kubeconfig_command)

# Get HTTPS outputs if enabled
if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
    HTTPS_CERT_ARN=$(terraform output -raw https_certificate_arn 2>/dev/null || echo "N/A")
else
    HTTPS_CERT_ARN="N/A - HTTPS not enabled"
fi

print_success "EKS Cluster: $EKS_CLUSTER_NAME"
print_success "SonarQube IP: $SONARQUBE_PUBLIC_IP"
print_success "DB+NFS IP: $DB_NFS_PUBLIC_IP"

if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
    print_success "HTTPS Certificate: Ready"
fi

cd ..

# =============================================================================
# GENERATE ANSIBLE INVENTORY
# =============================================================================
print_header "5. Tạo Ansible Inventory"

SSH_KEY_ABSOLUTE_PATH="$(pwd)/${SSH_KEY_PATH}"

cat > ansible/inventory/hosts.ini << EOF
# Auto-generated by setup.sh at $(date)

[sonarqube]
sonarqube ansible_host=${SONARQUBE_PUBLIC_IP} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3

[database]
db-nfs ansible_host=${DB_NFS_PUBLIC_IP} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3

[nfs_server]
db-nfs ansible_host=${DB_NFS_PUBLIC_IP} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3

[all:vars]
ansible_ssh_private_key_file=${SSH_KEY_ABSOLUTE_PATH}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# Private IPs for K8s configuration
# DB_PRIVATE_IP=${DB_NFS_PRIVATE_IP}
# NFS_SERVER_IP=${DB_NFS_PRIVATE_IP}
EOF

print_success "Ansible inventory created"

# =============================================================================
# WAIT FOR SSH
# =============================================================================
print_header "6. Đợi EC2 instances sẵn sàng"

print_info "Waiting for SSH to be ready (max 20s per server)..."

# Wait for SonarQube
for i in {1..4}; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i "$SSH_KEY_PATH" ubuntu@"$SONARQUBE_PUBLIC_IP" "echo 'OK'" &>/dev/null; then
        print_success "SonarQube server SSH ready!"
        break
    fi
    [ $i -lt 4 ] && sleep 5
done

# Wait for DB+NFS
for i in {1..4}; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i "$SSH_KEY_PATH" ubuntu@"$DB_NFS_PUBLIC_IP" "echo 'OK'" &>/dev/null; then
        print_success "DB+NFS server SSH ready!"
        break
    fi
    [ $i -lt 4 ] && sleep 5
done

# =============================================================================
# RUN ANSIBLE
# =============================================================================
print_header "7. Ansible - Cấu hình Servers"

cd ansible

print_info "Testing Ansible connectivity..."
ansible all -i inventory/hosts.ini -m ping

echo ""
read -p "Tiếp tục chạy Ansible playbooks? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Bỏ qua Ansible configuration"
    cd ..
else
    print_info "Running Ansible playbooks..."
    ansible-playbook -i inventory/hosts.ini playbooks/site.yml -e "db_password=${DB_PASSWORD}"
    cd ..
fi

# =============================================================================
# KUBERNETES BASE SETUP (Infrastructure)
# =============================================================================
print_header "8. Kubernetes - Setup Base Resources"

# Configure kubectl if not already configured
if ! kubectl cluster-info &>/dev/null; then
    print_warning "kubectl chưa được cấu hình. Đang cấu hình..."
    
    # Run kubeconfig command
    eval "$KUBECONFIG_COMMAND"
    
    # Verify connection
    if kubectl cluster-info &>/dev/null; then
        print_success "kubectl đã được cấu hình thành công!"
    else
        print_error "Không thể kết nối với EKS cluster"
        print_info "Thử chạy thủ công: ${KUBECONFIG_COMMAND}"
        print_warning "Bỏ qua Kubernetes setup. Chạy lại ./setup.sh sau khi config kubectl."
        # Skip Kubernetes setup but continue to summary
        kubectl_configured=false
    fi
else
    print_success "kubectl đã được cấu hình"
    kubectl_configured=true
fi

if [ "${kubectl_configured:-true}" = "true" ]; then
    print_info "Applying Kubernetes base resources..."
    
    # Apply namespace
    kubectl apply -f kubernetes/namespace.yaml
    
    # Apply ConfigMap với placeholders được thay thế
    echo "📝 Applying ConfigMap..."
    cat kubernetes/configmap.yaml | \
      sed "s|PLACEHOLDER_DB_HOST|${DB_NFS_PRIVATE_IP}|g" | \
      sed "s|PLACEHOLDER_NFS_SERVER|${DB_NFS_PRIVATE_IP}|g" | \
      kubectl apply -f -
    
    # Apply Secrets với placeholders được thay thế
    echo "🔐 Applying Secrets..."
    cat kubernetes/secrets.yaml | \
      sed "s|PLACEHOLDER_DB_PASSWORD|${DB_PASSWORD}|g" | \
      kubectl apply -f -
    
    # Apply NFS PV với placeholders được thay thế
    echo "💾 Applying NFS PersistentVolume..."
    cat kubernetes/nfs-pv.yaml | \
      sed "s|PLACEHOLDER_NFS_SERVER|${DB_NFS_PRIVATE_IP}|g" | \
      kubectl apply -f -
    
    # Wait for PVC
    echo "⏳ Waiting for NFS PVC to be bound..."
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/nfs-uploads-pvc -n devops-final --timeout=60s || true
    
    # Apply Services
    kubectl apply -f kubernetes/base/backend/service.yaml
    kubectl apply -f kubernetes/base/frontend/service.yaml
    
    # Apply HPA
    kubectl apply -f kubernetes/base/backend/hpa.yaml
    kubectl apply -f kubernetes/base/frontend/hpa.yaml
    
    # Apply Ingress với HTTPS config (nếu có)
    echo "🌐 Applying Ingress..."
    if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ] && [ "$HTTPS_CERT_ARN" != "N/A - HTTPS not enabled" ]; then
        cat kubernetes/ingress.yaml | \
          sed "s|PLACEHOLDER_CERT_ARN|${HTTPS_CERT_ARN}|g" | \
          sed "s|PLACEHOLDER_DOMAIN|${DOMAIN_NAME}|g" | \
          kubectl apply -f -
        print_info "HTTPS enabled for ${DOMAIN_NAME}"
        
        # Wait for ALB to be created
        echo "⏳ Waiting for ALB to be created (this may take 2-3 minutes)..."
        sleep 30  # Đợi Ingress Controller bắt đầu tạo ALB
        
        # Get ALB URL
        ALB_URL=""
        for i in {1..12}; do
            ALB_URL=$(kubectl get ingress app-ingress -n devops-final -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            if [ -n "$ALB_URL" ]; then
                print_success "ALB created: $ALB_URL"
                break
            fi
            echo "Waiting for ALB... ($i/12)"
            sleep 10
        done
        
        # Auto-create CNAME record if ALB is ready
        if [ -n "$ALB_URL" ]; then
            echo "🌐 Creating CNAME record for app.${DOMAIN_NAME}..."
            
            # Get Hosted Zone ID
            HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text | cut -d'/' -f3)
            
            if [ -n "$HOSTED_ZONE_ID" ]; then
                # Create/Update CNAME record
                aws route53 change-resource-record-sets \
                  --hosted-zone-id "$HOSTED_ZONE_ID" \
                  --change-batch "{
                    \"Changes\": [{
                      \"Action\": \"UPSERT\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"app.${DOMAIN_NAME}\",
                        \"Type\": \"CNAME\",
                        \"TTL\": 300,
                        \"ResourceRecords\": [{\"Value\": \"${ALB_URL}\"}]
                      }
                    }]
                  }" > /dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    print_success "CNAME record created: app.${DOMAIN_NAME} -> ${ALB_URL}"
                    print_info "Truy cập: https://app.${DOMAIN_NAME} (đợi 2-5 phút cho DNS propagation)"
                else
                    print_warning "Không thể tạo CNAME tự động. Tạo thủ công:"
                    echo "  Record name: app"
                    echo "  Record type: CNAME"
                    echo "  Value: ${ALB_URL}"
                fi
            else
                print_warning "Không tìm thấy Hosted Zone. Tạo CNAME thủ công."
            fi
        else
            print_warning "ALB chưa sẵn sàng. Tạo CNAME sau khi deploy app:"
            echo "  kubectl get ingress -n devops-final"
        fi
    else
        cat kubernetes/ingress.yaml | \
          sed '/certificate-arn/d' | \
          sed "s|listen-ports.*|listen-ports: '[{\"HTTP\": 80}]'|g" | \
          sed '/ssl-redirect/d' | \
          sed '/host: app.PLACEHOLDER_DOMAIN/d' | \
          kubectl apply -f -
        print_info "HTTP-only mode"
    fi
    
    print_success "Kubernetes base resources applied!"
    echo ""
    print_warning "LƯU Ý: Deployments sẽ được apply bởi CD pipeline (cần Docker images)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
print_header "🎉 SETUP HOÀN TẤT!"

echo -e "${GREEN}"
cat << EOF
=============================================
           THÔNG TIN HỆ THỐNG
=============================================

☸️  EKS CLUSTER:
   - Name: ${EKS_CLUSTER_NAME}
   - Endpoint: ${EKS_CLUSTER_ENDPOINT}
   - Region: ${AWS_REGION}
   
   Connect kubectl:
   ${KUBECONFIG_COMMAND}

🔍 SONARQUBE SERVER:
   - Public IP: ${SONARQUBE_PUBLIC_IP}
   - Private IP: ${SONARQUBE_PRIVATE_IP}
   - URL: http://${SONARQUBE_PUBLIC_IP}:9000
   - Login: admin / admin
   - SSH: ssh -i ${SSH_KEY_PATH} ubuntu@${SONARQUBE_PUBLIC_IP}

💾 DATABASE + NFS SERVER:
   - Public IP: ${DB_NFS_PUBLIC_IP}
   - Private IP: ${DB_NFS_PRIVATE_IP}
   - PostgreSQL: ${DB_NFS_PRIVATE_IP}:5432
   - NFS: ${DB_NFS_PRIVATE_IP}:/srv/nfs/uploads
   - SSH: ssh -i ${SSH_KEY_PATH} ubuntu@${DB_NFS_PUBLIC_IP}

EOF

# =============================================================================
# HTTPS SECTION (if enabled)
# =============================================================================
if [ "$ENABLE_HTTPS" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
echo -e "${CYAN}"
cat << EOF
=============================================
           🔒 HTTPS CONFIGURATION
=============================================

Domain: ${DOMAIN_NAME}
Certificate ARN: ${HTTPS_CERT_ARN}
Status: ✅ Configured

📝 THÊM VÀO GITHUB SECRETS (chỉ cần 4 secrets):
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}
   - DOCKER_USERNAME

🌐 DNS CONFIGURATION:
   - CNAME record đã được tạo tự động (nếu có ALB)
   - Truy cập: https://app.${DOMAIN_NAME}
   - Đợi 2-5 phút cho DNS propagation

=============================================
EOF
echo -e "${NC}"
fi

# =============================================================================
# GITHUB SECRETS SECTION
# =============================================================================
echo -e "${YELLOW}"
cat << EOF
=============================================
      📋 GITHUB ACTIONS SECRETS
=============================================

Vào GitHub repo → Settings → Secrets → Actions

✅ SECRETS BẮT BUỘC (chỉ 4 secrets):
   1. AWS_ACCESS_KEY_ID: <your-aws-access-key>
   2. AWS_SECRET_ACCESS_KEY: <your-aws-secret-key>
   3. EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}
   4. DOCKER_USERNAME: <your-dockerhub-username>

ℹ️  SECRETS CHO CI (không liên quan CD):
   - SONAR_HOST_URL: http://${SONARQUBE_PUBLIC_IP}:9000
   - SONAR_TOKEN: <generate từ SonarQube UI>
   - DOCKER_PASSWORD: <your-dockerhub-password>

💡 Setup.sh đã cấu hình:
   ✅ ConfigMap (DB_HOST, NFS_SERVER)
   ✅ Secrets (DB_PASSWORD)
   ✅ Ingress (HTTPS certificate)
   ✅ CNAME record (nếu có domain)

=============================================
EOF
echo -e "${NC}"

# =============================================================================
# NEXT STEPS SECTION
# =============================================================================
echo -e "${GREEN}"
cat << EOF
=============================================
           📝 NEXT STEPS
=============================================

1️⃣  Cấu hình SonarQube:
   - Truy cập: http://${SONARQUBE_PUBLIC_IP}:9000
   - Login: admin / admin
   - Đổi password
   - Generate token: My Account → Security → Generate Token

2️⃣  Thêm GitHub Secrets:
   - Vào repo → Settings → Secrets and variables → Actions
   - Thêm tất cả secrets ở trên

3️⃣  Deploy ứng dụng:
   - Push code lên GitHub: git push origin main
   - CI/CD sẽ tự động chạy

4️⃣  Kiểm tra deployment:
   - kubectl get pods -n devops-final
   - kubectl get ingress -n devops-final

=============================================
EOF
echo -e "${NC}"

print_info "Để xem lại kubectl command: echo '${KUBECONFIG_COMMAND}'"
print_info "Để test Ansible: cd ansible && ansible all -i inventory/hosts.ini -m ping"


