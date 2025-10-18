# Variables for Shepherd Configuration Management System - AWS Infrastructure

# General Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "shepherd"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-west-1, etc."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# ECS Configuration
variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
  type        = number
  default     = 512
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)"
  type        = number
  default     = 1024
}

variable "app_image" {
  description = "Docker image to run in the ECS cluster"
  type        = string
  default     = "nginx:latest"  # Replace with your Shepherd image
}

variable "app_count" {
  description = "Number of docker containers to run"
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  type        = number
  default     = 5000
}

variable "docker_image" {
  description = "Docker image to deploy (e.g., your-account.dkr.ecr.region.amazonaws.com/shepherd:latest)"
  type        = string
  default     = "shepherd:latest"
  
  validation {
    condition     = length(var.docker_image) > 0
    error_message = "Docker image must not be empty."
  }
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "alarms_email" {
  description = "Email address for CloudWatch alarms notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alarms_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[A-Za-z]{2,}$", var.alarms_email))
    error_message = "Alarms email must be a valid email address or empty."
  }
}

# Auto Scaling Configuration
variable "auto_scaling_min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 1
}

variable "auto_scaling_max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 6
}

# DocumentDB Configuration
variable "documentdb_master_username" {
  description = "Username for the DocumentDB cluster master DB user"
  type        = string
  default     = "shepherd"
}

variable "documentdb_master_password" {
  description = "Password for the DocumentDB cluster master DB user"
  type        = string
  sensitive   = true
}

variable "documentdb_instance_count" {
  description = "Number of DocumentDB instances"
  type        = number
  default     = 3
}

variable "documentdb_instance_class" {
  description = "Instance class for DocumentDB instances"
  type        = string
  default     = "db.t3.medium"
}

variable "documentdb_backup_retention_period" {
  description = "Backup retention period for DocumentDB (1-35 days)"
  type        = number
  default     = 30  # Changed from 7 to 30 for enterprise compliance
  
  validation {
    condition     = var.documentdb_backup_retention_period >= 1 && var.documentdb_backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "documentdb_preferred_backup_window" {
  description = "Preferred backup window for DocumentDB (UTC)"
  type        = string
  default     = "03:00-05:00"  # Changed to off-peak hours
}

variable "documentdb_preferred_maintenance_window" {
  description = "Preferred maintenance window for DocumentDB (UTC)"
  type        = string
  default     = "sun:05:00-sun:07:00"
  
  validation {
    condition = can(regex("^(sun|mon|tue|wed|thu|fri|sat):[0-9]{2}:[0-9]{2}-(sun|mon|tue|wed|thu|fri|sat):[0-9]{2}:[0-9]{2}$", var.documentdb_preferred_maintenance_window))
    error_message = "Maintenance window must be in format: day:hh:mm-day:hh:mm"
  }
}

variable "documentdb_storage_encrypted" {
  description = "Enable storage encryption for DocumentDB"
  type        = bool
  default     = true
}

variable "documentdb_deletion_protection" {
  description = "Enable deletion protection for DocumentDB cluster"
  type        = bool
  default     = true
}

variable "documentdb_enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["audit", "profiler"]
  
  validation {
    condition = alltrue([
      for log_type in var.documentdb_enabled_cloudwatch_logs_exports :
      contains(["audit", "profiler"], log_type)
    ])
    error_message = "Log types must be from: audit, profiler."
  }
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication for disaster recovery"
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "Disaster recovery region for cross-region backups"
  type        = string
  default     = "us-east-1"
}

variable "backup_notification_email" {
  description = "Email address for backup failure notifications"
  type        = string
  default     = ""
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective in minutes for documentation"
  type        = number
  default     = 60
}

variable "rpo_target_minutes" {
  description = "Recovery Point Objective in minutes for documentation"
  type        = number
  default     = 15
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting DocumentDB cluster"
  type        = bool
  default     = false
}

# Application Configuration
variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "shepherd_cms"
}

variable "secret_key" {
  description = "Flask secret key"
  type        = string
  sensitive   = true
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Monitoring and Logging
variable "log_retention_in_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 14
}

# Security Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for Load Balancer"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}