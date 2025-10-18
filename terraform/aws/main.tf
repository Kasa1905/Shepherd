# Shepherd Configuration Management System - AWS Infrastructure
# Terraform configuration for deploying Shepherd on AWS using ECS Fargate with DocumentDB

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Backend configuration for state management
  # Configure this before running terraform init
  backend "s3" {
    # bucket         = "your-terraform-state-bucket"
    # key            = "shepherd/terraform.tfstate"
    # region         = "us-west-2"
    # dynamodb_table = "terraform-state-lock"
    # encrypt        = true
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "backup_region"
  region = var.dr_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
    Type        = "Public"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
    Type        = "Private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? length(aws_subnet.public) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.project_name}-nat-gw-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(aws_subnet.public) : 0
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? length(aws_subnet.private) : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "${var.project_name}-private-rt-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "private" {
  count          = var.enable_nat_gateway ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-ecs-tasks-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ecs-tasks-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "documentdb" {
  name_prefix = "${var.project_name}-documentdb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB from ECS"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = {
    Name        = "${var.project_name}-documentdb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECR Repository
resource "aws_ecr_repository" "shepherd" {
  name                 = "${var.project_name}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle_policy {
    policy = jsonencode({
      rules = [
        {
          rulePriority = 1
          description  = "Keep last 10 images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = ["v"]
            countType     = "imageCountMoreThan"
            countNumber   = 10
          }
          action = {
            type = "expire"
          }
        }
      ]
    })
  }

  tags = {
    Name        = "${var.project_name}-ecr"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecsTaskExecutionRole"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecsTaskRole"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DocumentDB Subnet Group
resource "aws_docdb_subnet_group" "main" {
  name       = "${var.project_name}-docdb-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-docdb-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DocumentDB Cluster with Enhanced HA and Backup Configuration
resource "aws_docdb_cluster" "main" {
  cluster_identifier              = "${var.project_name}-docdb-cluster"
  engine                         = "docdb"
  master_username                = var.documentdb_master_username
  master_password                = var.documentdb_master_password
  
  # Enhanced backup configuration
  backup_retention_period        = var.documentdb_backup_retention_period
  preferred_backup_window        = var.documentdb_preferred_backup_window
  preferred_maintenance_window   = var.documentdb_preferred_maintenance_window
  
  # Security and compliance
  storage_encrypted              = var.documentdb_storage_encrypted
  deletion_protection           = var.documentdb_deletion_protection
  final_snapshot_identifier     = var.skip_final_snapshot ? null : "${var.project_name}-docdb-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  skip_final_snapshot           = var.skip_final_snapshot
  
  # Network configuration
  db_subnet_group_name          = aws_docdb_subnet_group.main.name
  vpc_security_group_ids        = [aws_security_group.documentdb.id]
  
  # Logging configuration
  enabled_cloudwatch_logs_exports = var.documentdb_enabled_cloudwatch_logs_exports
  
  # Apply immediately for critical updates
  apply_immediately             = var.environment == "production" ? false : true

  tags = merge(
    {
      Name        = "${var.project_name}-docdb-cluster"
      Environment = var.environment
      Project     = var.project_name
    },
    var.environment == "production" ? {
      BackupRetention = "${var.documentdb_backup_retention_period}-days"
      DRTier         = "critical"
      Compliance     = "30-day-retention"
    } : {}
  )
}

# DocumentDB Cluster Instances with Multi-AZ Distribution
resource "aws_docdb_cluster_instance" "cluster_instances" {
  count              = var.documentdb_instance_count
  identifier         = "${var.project_name}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.documentdb_instance_class
  
  # Distribute instances across multiple AZs for HA
  availability_zone         = var.availability_zones[count.index % length(var.availability_zones)]
  auto_minor_version_upgrade = true
  preferred_maintenance_window = var.documentdb_preferred_maintenance_window

  tags = {
    Name        = "${var.project_name}-docdb-${count.index}"
    Environment = var.environment
    Project     = var.project_name
    AZ          = var.availability_zones[count.index % length(var.availability_zones)]
  }
}

# Initial manual snapshot for baseline backup
resource "aws_docdb_cluster_snapshot" "initial" {
  count                          = var.environment == "production" ? 1 : 0
  db_cluster_identifier         = aws_docdb_cluster.main.id
  db_cluster_snapshot_identifier = "${var.project_name}-initial-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = {
    Name        = "${var.project_name}-initial-snapshot"
    Environment = var.environment
    Project     = var.project_name
    Type        = "manual"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "ca-bundle-downloader"
      image = "amazonlinux:2"
      essential = false
      command = [
        "/bin/sh",
        "-c",
        "curl -o /shared/rds-combined-ca-bundle.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem && chmod 644 /shared/rds-combined-ca-bundle.pem"
      ]
      mountPoints = [
        {
          sourceVolume  = "ca-certificates"
          containerPath = "/shared"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ca-bundle"
        }
      }
    },
    {
      name  = var.project_name
      image = var.app_image
      dependsOn = [
        {
          containerName = "ca-bundle-downloader"
          condition     = "SUCCESS"
        }
      ]
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
        }
      ]
      essential = true
      mountPoints = [
        {
          sourceVolume  = "ca-certificates"
          containerPath = "/opt/ssl"
          readOnly      = true
        }
      ]
      environment = [
        {
          name  = "FLASK_ENV"
          value = var.environment == "production" ? "production" : "development"
        },
        {
          name  = "FLASK_DEBUG"
          value = var.environment == "production" ? "False" : "True"
        },
        {
          name  = "MONGODB_URI"
          value = "mongodb://${var.documentdb_master_username}:${var.documentdb_master_password}@${aws_docdb_cluster.main.endpoint}:27017/?ssl=true&ssl_ca_certs=/opt/ssl/rds-combined-ca-bundle.pem&retryWrites=false"
        },
        {
          name  = "SSL_CA_CERTS"
          value = "/opt/ssl/rds-combined-ca-bundle.pem"
        },
        {
          name  = "DATABASE_NAME"
          value = var.database_name
        },
        {
          name  = "SECRET_KEY"
          value = var.secret_key
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "LOG_FORMAT"
          value = "json"
        },
        {
          name  = "LOG_LEVEL"
          value = var.log_level
        },
        {
          name  = "METRICS_ENABLED"
          value = "True"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name = "ca-certificates"
  }

  tags = {
    Name        = "${var.project_name}-task-definition"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.web, aws_iam_role_policy_attachment.ecs_task_execution_role_policy]

  tags = {
    Name        = "${var.project_name}-service"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.auto_scaling_min_capacity
  max_capacity       = var.auto_scaling_max_capacity
}

resource "aws_appautoscaling_policy" "up" {
  name               = "${var.project_name}-scale-up"
  service_namespace  = aws_appautoscaling_target.target.service_namespace
  resource_id        = aws_appautoscaling_target.target.resource_id
  scalable_dimension = aws_appautoscaling_target.target.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "down" {
  name               = "${var.project_name}-scale-down"
  service_namespace  = aws_appautoscaling_target.target.service_namespace
  resource_id        = aws_appautoscaling_target.target.resource_id
  scalable_dimension = aws_appautoscaling_target.target.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Name        = "${var.project_name}-alarms"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.alarms_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarms_email
}

# CloudWatch Metric Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ecs cpu utilization"
  alarm_actions       = [
    aws_appautoscaling_policy.up.arn,
    aws_sns_topic.alarms.arn
  ]

  dimensions = {
    ServiceName = aws_ecs_service.main.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = {
    Name        = "${var.project_name}-cpu-utilization-high"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-utilization-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ecs cpu utilization"
  alarm_actions       = [
    aws_appautoscaling_policy.down.arn,
    aws_sns_topic.alarms.arn
  ]

  dimensions = {
    ServiceName = aws_ecs_service.main.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = {
    Name        = "${var.project_name}-cpu-utilization-low"
    Environment = var.environment
    Project     = var.project_name
  }
}

# SNS Topic for DR Notifications
resource "aws_sns_topic" "dr_notifications" {
  name = "${var.project_name}-dr-notifications"

  tags = {
    Name        = "${var.project_name}-dr-notifications"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic_subscription" "dr_email" {
  count     = var.backup_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.dr_notifications.arn
  protocol  = "email"
  endpoint  = var.backup_notification_email
}

# CloudWatch Alarms for DocumentDB Monitoring
resource "aws_cloudwatch_metric_alarm" "docdb_cpu_high" {
  alarm_name          = "${var.project_name}-docdb-cpu-high"
  alarm_description   = "DocumentDB CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.dr_notifications.arn]
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DocDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_docdb_cluster.main.cluster_identifier
  }

  tags = {
    Name        = "${var.project_name}-docdb-cpu-high"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "docdb_storage_low" {
  alarm_name          = "${var.project_name}-docdb-storage-low"
  alarm_description   = "DocumentDB free storage space is low"
  alarm_actions       = [aws_sns_topic.dr_notifications.arn]
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/DocDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2147483648" # 2GB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_docdb_cluster.main.cluster_identifier
  }

  tags = {
    Name        = "${var.project_name}-docdb-storage-low"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "docdb_connection_count_high" {
  alarm_name          = "${var.project_name}-docdb-connections-high"
  alarm_description   = "DocumentDB connection count is high"
  alarm_actions       = [aws_sns_topic.dr_notifications.arn]
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/DocDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "40" # Adjust based on instance size
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_docdb_cluster.main.cluster_identifier
  }

  tags = {
    Name        = "${var.project_name}-docdb-connections-high"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Group for DocumentDB Logs
resource "aws_cloudwatch_log_group" "docdb_audit" {
  count             = contains(var.documentdb_enabled_cloudwatch_logs_exports, "audit") ? 1 : 0
  name              = "/aws/docdb/${aws_docdb_cluster.main.cluster_identifier}/audit"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-docdb-audit-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "docdb_profiler" {
  count             = contains(var.documentdb_enabled_cloudwatch_logs_exports, "profiler") ? 1 : 0
  name              = "/aws/docdb/${aws_docdb_cluster.main.cluster_identifier}/profiler"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-docdb-profiler-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}