# Document Management System - DevOps Final Project

Production-ready full-stack document management application with Kubernetes orchestration, automated CI/CD pipeline, and comprehensive monitoring.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

Full-stack Document Management Application with CRUD operations and file attachments:

**Features:**
- ✅ Create, read, update, delete documents
- ✅ File upload/download (stored in NFS persistent volume)
- ✅ **Kubernetes orchestration** (Amazon EKS)
- ✅ **Infrastructure as Code** (Terraform + Ansible)
- ✅ **Automated CI/CD** (GitHub Actions)
- ✅ **Horizontal Pod Autoscaling** (HPA)
- ✅ **Self-healing** (Kubernetes liveness/readiness probes)
- ✅ **Monitoring** (Prometheus + Grafana)
- ✅ **SSL/HTTPS** (AWS Certificate Manager)
- ✅ **Secure configuration** (GitHub Secrets, AWS Secrets Manager)

**Technologies:**
- Backend: Spring Boot 3.5.13 + Java 21 + PostgreSQL
- Frontend: React 18 + Vite + TailwindCSS
- Infrastructure: Amazon EKS + Terraform + Ansible
- CI/CD: GitHub Actions
- Monitoring: Prometheus + Grafana + Alertmanager
- Storage: NFS Persistent Volume

---

## 🏗️ Architecture

### Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                               │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                      │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │         Amazon EKS Cluster (devops-final-eks)       │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌──────────────────────────────────────────────┐  │ │ │
│  │  │  │  Namespace: devops-final (Production)        │  │ │ │
│  │  │  │                                              │  │ │ │
│  │  │  │  ┌────────────┐  ┌────────────┐            │  │ │ │
│  │  │  │  │  Backend   │  │  Frontend  │            │  │ │ │
│  │  │  │  │  Pods      │  │  Pods      │            │  │ │ │
│  │  │  │  │  (2-5)     │  │  (2-5)     │            │  │ │ │
│  │  │  │  │  + HPA     │  │  + HPA     │            │  │ │ │
│  │  │  │  └────────────┘  └────────────┘            │  │ │ │
│  │  │  │                                              │  │ │ │
│  │  │  │  ┌────────────────────────────────────┐    │  │ │ │
│  │  │  │  │  NFS Persistent Volume             │    │  │ │ │
│  │  │  │  │  (File uploads storage)            │    │  │ │ │
│  │  │  │  └────────────────────────────────────┘    │  │ │ │
│  │  │  └──────────────────────────────────────────────┘  │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌──────────────────────────────────────────────┐  │ │ │
│  │  │  │  Namespace: staging                          │  │ │ │
│  │  │  │  - Backend Pod (1)                           │  │ │ │
│  │  │  │  - Frontend Pod (1)                          │  │ │ │
│  │  │  └──────────────────────────────────────────────┘  │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌──────────────────────────────────────────────┐  │ │ │
│  │  │  │  Namespace: monitoring                       │  │ │ │
│  │  │  │  - Prometheus                                │  │ │ │
│  │  │  │  - Grafana                                   │  │ │ │
│  │  │  │  - Alertmanager                              │  │ │ │
│  │  │  └──────────────────────────────────────────────┘  │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌──────────────────────────────────────────────┐  │ │ │
│  │  │  │  AWS Load Balancer Controller                │  │ │ │
│  │  │  │  (Manages ALB for Ingress)                   │  │ │ │
│  │  │  └──────────────────────────────────────────────┘  │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  EC2 Instance: Database + NFS Server               │ │ │
│  │  │  - PostgreSQL 16                                   │ │ │
│  │  │  - NFS Server (exports /nfs/uploads)               │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  EC2 Instance: SonarQube Server                    │ │ │
│  │  │  - SonarQube (Code Quality Analysis)               │ │ │
│  │  │  - HTTPS with Let's Encrypt                        │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Application Load Balancer (ALB)                   │ │ │
│  │  │  - HTTPS (ACM Certificate)                         │ │ │
│  │  │  - Routes to EKS pods                              │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Request Flow

