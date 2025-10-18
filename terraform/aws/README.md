# Shepherd Configuration Management System - AWS Infrastructure

This directory contains Terraform configuration files for deploying Shepherd Configuration Management System on AWS using Amazon ECS with Fargate and Amazon DocumentDB with enterprise-grade High Availability and Disaster Recovery capabilities.

## Architecture Overview

### Core Infrastructure
The infrastructure deploys:

- **VPC**: Custom VPC with public and private subnets across multiple AZs
- **Application Load Balancer**: Public-facing ALB for HTTP/HTTPS traffic with health checks on `/api/health`
- **ECS Fargate**: Containerized application deployment with auto-scaling
- **ECR Repository**: Docker image registry with lifecycle policies
- **DocumentDB**: MongoDB-compatible database with multi-AZ deployment
- **CloudWatch**: Centralized logging and monitoring with structured JSON logs
- **SNS Topic**: Alarm notifications via email
- **Auto Scaling**: Automatic scaling based on CPU utilization
- **Security Groups**: Network-level security controls
- **IAM Roles**: Least-privilege access for ECS tasks
- **S3 + DynamoDB**: Terraform state backend (commented configuration)

### High Availability & Disaster Recovery Features

- **Multi-AZ DocumentDB Cluster**: Automatic failover with read replicas
- **Automated Backup System**: 30-day retention with point-in-time recovery
- **Cross-Region Backup Replication**: Disaster recovery capabilities
- **Backup Verification**: Lambda-based automated backup testing
- **CloudWatch Monitoring**: Comprehensive metrics and alerting
- **SNS Notifications**: Real-time alerts for backup failures and health issues

### RTO/RPO Targets
- **Recovery Time Objective (RTO)**: 60 minutes
- **Recovery Point Objective (RPO)**: 15 minutes
- **Backup Retention**: 30 days
- **Cross-Region Replication**: Enabled for disaster recovery

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** v1.0 or later installed
3. **Docker image** of Shepherd application (will be referenced via `docker_image` variable)
4. **S3 bucket and DynamoDB table** for Terraform state backend (optional but recommended)
5. **SSL Certificate** ARN for HTTPS (optional)
6. **Email address** for CloudWatch alarm notifications (required for DR alerts)
7. **AWS permissions** for creating VPC, ECS, DocumentDB, ALB, ECR, SNS, Lambda, AWS Backup, and related resources

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/aws
```

### 2. Configure Backend (Optional but Recommended)

Uncomment and configure the S3 backend in `main.tf`:

```terraform
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "shepherd/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

### 3. Configure Variables

Create `terraform.tfvars`:

```hcl
# Basic Configuration
project_name = "shepherd-cms"
environment  = "production"
aws_region   = "us-west-2"

# Application Configuration
docker_image = "your-account.dkr.ecr.us-west-2.amazonaws.com/shepherd:latest"

# HA/DR Configuration
documentdb_backup_retention_period = 30
documentdb_deletion_protection     = true
cross_region_backup_enabled        = true
backup_verification_enabled        = true

# Monitoring Configuration
alarm_email = "alerts@yourcompany.com"
enable_detailed_monitoring = true

# Security Configuration
ssl_certificate_arn = "arn:aws:acm:us-west-2:account:certificate/cert-id"
allowed_cidr_blocks = ["0.0.0.0/0"]  # Restrict as needed

# Disaster Recovery Configuration
rto_target_minutes = 60
rpo_target_minutes = 15
```

### 4. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### 5. Verify Deployment

```bash
# Get ALB DNS name
terraform output alb_dns_name

# Test health endpoint
curl https://$(terraform output -raw alb_dns_name)/api/health

# Check DocumentDB cluster status
aws docdb describe-db-clusters --db-cluster-identifier $(terraform output -raw documentdb_cluster_identifier)
```

## High Availability Configuration

### DocumentDB Multi-AZ Setup

The DocumentDB cluster is configured with:

```hcl
resource "aws_docdb_cluster" "main" {
  cluster_identifier      = "${var.project_name}-${var.environment}-cluster"
  engine                 = "docdb"
  master_username        = var.documentdb_username
  master_password        = var.documentdb_password
  
  # HA/DR Configuration
  backup_retention_period   = var.documentdb_backup_retention_period  # 30 days
  preferred_backup_window   = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.project_name}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # Security and Durability
  storage_encrypted        = true
  kms_key_id              = aws_kms_key.documentdb.arn
  deletion_protection     = var.documentdb_deletion_protection
  
  # Enhanced Monitoring
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  
  tags = local.common_tags
}

# Multi-AZ cluster instances
resource "aws_docdb_cluster_instance" "cluster_instances" {
  count              = var.documentdb_instance_count
  identifier         = "${var.project_name}-${var.environment}-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.documentdb_instance_class
  
  # Distribute across AZs
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
}
```

