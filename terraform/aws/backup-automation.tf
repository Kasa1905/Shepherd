# Backup Automation and Verification for Shepherd DocumentDB
# This file provides automated backup verification and cross-region replication capabilities

# AWS Backup Vault for centralized backup management
resource "aws_backup_vault" "main" {
  name        = "${var.project_name}-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = {
    Name        = "${var.project_name}-backup-vault"
    Environment = var.environment
    Project     = var.project_name
  }
}

# KMS key for backup encryption
resource "aws_kms_key" "backup" {
  description             = "KMS key for ${var.project_name} backup encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-backup-key"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.project_name}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

# AWS Backup Plan for DocumentDB
resource "aws_backup_plan" "main" {
  name = "${var.project_name}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)" # Daily at 2:00 UTC

    lifecycle {
      cold_storage_after = 30
      delete_after       = var.documentdb_backup_retention_period
    }

    recovery_point_tags = {
      BackupType  = "automated"
      Environment = var.environment
      Project     = var.project_name
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_backup ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.cross_region[0].arn

        lifecycle {
          cold_storage_after = 30
          delete_after       = var.documentdb_backup_retention_period
        }
      }
    }
  }

  rule {
    rule_name         = "weekly_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 ? * SUN *)" # Weekly on Sunday at 2:00 UTC

    lifecycle {
      cold_storage_after = 30
      delete_after       = 84 # 12 weeks
    }

    recovery_point_tags = {
      BackupType  = "weekly"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  rule {
    rule_name         = "monthly_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 1 * ? *)" # Monthly on 1st at 2:00 UTC

    lifecycle {
      cold_storage_after = 30
      delete_after       = 365 # 12 months
    }

    recovery_point_tags = {
      BackupType  = "monthly"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  tags = {
    Name        = "${var.project_name}-backup-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cross-region backup vault (conditional)
resource "aws_backup_vault" "cross_region" {
  count       = var.enable_cross_region_backup ? 1 : 0
  name        = "${var.project_name}-backup-vault-dr"
  kms_key_arn = aws_kms_key.backup_cross_region[0].arn

  # Deploy in a different region for DR
  provider = aws.backup_region

  tags = {
    Name        = "${var.project_name}-backup-vault-dr"
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "disaster-recovery"
  }
}

resource "aws_kms_key" "backup_cross_region" {
  count                   = var.enable_cross_region_backup ? 1 : 0
  description             = "KMS key for ${var.project_name} cross-region backup encryption"
  deletion_window_in_days = 7
  
  provider = aws.backup_region

  tags = {
    Name        = "${var.project_name}-backup-key-dr"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Backup selection for DocumentDB
resource "aws_backup_selection" "main" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.project_name}-backup-selection"
  plan_id      = aws_backup_plan.main.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = var.project_name
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Environment"
    value = var.environment
  }
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backup-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Lambda function for backup verification
resource "aws_lambda_function" "backup_verification" {
  filename         = data.archive_file.backup_verification.output_path
  function_name    = "${var.project_name}-backup-verification"
  role            = aws_iam_role.backup_verification_lambda.arn
  handler         = "backup_verification.handler"
  source_code_hash = data.archive_file.backup_verification.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      SNS_TOPIC_ARN           = aws_sns_topic.dr_notifications.arn
      DOCDB_CLUSTER_IDENTIFIER = aws_docdb_cluster.main.cluster_identifier
      PROJECT_NAME            = var.project_name
      ENVIRONMENT             = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-backup-verification"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda function source code
data "archive_file" "backup_verification" {
  type        = "zip"
  output_path = "${path.module}/backup_verification.zip"

  source {
    content = templatefile("${path.module}/backup_verification.py", {
      project_name = var.project_name
    })
    filename = "backup_verification.py"
  }
}

# IAM role for backup verification Lambda
resource "aws_iam_role" "backup_verification_lambda" {
  name = "${var.project_name}-backup-verification-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backup-verification-lambda"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "backup_verification_lambda" {
  name = "${var.project_name}-backup-verification-lambda-policy"
  role = aws_iam_role.backup_verification_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBClusterSnapshots",
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "backup:DescribeBackupJob",
          "backup:DescribeRecoveryPoint",
          "backup:ListBackupJobs"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule to trigger Lambda on backup completion
resource "aws_cloudwatch_event_rule" "backup_completion" {
  name        = "${var.project_name}-backup-completion"
  description = "Trigger backup verification when DocumentDB backup completes"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change"]
    detail = {
      state = ["COMPLETED", "FAILED"]
      resourceType = ["DocumentDB"]
    }
  })

  tags = {
    Name        = "${var.project_name}-backup-completion"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "backup_verification" {
  rule      = aws_cloudwatch_event_rule.backup_completion.name
  target_id = "BackupVerificationTarget"
  arn       = aws_lambda_function.backup_verification.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_verification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_completion.arn
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "backup_verification" {
  name              = "/aws/lambda/${aws_lambda_function.backup_verification.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-backup-verification-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failure" {
  alarm_name          = "${var.project_name}-backup-failure"
  alarm_description   = "DocumentDB backup has failed"
  alarm_actions       = [aws_sns_topic.dr_notifications.arn]
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"

  dimensions = {
    BackupVaultName = aws_backup_vault.main.name
  }

  tags = {
    Name        = "${var.project_name}-backup-failure"
    Environment = var.environment
    Project     = var.project_name
  }
}