1. **User → ALB (HTTPS):** Browser accesses `https://devops-midterm.online`
2. **ALB → Ingress Controller:** Routes to appropriate service
3. **Ingress → Frontend/Backend Pods:** Load balanced across pods
4. **Backend → PostgreSQL:** Database queries via private network
5. **Backend → NFS:** File uploads stored in persistent volume
6. **Prometheus:** Scrapes metrics from all pods
7. **Grafana:** Visualizes metrics and alerts

---

## 🛠️ Tech Stack

### Frontend
- **Framework:** React 18
- **Build Tool:** Vite
- **Styling:** TailwindCSS
- **HTTP Client:** Axios
- **Container:** Nginx (alpine)

### Backend
- **Framework:** Spring Boot 3.5.13
- **Language:** Java 21
- **Build Tool:** Maven
- **Database:** PostgreSQL 16
- **ORM:** Spring Data JPA / Hibernate
- **Container:** Eclipse Temurin 21-JDK

### Infrastructure
- **Cloud Provider:** AWS
- **Orchestration:** Kubernetes (Amazon EKS)
- **IaC:** Terraform 1.7+
- **Configuration Management:** Ansible 2.9+
- **Container Registry:** Docker Hub
- **Load Balancer:** AWS Application Load Balancer
- **Storage:** NFS Persistent Volume
- **SSL/TLS:** AWS Certificate Manager

### CI/CD
- **Platform:** GitHub Actions
- **Workflows:**
  - PR CI: SonarQube code quality scan
  - Infrastructure CD: Terraform + Ansible deployment
  - Production Pipeline: Build → Staging → Production (with manual approval)
- **Security Scanning:** Trivy (container vulnerability scanning)
- **Secret Management:** GitHub Secrets + TruffleHog

### Monitoring
- **Metrics:** Prometheus
- **Visualization:** Grafana
- **Alerting:** Alertmanager
- **Dashboards:** Kubernetes cluster metrics, application metrics

---

## 📦 Prerequisites

### Required Accounts & Access

| Service | Purpose | Required |
|---------|---------|----------|
| AWS Account | Infrastructure hosting | ✅ Yes |
| Docker Hub | Container registry | ✅ Yes |
| GitHub | Code repository + CI/CD | ✅ Yes |
| Domain Name | Custom domain + HTTPS | ✅ Yes |
| Email Account | Monitoring alerts | ✅ Yes |

### Required Software (Local Machine)