### Automated Backup Verification

The backup verification system includes:

1. **AWS Backup Vault**: Centralized backup management
2. **Lambda Function**: Automated backup testing
3. **EventBridge Rules**: Scheduled verification runs
4. **CloudWatch Alarms**: Backup failure monitoring
5. **SNS Notifications**: Real-time alerts

```bash
# Check backup verification status
aws lambda get-function --function-name shepherd-backup-verification

# View recent backup verification logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/shepherd-backup-verification \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Disaster Recovery Procedures

### Backup Management

```bash
# List available backups
aws docdb describe-db-cluster-snapshots \
  --db-cluster-identifier $(terraform output -raw documentdb_cluster_identifier)

# Create manual snapshot
aws docdb create-db-cluster-snapshot \
  --db-cluster-identifier $(terraform output -raw documentdb_cluster_identifier) \
  --db-cluster-snapshot-identifier shepherd-manual-$(date +%Y%m%d-%H%M%S)

# Restore from snapshot
aws docdb restore-db-cluster-from-snapshot \
  --db-cluster-identifier shepherd-cluster-restored \
  --snapshot-identifier <snapshot-id>
```

### Point-in-Time Recovery

```bash
# Restore to specific point in time
aws docdb restore-db-cluster-to-point-in-time \
  --db-cluster-identifier shepherd-cluster-restored \
  --source-db-cluster-identifier $(terraform output -raw documentdb_cluster_identifier) \
  --restore-to-time 2024-01-15T10:30:00.000Z
```

### Cross-Region Disaster Recovery

```bash
# Copy snapshot to another region for DR
aws docdb copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier arn:aws:rds:us-west-2:account:cluster-snapshot:snapshot-id \
  --target-db-cluster-snapshot-identifier shepherd-dr-snapshot \
  --source-region us-west-2 \
  --region us-east-1

# Deploy infrastructure in DR region
cd terraform/aws
terraform workspace new dr-region
terraform plan -var="aws_region=us-east-1" -var="environment=dr"
terraform apply
```

## Monitoring and Alerting

### CloudWatch Alarms

The infrastructure includes comprehensive monitoring:

- **Database Health**: Connection failures, CPU utilization
- **Application Health**: ECS task health, ALB response times
- **Backup Status**: Backup failures, verification failures
- **Storage**: Database storage usage, backup storage

### Key Metrics to Monitor

```bash
# Database metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=$(terraform output -raw documentdb_cluster_identifier) \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Application metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=$(terraform output -raw ecs_service_name) \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Security Configuration

### Encryption

- **EBS Volumes**: Encrypted with customer-managed KMS keys
- **DocumentDB**: Encryption at rest with KMS
- **ALB**: HTTPS/TLS 1.2 minimum
- **S3**: Server-side encryption for backups

### Network Security

- **Private Subnets**: Database and application in private subnets
- **Security Groups**: Restrictive inbound/outbound rules
- **NAT Gateway**: Secure outbound internet access
- **VPC Endpoints**: Direct AWS service access without internet

### Access Control

- **IAM Roles**: Least-privilege principle
- **Resource-based Policies**: S3 bucket policies
- **KMS Policies**: Key usage restrictions

## Cost Optimization

### Variable Pricing Tiers

```hcl
# Development
documentdb_instance_class = "db.t3.medium"
ecs_task_cpu             = 256
ecs_task_memory          = 512

# Production
documentdb_instance_class = "db.r5.large"
ecs_task_cpu             = 1024
ecs_task_memory          = 2048
```

### Cost Monitoring

```bash
# Estimate monthly costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

#### DocumentDB Connection Issues
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids $(terraform output -raw documentdb_security_group_id)

# Test DocumentDB connectivity from ECS
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task <task-arn> \
  --container shepherd-app \
  --command "mongosh --host $(terraform output -raw documentdb_endpoint)"
```

#### ECS Task Failures
```bash
# Check ECS service events
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name)

# View task logs
aws logs get-log-events \
  --log-group-name /ecs/shepherd-app \
  --log-stream-name <log-stream-name>
```

#### Backup Verification Failures
```bash
# Check Lambda function logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/shepherd-backup-verification \
  --filter-pattern "ERROR"

# Manual backup test
aws lambda invoke \
  --function-name shepherd-backup-verification \
  --payload '{"source":"manual-test"}' \
  response.json
```

## Variables Reference

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `project_name` | Project name for resource naming | `string` | `"shepherd-cms"` |
| `environment` | Environment name | `string` | `"production"` |
| `docker_image` | Docker image URI | `string` | `"account.dkr.ecr.region.amazonaws.com/shepherd:latest"` |

