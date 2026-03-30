#!/bin/bash
# =============================================================================
# SETUP.SH - Automated Infrastructure & K8s Setup (Linux/Mac/WSL)
# =============================================================================
# Chạy: chmod +x setup.sh && ./setup.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=============================================${NC}\n${BLUE}$1${NC}\n${BLUE}=============================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# =============================================================================
# INSTALL PREREQUISITES (Terraform, AWS CLI, Ansible)
# =============================================================================
print_header "1. Kiểm tra & Cài đặt Prerequisites"

NEED_INSTALL=false

# --- Check Terraform ---
if command -v terraform &> /dev/null; then
    print_success "Terraform: $(terraform version | head -n1)"
else
    print_warning "Terraform chưa được cài đặt. Đang tải thẳng file nhị phân (Bypass APT)..."
    NEED_INSTALL=true
    
    # Đảm bảo máy có lệnh wget và unzip
    sudo apt-get update -qq
    sudo apt-get install -y unzip wget
    
    # Tải thẳng bản Terraform 1.7.5 và cài đặt trực tiếp
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
    unzip -o -q terraform_1.7.5_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm -f terraform_1.7.5_linux_amd64.zip
    cd - > /dev/null
    
    if command -v terraform &> /dev/null; then
        print_success "Terraform đã cài đặt: $(terraform version | head -n1)"
    else
        print_error "Không thể cài đặt Terraform. Vui lòng kiểm tra quyền sudo."
        exit 1
    fi
fi

# --- Check AWS CLI ---
if command -v aws &> /dev/null; then
    print_success "AWS CLI: $(aws --version | cut -d' ' -f1)"
else
    print_warning "AWS CLI chưa được cài đặt. Đang cài đặt..."
    NEED_INSTALL=true
    
    # Install AWS CLI v2
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
    
    # Install Ansible
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
    print_success "AWS Account: $AWS_ACCOUNT"
    print_success "AWS User/Role: $AWS_USER"
else
    print_error "AWS credentials chưa được cấu hình!"
    echo ""
    echo -e "${YELLOW}Bạn cần cấu hình AWS credentials trước khi tiếp tục.${NC}"
    echo ""
    echo "Cách 1 - Chạy aws configure:"
    echo "  aws configure"
    echo "  → Nhập Access Key ID"
    echo "  → Nhập Secret Access Key"  
    echo "  → Nhập Region (ví dụ: ap-southeast-1)"
    echo ""
    echo "Cách 2 - Export environment variables:"
    echo "  export AWS_ACCESS_KEY_ID=your_access_key"
    echo "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "  export AWS_DEFAULT_REGION=ap-southeast-1"
    echo ""
    echo -e "${BLUE}Sau khi cấu hình xong, chạy lại: ./setup.sh${NC}"
    exit 1
fi

# =============================================================================
# LOAD .ENV FILE
# =============================================================================
print_header "3. Đọc cấu hình từ .env"

if [ ! -f ".env" ]; then
    print_error "Không tìm thấy file .env!"
    echo "Hãy copy .env.example thành .env và điền thông tin."
    exit 1
fi

# Load .env
export $(grep -v '^#' .env | grep -v '^\s*$' | xargs)

# Validate required vars
if [ -z "$AWS_KEY_NAME" ] || [ "$AWS_KEY_NAME" = "your-key-name-here" ]; then
    print_error "AWS_KEY_NAME chưa được cấu hình trong .env"
    exit 1
fi

print_success "AWS_KEY_NAME: $AWS_KEY_NAME"

# Check SSH key file
SSH_KEY_PATH="${AWS_KEY_NAME}.pem"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_error "Không tìm thấy SSH key: $SSH_KEY_PATH"
    exit 1
fi

# Fix permission cho SSH key (quan trọng!)
chmod 600 "$SSH_KEY_PATH"
print_success "SSH Key file: $SSH_KEY_PATH (permission 600)"

# =============================================================================
# TERRAFORM
# =============================================================================
print_header "4. Terraform - Tạo Infrastructure"

cd terraform

terraform init -upgrade
terraform plan -var="key_name=$AWS_KEY_NAME" -out=tfplan
terraform apply tfplan

# Get outputs
K8S_IP=$(terraform output -raw k8s_master_public_ip)
SONARQUBE_IP=$(terraform output -raw sonarqube_public_ip)
K8S_PRIVATE_IP=$(terraform output -raw k8s_master_private_ip)

print_success "K8s Master IP: $K8S_IP"
print_success "SonarQube IP: $SONARQUBE_IP"

cd ..

# =============================================================================
# GENERATE ANSIBLE INVENTORY
# =============================================================================
print_header "5. Tạo Ansible Inventory"

# Lấy absolute path của SSH key
SSH_KEY_ABSOLUTE_PATH="$(pwd)/${SSH_KEY_PATH}"

cat > ansible/inventory/hosts.ini << EOF
# Auto-generated by setup.sh at $(date)

[k8s_master]
k8s-master ansible_host=${K8S_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${SSH_KEY_ABSOLUTE_PATH}

[k8s_master:vars]
ansible_python_interpreter=/usr/bin/python3
k8s_master_private_ip=${K8S_PRIVATE_IP}

[sonarqube]
sonar ansible_host=${SONARQUBE_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${SSH_KEY_ABSOLUTE_PATH}

[sonarqube:vars]
ansible_python_interpreter=/usr/bin/python3

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

print_success "Inventory đã được tạo"

# =============================================================================
# WAIT FOR SSH
# =============================================================================
print_header "6. Đợi servers sẵn sàng"

echo "Đang đợi SSH ready..."
for i in {1..5}; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -i "$SSH_KEY_PATH" ubuntu@"$K8S_IP" "echo 'OK'" &>/dev/null; then
        print_success "K8s Master SSH ready!"
        break
    fi
    echo "Đợi... ($i/5)"
    sleep 5
done

# =============================================================================
# RUN ANSIBLE
# =============================================================================
print_header "7. Ansible - Cấu hình K8s Cluster"

cd ansible

# Set roles path
export ANSIBLE_ROLES_PATH="./roles"

echo "Testing Ansible connection..."
ansible all -i inventory/hosts.ini -m ping

echo "Running Ansible playbook..."
ansible-playbook -i inventory/hosts.ini playbooks/k8s-master.yml

cd ..

# =============================================================================
# SUMMARY
# =============================================================================
print_header "🎉 SETUP HOÀN TẤT!"

echo -e "${GREEN}"
cat << EOF
=============================================
           THÔNG TIN HỆ THỐNG
=============================================

📦 K8s Master Node:
   - IP: $K8S_IP
   - SSH: ssh -i $SSH_KEY_PATH ubuntu@$K8S_IP

🔍 SonarQube Server:
   - URL: http://$SONARQUBE_IP:9000
   - Login: admin / admin

📋 GITHUB SECRETS (thêm vào repo):
   - K8S_HOST: $K8S_IP
   - K8S_SSH_KEY: <nội dung file $SSH_KEY_PATH>
   - DOCKER_USERNAME: <your dockerhub username>
   - DOCKER_PASSWORD: <your dockerhub password>
   - DB_PASSWORD: <your database password>

=============================================
EOF
echo -e "${NC}"