| Software | Version | Installation |
|----------|---------|--------------|
| AWS CLI | 2.x | `brew install awscli` or [AWS Docs](https://aws.amazon.com/cli/) |
| kubectl | 1.28+ | `brew install kubectl` or [Kubernetes Docs](https://kubernetes.io/docs/tasks/tools/) |
| Git | 2.x | `brew install git` |

> **Note:** Terraform and Ansible are not required locally as infrastructure deployment is automated via GitHub Actions.

### Prerequisites

#### 1. AWS Account with IAM User

Create IAM user with programmatic access and required permissions:
- EC2 (create instances, security groups)
- EKS (create cluster, node groups)
- VPC (create VPC, subnets, route tables)
- IAM (create roles, policies)
- ACM (request certificates)
- Route53 (manage DNS records)
- S3 (create buckets, manage objects)
- DynamoDB (create tables)

#### 2. AWS Access Keys

- Go to AWS Console → IAM → Users → Your User → Security Credentials
- Click "Create access key" → Choose "Command Line Interface (CLI)"
- Download and save:
  - Access Key ID
  - Secret Access Key

#### 3. SSH Key Pair

- Go to AWS Console → EC2 → Key Pairs → Create key pair
- Name: `Devops_Final`
- Key pair type: RSA
- Private key file format: `.pem`
- Download `Devops_Final.pem` and save it securely

#### 4. Domain Name Registration

Purchase a domain from domain registrars like Hostinger, Namecheap, GoDaddy, etc.

**Step 1: Create Hosted Zone on AWS Route 53**

1. Log in to AWS Management Console and search for Route 53
2. In the left menu, select "Hosted zones" → Click "Create hosted zone"
3. Fill in the information:
   - Domain name: Enter your domain (e.g., `devops-midterm.online`)
   - Description: Project notes
   - Type: Select "Public hosted zone"
4. Click "Create hosted zone"
5. After creation, the system will automatically generate 2 records: NS and SOA
6. Note the NS (Name server) record - you will see 4 values like:
   ```
   ns-xxxx.awsdns-xx.co.uk.
   ns-xxxx.awsdns-xx.com.
   ns-xxxx.awsdns-xx.net.
   ns-xxxx.awsdns-xx.org.
   ```
7. **Important:** Copy these 4 values to Notepad. When copying to your domain registrar in Step 2, remove the dot (.) at the end of each line if present.

**Step 2: Point Name Servers (NS) from Domain Registrar to AWS**

Example using Hostinger (similar process for other registrars):

1. Log in to your domain registrar control panel (e.g., Hostinger hPanel)
2. Go to "Domains" section and select your domain
3. In the left menu, find and select "DNS / Nameservers"
4. Select the "Nameservers" tab and click "Change Nameservers"
5. Choose "Change nameservers" option instead of using default nameservers
6. Delete the old NS records and paste the 4 AWS Route 53 NS values from Step 1 into the 4 corresponding fields
7. Click "Save" to complete

> **Note:** DNS propagation may take 24-48 hours. You can check propagation status at [whatsmydns.net](https://www.whatsmydns.net/)

#### 5. Email Configuration for Alerts

Create an app password for email alerts (using Gmail as example):

1. Go to your Google Account → Security
2. Enable 2-Step Verification if not already enabled
3. Go to "App passwords" section
4. Select app: "Mail"
5. Select device: "Other (Custom name)" → Enter "DevOps Alerts"
6. Click "Generate"
7. Copy the 16-character app password (save it for GitHub Secrets)

> **Note:** For other email providers, check their documentation for app password generation.

#### 6. Docker Hub Account

- Sign up at [Docker Hub](https://hub.docker.com/)
- Create access token:
  - Account Settings → Security → New Access Token
  - Save username and token

### System Requirements
- **OS:** macOS, Linux, or WSL2 on Windows
- **RAM:** Minimum 8GB (for local development)
- **Disk Space:** 5GB free space
- **Network:** Stable internet connection

---

## Deployment Steps

> **⚠️ CRITICAL WARNING:** Do NOT push any code to main branch or any other branch before completing Steps 1-4 below. GitHub Actions workflows will fail without proper secrets configuration. Follow the steps in order!

### Step 1: Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <your-access-key-id>
# AWS Secret Access Key: <your-secret-access-key>
# Default region name: ap-southeast-1
# Default output format: json
```

### Step 2: Create Terraform Backend

Run the bootstrap script to create S3 bucket and DynamoDB table for Terraform state:

```bash
chmod +x bootstrap-backend.sh
./bootstrap-backend.sh
```

This creates:
- S3 bucket: `devops-final-tfstate-<random-id>`
- DynamoDB table: `devops-final-tflock`

**Save the bucket name** - you'll need it for GitHub Secrets in the next step.

### Step 3: Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

**Add the following secrets:**

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | AWS access key from Prerequisites #2 | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key from Prerequisites #2 | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_KEY_NAME` | SSH key pair name from Prerequisites #3 | `Devops_Final` |
| `EC2_SSH_PRIVATE_KEY` | Content of `Devops_Final.pem` file | `-----BEGIN RSA PRIVATE KEY-----...` |
| `TF_BACKEND_BUCKET` | S3 bucket name from Deployment Step 2 | `devops-final-tfstate-abc123` |
| `EKS_CLUSTER_NAME` | EKS cluster name | `devops-final-eks` |
| `DOCKER_USERNAME` | Docker Hub username from Prerequisites #6 | `yourusername` |
| `DOCKER_PASSWORD` | Docker Hub access token from Prerequisites #6 | `dckr_pat_...` |
| `DB_PASSWORD` | PostgreSQL password (create strong password) | `YourStrongPassword123!` |
| `DOMAIN_NAME` | Your domain from Prerequisites #4 | `devops-midterm.online` |
| `ALERT_EMAIL` | Email for alerts from Prerequisites #5 | `your-email@example.com` |
| `ALERT_EMAIL_PASSWORD` | Email app password from Prerequisites #5 | `abcd efgh ijkl mnop` |

**SonarQube secrets (add after infrastructure deployment):**

| Secret Name | Description | When to Add |
|-------------|-------------|-------------|
| `SONAR_HOST_URL` | SonarQube server URL | After Step 5 |
| `SONAR_TOKEN` | SonarQube access token | After Step 6 |

### Step 4: Configure GitHub Environments

**Create two environments for manual approval:**

1. Go to Settings → Environments → New environment
2. Create `staging` environment (no protection rules needed)
3. Create `production` environment with:
   - ✅ Required reviewers: Add yourself
   - ✅ Wait timer: 0 minutes (optional)

### Step 5: Deploy Infrastructure (First Push)

Since SonarQube needs to be running before we can scan application code, we'll first deploy only the infrastructure without the application source code.

**Push only infrastructure files to main branch:**

```bash
# Only add infrastructure-related files
git add terraform/ ansible/ kubernetes/ .github/workflows/infrastructure-cd.yml bootstrap-backend.sh
git commit -m "chore: setup infrastructure"
git branch -M main
git push -u origin main
```

This will trigger the Infrastructure CD workflow. Wait approximately 15-20 minutes for EKS cluster and SonarQube server to be created.

**What happens:**
- ✅ Terraform creates: VPC, EKS cluster, EC2 instances
- ✅ Ansible configures: PostgreSQL, NFS, SonarQube
- ✅ Kubernetes resources deployed: Namespaces, ConfigMaps, Secrets, HPAs
- ✅ Monitoring stack installed: Prometheus, Grafana, Alertmanager

### Step 6: Configure SonarQube Token

After infrastructure deployment completes:

1. Access SonarQube: `https://sonar.devops-midterm.online` (replace with your domain)
2. Login with default credentials: `admin` / `admin`
3. Change password on first login (required)
4. Generate token:
   - Click on your profile (top right) → My Account
   - Go to Security tab → Generate Tokens
   - Token Name: `github-actions`
   - Type: `Global Analysis Token`
   - Click "Generate" and copy the token
5. Add secrets to GitHub:
   - Go to GitHub repository → Settings → Secrets and variables → Actions
   - Add `SONAR_HOST_URL`: `https://sonar.devops-midterm.online`
   - Add `SONAR_TOKEN`: `<generated-token>`

### Step 7: Submit Application Code (Create Pull Request)

Now that infrastructure and SonarQube are ready, create a new branch and push all remaining files.

**Create feature branch and push all remaining code:**

```bash
# Create new branch from current main
git checkout -b feature/init-app
```

> **Important:** After creating the branch, you need to copy all remaining project files (application source code, additional workflows, documentation, etc.) into your local repository folder. The new branch only contains the infrastructure files that were pushed to main in Step 5. You must manually add the remaining files before committing.

```bash
# After copying all remaining files to your repository folder
# Add all files to git
git add .
git commit -m "feat: init application and CI/CD pipelines"
git push -u origin feature/init-app
```

**Create Pull Request:**

1. Go to GitHub repository → Pull requests → New pull request
2. Base: `main` ← Compare: `feature/init-app`
3. Click "Create pull request"
4. The PR CI workflow will automatically run SonarQube code quality scan
5. Wait for quality gate to pass (green checkmark)
6. Click "Merge pull request" to merge into main

**After merging:**
- ✅ Production Pipeline automatically triggers
- ✅ Builds backend and frontend Docker images
- ✅ Deploys to staging environment
- ⏸️ Waits for manual approval
- ✅ Deploys to production after approval

**Access application (replace with your domain):**
- Production: `https://devops-midterm.online`
- Staging: `https://staging.devops-midterm.online`
- Grafana: `https://grafana.devops-midterm.online`
- SonarQube: `https://sonar.devops-midterm.online`

### Step 8: Approve Production Deployment

After staging deployment completes:

1. Go to GitHub repository → Actions → Production Pipeline workflow
2. Click on the running workflow
3. Click "Review deployments"
4. Select "production" environment
5. Click "Approve and deploy"
6. Production deployment will start automatically

**Verify deployment:**

```bash
# Connect to EKS cluster (required for kubectl commands)
aws eks update-kubeconfig --name devops-final-eks --region ap-southeast-1

# Check production pods
kubectl get pods -n devops-final

# Check HPA status
kubectl get hpa -n devops-final

# Check ingress
kubectl get ingress -n devops-final
```

---

## 🔄 CI/CD Pipeline

### Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **PR CI** | Pull Request | SonarQube code quality scan |
| **Infrastructure CD** | Manual | Deploy/destroy infrastructure |
| **Production Pipeline** | Push to main | Build → Staging → Production |

### Production Pipeline Details

```
┌─────────────────────────────────────────────────────────────┐
│                   Production Pipeline                       │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────┐
│ Wait for             │
│ Infrastructure       │  ← Smart check: waits if infra is deploying
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐  ┌──────────────────────┐
│ Build Backend        │  │ Build Frontend       │
│ + Trivy Scan         │  │ + Trivy Scan         │
│ + Push to Docker Hub │  │ + Push to Docker Hub │
└──────────┬───────────┘  └──────────┬───────────┘
           │                         │
           └────────────┬────────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │ Deploy to Staging      │
           │ (Automatic)            │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │ Manual Approval        │  ← GitHub Environment Protection
           │ (Production)           │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │ Deploy to Production   │
           │ (After Approval)       │
           └────────────────────────┘
```

**Key Features:**
- ✅ Build Once, Deploy Anywhere (same Docker image for staging & production)
- ✅ Security scanning with Trivy (blocks on CRITICAL vulnerabilities)
- ✅ Manual approval gate for production
- ✅ Automatic rollback on deployment failure

---

## 📊 Monitoring

### Prometheus Metrics

**Access Prometheus:**

```bash
# Port forward to access Prometheus locally
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then open browser: `http://localhost:9090`

**Collected Metrics:**
- Kubernetes cluster metrics (CPU, memory, disk, network)
- Pod metrics (restarts, status, resource usage)
- Application metrics (HTTP requests, response times, errors)
- HPA metrics (current replicas, desired replicas, scaling events)

### Grafana Dashboards

Access: `https://grafana.devops-midterm.online` (replace with your domain)

**Default Credentials:** `admin` / `admin123`

**Pre-configured Dashboards:**
- Kubernetes Cluster Overview
- Pod Resource Usage
- Application Performance
- HPA Scaling Events

### Alertmanager

Access Alertmanager to view active alerts and notification status:

```bash
# Port forward to access Alertmanager locally
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Then open browser: `http://localhost:9093`

**Configured Alerts:**
- Pod CrashLooping
- High Memory Usage (>90%)
- High CPU Usage (>80%)
- Deployment Rollout Failed

---

## 🧪 Testing

> **Note:** Before running kubectl commands, ensure you're connected to the EKS cluster:
> ```bash
> aws eks update-kubeconfig --name devops-final-eks --region ap-southeast-1
> ```

### Test Horizontal Pod Autoscaling

```bash
# Check current HPA configuration
kubectl get hpa -n devops-final

# Generate load to trigger autoscaling
while true; do
  for i in {1..100}; do
    curl https://devops-midterm.online/api/documents &
  done
  sleep 1
done

# Watch HPA scale (in another terminal)
kubectl get hpa -n devops-final -w

# Watch pods scale
kubectl get pods -n devops-final -w
```

**Expected Result:** Backend scales from 2 → 5 pods when CPU > 50%

### Test Self-Healing

```bash
# Delete a pod
kubectl delete pod <pod-name> -n devops-final

# Kubernetes automatically creates a new pod
kubectl get pods -n devops-final -w
```

### Test Rolling Update

```bash
# Make a code change and push
git add .
git commit -m "Update feature"
git push origin main

# Watch rolling update
kubectl rollout status deployment/backend -n devops-final
```

---

## 🔧 Troubleshooting

**Note:** Before running kubectl commands, ensure you're connected to the EKS cluster:
> ```bash
> aws eks update-kubeconfig --name devops-final-eks --region ap-southeast-1
> ```

### Infrastructure Issues

#### Issue: Terraform state lock

```bash
# Delete lock from DynamoDB
aws dynamodb delete-item \
  --table-name devops-final-tflock \
  --key '{"LockID":{"S":"devops-final-tfstate/terraform.tfstate"}}'
```

### Application Issues

#### Issue: Pods not starting

```bash
# Check pod status
kubectl get pods -n devops-final

# View logs
kubectl logs -l app=backend -n devops-final --tail=100

# Describe pod for events
kubectl describe pod <pod-name> -n devops-final
```

#### Issue: Database connection failed

```bash
# Check if database is accessible from EKS
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <db-private-ip> -U postgres -d document_db

# Check ConfigMap
kubectl get configmap app-config -n devops-final -o yaml
```

#### Issue: NFS mount failed

```bash
# Check NFS server
ssh -i Devops_Final.pem ubuntu@<db-server-ip>
sudo systemctl status nfs-kernel-server
sudo exportfs -v

# Check PV/PVC
kubectl get pv,pvc -n devops-final
```

### CI/CD Issues

#### Issue: GitHub Actions workflow failed

```bash
# Check workflow logs in GitHub Actions tab

# Common fixes:
# 1. Verify all secrets are set correctly
# 2. Check if infrastructure is deployed
# 3. Verify Docker Hub credentials
# 4. Check if EKS cluster is accessible
```

#### Issue: Trivy scan blocking deployment

```bash
# Update vulnerable dependencies
# Backend: Update pom.xml
# Frontend: Update package.json

# Or temporarily disable Trivy (not recommended)
# Remove Trivy step from .github/workflows/production-pipeline.yml
```

---

## 🗑️ Cleanup

### Destroy Infrastructure

**Via GitHub Actions:**

1. Go to GitHub repository → Actions tab
2. Select "Infrastructure CD" workflow
3. Click "Run workflow"
4. Select:
   - Branch: `main`
   - Action: `destroy`
5. Type `DESTROY` in the confirmation field (required)
6. Click "Run workflow"

Wait for the workflow to complete (~10-15 minutes). The workflow will automatically clean up:
- ✅ Kubernetes resources (Ingress, Services, Namespaces)
- ✅ Application Load Balancers (ALBs)
- ✅ Route53 DNS records (A records and CNAMEs)
- ✅ Security Groups (Kubernetes-created)
- ✅ EKS cluster, EC2 instances, VPC
- ✅ S3 backend bucket
- ✅ DynamoDB state lock table

### Manual Verification and Cleanup

After the destroy workflow completes, verify all resources are deleted:

```bash
# Connect to AWS
aws configure

# Check EC2 instances
aws ec2 describe-instances --region ap-southeast-1 --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' --output table

# Check VPC
aws ec2 describe-vpcs --region ap-southeast-1 --filters "Name=tag:Name,Values=devops-final-vpc" --query 'Vpcs[].VpcId' --output table

# Check EKS clusters
aws eks list-clusters --region ap-southeast-1

# Check Load Balancers
aws elbv2 describe-load-balancers --region ap-southeast-1 --query 'LoadBalancers[].LoadBalancerName' --output table
```

### Delete Route 53 Hosted Zone (Manual)

> **Important:** The Route 53 Hosted Zone is NOT managed by Terraform and must be deleted manually.

1. Go to AWS Console → Route 53 → Hosted zones
2. Select your hosted zone (e.g., `devops-midterm.online`)
3. Verify all DNS records are deleted (only NS and SOA should remain)
4. Click "Delete hosted zone"
5. Confirm deletion

> **Note:** The Hosted Zone was created manually to link with your third-party domain registrar (Hostinger, Namecheap, etc.), so it must be deleted manually as well.

---

## 📝 Project Structure

```
Devops-Final/
├── .github/
│   └── workflows/
│       ├── pr-ci.yml                    # PR code quality scan
│       ├── infrastructure-cd.yml        # Infrastructure deployment
│       └── production-pipeline.yml      # Application deployment
├── ansible/
│   ├── inventory/
│   │   └── hosts.ini                    # Dynamic inventory
│   └── playbooks/
│       ├── database.yml                 # PostgreSQL + NFS setup
│       ├── sonarqube.yml                # SonarQube setup
│       └── site.yml                     # Main playbook
├── kubernetes/
│   ├── base/
│   │   ├── backend/
│   │   │   ├── deployment.yaml          # Backend deployment
│   │   │   ├── service.yaml             # Backend service
│   │   │   └── hpa.yaml                 # Backend HPA
│   │   └── frontend/
│   │       ├── deployment.yaml          # Frontend deployment
│   │       ├── service.yaml             # Frontend service
│   │       └── hpa.yaml                 # Frontend HPA
│   ├── staging/
│   │   ├── backend-deployment.yaml      # Staging backend
│   │   ├── frontend-deployment.yaml     # Staging frontend
│   │   └── ingress.yaml                 # Staging ingress
│   ├── monitoring/
│   │   ├── alert-rules.yaml             # Prometheus alerts
│   │   └── grafana-ingress.yaml         # Grafana ingress
│   ├── configmap.yaml                   # App configuration
│   ├── secrets.yaml                     # App secrets
│   ├── namespace.yaml                   # Namespaces
│   ├── nfs-pv.yaml                      # NFS persistent volume
│   └── ingress.yaml                     # Production ingress
├── src/
│   ├── backend/
│   │   ├── src/main/java/...            # Spring Boot code
│   │   ├── pom.xml                      # Maven dependencies
│   │   └── Dockerfile                   # Backend container
│   └── frontend/
│       ├── src/                         # React code
│       ├── package.json                 # npm dependencies
│       └── Dockerfile                   # Frontend container
├── terraform/
│   ├── vpc.tf                           # VPC configuration
│   ├── eks.tf                           # EKS cluster
│   ├── ec2.tf                           # EC2 instances
│   ├── acm-route53.tf                   # SSL certificates
│   ├── load-balancer-controller.tf      # ALB controller
│   ├── prometheus-grafana.tf            # Monitoring stack
│   ├── variables.tf                     # Input variables
│   ├── outputs.tf                       # Output values
│   └── backend.tf                       # Terraform backend
├── bootstrap-backend.sh                 # Create S3 + DynamoDB
└── README.md                            # This file
```

---

## 🔒 Security Best Practices

- ✅ All secrets stored in GitHub Secrets (never in code)
- ✅ Container vulnerability scanning with Trivy
- ✅ Secret scanning with TruffleHog
- ✅ HTTPS with AWS Certificate Manager
- ✅ Private subnets for database and NFS
- ✅ Security groups with least privilege
- ✅ IAM roles with minimal permissions
- ✅ Kubernetes RBAC enabled
- ✅ Network policies

---

## 🔄 Version History

- **v1.0.0** - Initial Kubernetes deployment
- **v2.0.0** - Added Terraform + Ansible automation
- **v3.0.0** - Implemented CI/CD with GitHub Actions
- **v4.0.0** - Added monitoring (Prometheus + Grafana)
- **v5.0.0** - Production-ready with HPA, self-healing, HTTPS

---

## 📄 License

This project is for educational purposes (DevOps Final Exam).

---

## 👥 Authors

- DevOps Engineer - Final Project

---

## 🙏 Acknowledgments

- AWS Documentation
- Kubernetes Documentation
- Terraform AWS Provider
- Spring Boot Documentation
- GitHub Actions Documentation

---

**Last Updated:** April 13, 2026  
**Status:** ✅ Production Ready