### HA/DR Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `documentdb_backup_retention_period` | Backup retention in days | `number` | `30` |
| `documentdb_deletion_protection` | Enable deletion protection | `bool` | `true` |
| `cross_region_backup_enabled` | Enable cross-region backup | `bool` | `true` |
| `backup_verification_enabled` | Enable automated backup verification | `bool` | `true` |
| `rto_target_minutes` | Recovery Time Objective | `number` | `60` |
| `rpo_target_minutes` | Recovery Point Objective | `number` | `15` |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `aws_region` | AWS region | `string` | `"us-west-2"` |
| `ssl_certificate_arn` | SSL certificate ARN | `string` | `null` |
| `alarm_email` | Email for alerts | `string` | `null` |
| `allowed_cidr_blocks` | Allowed CIDR blocks | `list(string)` | `["0.0.0.0/0"]` |

## Outputs

### Infrastructure Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | Application Load Balancer DNS name |
| `documentdb_endpoint` | DocumentDB cluster endpoint |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_service_name` | ECS service name |

### HA/DR Outputs

| Output | Description |
|--------|-------------|
| `documentdb_cluster_identifier` | DocumentDB cluster identifier |
| `backup_vault_arn` | AWS Backup vault ARN |
| `backup_verification_function_arn` | Lambda function ARN for backup verification |
| `disaster_recovery_summary` | Summary of DR configuration |

## Advanced Configuration

### Custom Domain Setup

```hcl
# Route 53 and ACM certificate
variable "domain_name" {
  description = "Custom domain name"
  type        = string
  default     = null
}

# Add to terraform.tfvars
domain_name = "shepherd.yourdomain.com"
```

### Multi-Environment Setup

```bash
# Create workspace for each environment
terraform workspace new development
terraform workspace new staging
terraform workspace new production

