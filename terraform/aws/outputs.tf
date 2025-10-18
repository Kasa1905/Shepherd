# Outputs for Shepherd Configuration Management System - AWS Infrastructure

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

# Load Balancer Outputs
output "alb_hostname" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.app.arn
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.main.id
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "ecs_task_definition_arn" {
  description = "Full ARN of the Task Definition"
  value       = aws_ecs_task_definition.app.arn
}

# DocumentDB Outputs
output "documentdb_cluster_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = aws_docdb_cluster.main.endpoint
}

output "documentdb_reader_endpoint" {
  description = "DocumentDB cluster reader endpoint"
  value       = aws_docdb_cluster.main.reader_endpoint
}

output "documentdb_cluster_identifier" {
  description = "DocumentDB cluster identifier"
  value       = aws_docdb_cluster.main.cluster_identifier
}

output "documentdb_cluster_arn" {
  description = "DocumentDB cluster ARN"
  value       = aws_docdb_cluster.main.arn
}

output "documentdb_port" {
  description = "DocumentDB cluster port"
  value       = aws_docdb_cluster.main.port
}

# Enhanced DocumentDB HA and DR Outputs
output "documentdb_backup_retention_period" {
  description = "DocumentDB backup retention period in days"
  value       = aws_docdb_cluster.main.backup_retention_period
}

output "documentdb_availability_zones" {
  description = "Availability zones where DocumentDB instances are deployed"
  value       = aws_docdb_cluster_instance.cluster_instances[*].availability_zone
}

output "documentdb_latest_restorable_time" {
  description = "Latest time to which a DocumentDB database can be restored with point-in-time restore"
  value       = aws_docdb_cluster.main.latest_restorable_time
}

output "documentdb_backup_window" {
  description = "DocumentDB backup window"
  value       = aws_docdb_cluster.main.preferred_backup_window
}

output "documentdb_maintenance_window" {
  description = "DocumentDB maintenance window"
  value       = aws_docdb_cluster.main.preferred_maintenance_window
}

output "cloudwatch_alarm_arns" {
  description = "ARNs of CloudWatch alarms for DR monitoring"
  value = [
    aws_cloudwatch_metric_alarm.docdb_cpu_high.arn,
    aws_cloudwatch_metric_alarm.docdb_storage_low.arn,
    aws_cloudwatch_metric_alarm.docdb_connection_count_high.arn
  ]
}

output "backup_notification_topic_arn" {
  description = "ARN of SNS topic for backup notifications"
  value       = aws_sns_topic.dr_notifications.arn
}

output "disaster_recovery_summary" {
  description = "Summary of disaster recovery configuration"
  value = {
    rto_target_minutes              = var.rto_target_minutes
    rpo_target_minutes              = var.rpo_target_minutes
    backup_retention_days           = var.documentdb_backup_retention_period
    multi_az_enabled               = length(toset(aws_docdb_cluster_instance.cluster_instances[*].availability_zone)) > 1
    encryption_enabled             = var.documentdb_storage_encrypted
    deletion_protection_enabled    = var.documentdb_deletion_protection
    instance_count                 = length(aws_docdb_cluster_instance.cluster_instances)
    availability_zones             = toset(aws_docdb_cluster_instance.cluster_instances[*].availability_zone)
    backup_window                  = aws_docdb_cluster.main.preferred_backup_window
    maintenance_window             = aws_docdb_cluster.main.preferred_maintenance_window
    cross_region_backup_enabled    = var.enable_cross_region_backup
  }
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

output "documentdb_security_group_id" {
  description = "ID of the DocumentDB security group"
  value       = aws_security_group.documentdb.id
}

# IAM Outputs
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.arn
}

# Auto Scaling Outputs
output "autoscaling_target_resource_id" {
  description = "Resource ID of the auto scaling target"
  value       = aws_appautoscaling_target.target.resource_id
}

output "scale_up_policy_arn" {
  description = "ARN of the scale up policy"
  value       = aws_appautoscaling_policy.up.arn
}

output "scale_down_policy_arn" {
  description = "ARN of the scale down policy"
  value       = aws_appautoscaling_policy.down.arn
}

# Connection Information
output "application_url" {
  description = "URL to access the Shepherd application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "URL for health check endpoint"
  value       = "http://${aws_lb.main.dns_name}/api/health"
}

output "metrics_url" {
  description = "URL for Prometheus metrics endpoint"
  value       = "http://${aws_lb.main.dns_name}/metrics"
}

# ECR Repository Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.shepherd.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.shepherd.arn
}

# SNS Topic Output
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms"
  value       = aws_sns_topic.alarms.arn
}

# MongoDB Connection String
output "mongodb_connection_string" {
  description = "MongoDB connection string for Shepherd application"
  value       = "mongodb://${var.documentdb_master_username}:${var.documentdb_master_password}@${aws_docdb_cluster.main.endpoint}:27017/?ssl=true&ssl_ca_certs=rds-combined-ca-bundle.pem&retryWrites=false"
  sensitive   = true
}

# Environment Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name         = var.project_name
    environment          = var.environment
    aws_region           = var.aws_region
    vpc_cidr             = var.vpc_cidr
    availability_zones   = var.availability_zones
    ecs_cluster_name     = aws_ecs_cluster.main.name
    documentdb_endpoint  = aws_docdb_cluster.main.endpoint
    application_url      = "http://${aws_lb.main.dns_name}"
    log_group           = aws_cloudwatch_log_group.app.name
    fargate_cpu         = var.fargate_cpu
    fargate_memory      = var.fargate_memory
    app_count           = var.app_count
    auto_scaling_range  = "${var.auto_scaling_min_capacity}-${var.auto_scaling_max_capacity}"
  }
}