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

print_success "AWS_KEY_NAME: $AWS_KEY_NAME"
print_success "DB_PASSWORD: ${DB_PASSWORD:0:3}***${DB_PASSWORD: -3}"

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
terraform plan -var="key_name=$AWS_KEY_NAME" -out=tfplan

echo ""
read -p "Tiếp tục apply infrastructure? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Hủy deployment"
    exit 0
fi

print_info "Applying infrastructure... (15-20 phút)"
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

print_success "EKS Cluster: $EKS_CLUSTER_NAME"
print_success "SonarQube IP: $SONARQUBE_PUBLIC_IP"
print_success "DB+NFS IP: $DB_NFS_PUBLIC_IP"

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

📋 GITHUB ACTIONS SECRETS (cần thêm vào repo):
   
   Các secrets BẮT BUỘC:
   - AWS_ACCESS_KEY_ID: <your-aws-access-key>
   - AWS_SECRET_ACCESS_KEY: <your-aws-secret-key>
   - EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}
   - DATA_SERVER_IP: ${DB_NFS_PRIVATE_IP}
   - SONAR_HOST_URL: http://${SONARQUBE_PUBLIC_IP}:9000
   - SONAR_TOKEN: <generate từ SonarQube UI>
   - DOCKER_USERNAME: <your-dockerhub-username>
   - DOCKER_PASSWORD: <your-dockerhub-password>
   - DB_PASSWORD: ${DB_PASSWORD}
   
   💡 AWS credentials dùng để GitHub Actions kết nối EKS cluster

📝 NEXT STEPS:
   1. Truy cập SonarQube và đổi password
   2. Generate SonarQube token: User > My Account > Security > Generate Token
   3. Thêm tất cả secrets vào GitHub repo
   4. Update K8s manifests với DB_HOST và NFS_SERVER_IP
   5. Push code để trigger CI/CD pipeline

=============================================
EOF
echo -e "${NC}"

print_info "Để xem lại kubectl command: echo '${KUBECONFIG_COMMAND}'"
print_info "Để test Ansible: cd ansible && ansible all -i inventory/hosts.ini -m ping"