# Deploy to specific environment
terraform workspace select production
terraform plan -var-file="production.tfvars"
terraform apply
```

### Blue-Green Deployment

```hcl
# ECS service configuration for blue-green
deployment_configuration {
  maximum_percent         = 200
  minimum_healthy_percent = 100
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
```

## Clean Up

### Destroy Infrastructure

```bash
# Disable deletion protection first
terraform apply -var="documentdb_deletion_protection=false"

# Destroy all resources
terraform destroy

# Clean up state files
rm -rf .terraform/
rm terraform.tfstate*
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Delete manual snapshots
aws docdb delete-db-cluster-snapshot --db-cluster-snapshot-identifier <snapshot-id>

# Empty and delete S3 buckets
aws s3 rm s3://bucket-name --recursive
aws s3 rb s3://bucket-name

# Delete ECR images
aws ecr list-images --repository-name shepherd
aws ecr batch-delete-image --repository-name shepherd --image-ids imageTag=latest
```

For detailed disaster recovery procedures, see [Disaster Recovery Runbook](../../docs/disaster-recovery.md).

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Create terraform.tfvars

Create a `terraform.tfvars` file with your configuration:

```hcl
# Project Configuration
project_name = "shepherd"
environment  = "production"
aws_region   = "us-west-2"

# Network Configuration
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

# Application Configuration
docker_image = "your-account.dkr.ecr.us-west-2.amazonaws.com/shepherd:latest"
app_count = 2

# DocumentDB Configuration
documentdb_master_password = "YourSecurePassword123!"
secret_key                = "your-very-secure-flask-secret-key"

# Optional Configuration
ssl_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
alarms_email       = "alerts@yourcompany.com"
fargate_cpu        = 1024
fargate_memory     = 2048
log_level          = "INFO"
```

### 5. Plan and Apply

```bash
# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 5. Access Your Application

After deployment completes, get the application URL:

```bash
terraform output application_url
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `documentdb_master_password` | DocumentDB master password | `"SecurePassword123!"` |
| `secret_key` | Flask application secret key | `"your-secret-key"` |

### Important Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | `"shepherd"` | Project name for resource naming |
| `environment` | `"dev"` | Environment name (dev/staging/production) |
| `aws_region` | `"us-west-2"` | AWS region for deployment |
| `app_image` | `"nginx:latest"` | Docker image for Shepherd application |
| `app_count` | `2` | Number of application instances |
| `fargate_cpu` | `512` | CPU units (256, 512, 1024, 2048, 4096) |
| `fargate_memory` | `1024` | Memory in MiB |
| `documentdb_instance_class` | `"db.t3.medium"` | DocumentDB instance size |

## Architecture Details

### Network Design

- **VPC**: `/16` CIDR with DNS hostnames enabled
- **Public Subnets**: `/24` CIDRs for ALB and NAT gateways
- **Private Subnets**: `/24` CIDRs for ECS tasks and DocumentDB
- **Internet Gateway**: For public internet access
- **NAT Gateways**: For outbound internet access from private subnets

### Security

- **ALB Security Group**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS Security Group**: Allows traffic from ALB on application port
- **DocumentDB Security Group**: Allows MongoDB (27017) from ECS tasks only
- **IAM Roles**: Separate execution and task roles with minimal permissions

### High Availability

- **Multi-AZ**: Resources deployed across multiple availability zones
- **Auto Scaling**: Scales between 1-6 instances based on CPU utilization
- **DocumentDB**: Multi-AZ cluster with automated backups
- **Load Balancer**: Health checks and automatic failover

### Monitoring

- **CloudWatch Logs**: Centralized application logging
- **CloudWatch Metrics**: CPU, memory, and custom application metrics
- **Health Checks**: ALB health checks on `/api/health` endpoint
- **Auto Scaling Alarms**: CPU-based scaling triggers

## Outputs

Key outputs after deployment:

```bash
# Application URLs
terraform output application_url      # Main application
terraform output health_check_url     # Health check endpoint
terraform output metrics_url          # Prometheus metrics

# Infrastructure IDs
terraform output vpc_id              # VPC identifier
terraform output ecs_cluster_id      # ECS cluster
terraform output documentdb_cluster_endpoint  # Database endpoint

# Deployment summary
terraform output deployment_summary  # Complete infrastructure overview
```

## Customization

### Environment-Specific Configuration

Create separate `.tfvars` files for different environments:

```bash
# Development
terraform apply -var-file="dev.tfvars"

# Staging
terraform apply -var-file="staging.tfvars"

# Production
terraform apply -var-file="production.tfvars"
```

### Instance Sizing

Adjust resources based on your needs:

```hcl
# Small deployment
fargate_cpu               = 256
fargate_memory           = 512
documentdb_instance_class = "db.t3.medium"
app_count               = 1

# Large deployment
fargate_cpu               = 2048
fargate_memory           = 4096
documentdb_instance_class = "db.r5.large"
app_count               = 4
```

### Auto Scaling Configuration

Customize scaling behavior:

```hcl
auto_scaling_min_capacity = 2
auto_scaling_max_capacity = 10
```

## Cost Optimization

### Development Environment

```hcl
# Minimal cost configuration
fargate_cpu                       = 256
fargate_memory                   = 512
app_count                       = 1
documentdb_instance_count       = 1
documentdb_instance_class       = "db.t3.medium"
enable_nat_gateway              = false  # Use public subnets only
documentdb_backup_retention_period = 1
```

### Production Environment

```hcl
# Production-ready configuration
fargate_cpu                       = 1024
fargate_memory                   = 2048
app_count                       = 3
documentdb_instance_count       = 3
documentdb_instance_class       = "db.r5.large"
enable_nat_gateway              = true
documentdb_backup_retention_period = 30
enable_deletion_protection      = true
```

## Troubleshooting

### Common Issues

1. **ECS Tasks Not Starting**
   - Check CloudWatch logs: `/ecs/shepherd`
   - Verify Docker image accessibility
   - Check ECS task definition environment variables

2. **Database Connection Issues**
   - Verify DocumentDB security group allows ECS access
   - Check MongoDB connection string format
   - Ensure SSL certificates are available in container

3. **Load Balancer Health Checks Failing**
   - Verify application starts on correct port (5000)
   - Check `/api/health` endpoint returns 200
   - Review ECS task logs for startup errors

### Useful Commands

```bash
# View ECS service events
aws ecs describe-services --cluster shepherd-cluster --services shepherd-service

# Check task logs
aws logs tail /ecs/shepherd --follow

# Verify DocumentDB connectivity
aws docdb describe-db-clusters --db-cluster-identifier shepherd-docdb-cluster

# Scale service manually
aws ecs update-service --cluster shepherd-cluster --service shepherd-service --desired-count 3
```

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including the DocumentDB cluster and data.

## Security Considerations

1. **Secrets Management**: Consider using AWS Secrets Manager for sensitive data
2. **SSL/TLS**: Add SSL certificate to ALB for HTTPS termination
3. **Network ACLs**: Add additional network-level controls if required
4. **VPC Flow Logs**: Enable for network traffic monitoring
5. **WAF**: Consider adding AWS WAF for application-level protection

## Support

For infrastructure issues:
1. Check Terraform logs and AWS CloudFormation events
2. Review CloudWatch logs for application errors
3. Verify security group and IAM permissions
4. Consult AWS documentation for service-specific issues

## Integration with Shepherd

This infrastructure automatically configures:
- MongoDB connection string for DocumentDB
- Structured JSON logging to CloudWatch
- Prometheus metrics collection
- Health check endpoints
- Auto-scaling based on CPU utilization

The deployed application will have all Phase 9 observability features enabled and configured for the AWS environment.