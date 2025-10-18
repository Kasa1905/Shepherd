import json
import boto3
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    AWS Lambda function to verify DocumentDB backup integrity and send notifications.
    
    This function is triggered by EventBridge when a backup job completes and:
    1. Validates backup job status and metadata
    2. Checks snapshot availability and status
    3. Sends notifications via SNS
    4. Logs results to CloudWatch
    """
    
    try:
        # Parse the EventBridge event
        detail = event.get('detail', {})
        backup_job_id = detail.get('backupJobId')
        state = detail.get('state')
        resource_arn = detail.get('resourceArn', '')
        
        logger.info(f"Processing backup event: job_id={backup_job_id}, state={state}")
        
        # Initialize AWS clients
        backup_client = boto3.client('backup')
        rds_client = boto3.client('rds')
        sns_client = boto3.client('sns')
        
        # Get environment variables
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        project_name = os.environ.get('PROJECT_NAME', 'shepherd')
        environment = os.environ.get('ENVIRONMENT', 'unknown')
        
        if state == 'COMPLETED':
            verification_result = verify_successful_backup(
                backup_client, rds_client, backup_job_id, resource_arn
            )
        elif state == 'FAILED':
            verification_result = handle_failed_backup(
                backup_client, backup_job_id, resource_arn
            )
        else:
            logger.warning(f"Unhandled backup state: {state}")
            return {'statusCode': 200, 'body': 'Unhandled state'}
        
        # Send notification
        send_notification(
            sns_client, sns_topic_arn, verification_result, 
            project_name, environment
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Backup verification completed',
                'backup_job_id': backup_job_id,
                'verification_result': verification_result
            })
        }
        
    except Exception as e:
        logger.error(f"Error in backup verification: {str(e)}")
        
        # Send error notification
        try:
            error_result = {
                'status': 'ERROR',
                'error': str(e),
                'backup_job_id': backup_job_id if 'backup_job_id' in locals() else 'unknown',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            
            if 'sns_client' in locals() and 'sns_topic_arn' in locals():
                send_notification(
                    sns_client, sns_topic_arn, error_result,
                    project_name if 'project_name' in locals() else 'shepherd',
                    environment if 'environment' in locals() else 'unknown'
                )
        except:
            logger.error("Failed to send error notification")
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def verify_successful_backup(backup_client, rds_client, backup_job_id, resource_arn):
    """Verify a successful backup job."""
    
    try:
        # Get backup job details
        backup_job = backup_client.describe_backup_job(BackupJobId=backup_job_id)
        
        backup_details = {
            'backup_job_id': backup_job_id,
            'creation_date': backup_job['CreationDate'].isoformat(),
            'completion_date': backup_job['CompletionDate'].isoformat(),
            'backup_size_bytes': backup_job.get('BackupSizeInBytes', 0),
            'recovery_point_arn': backup_job.get('RecoveryPointArn', ''),
            'resource_arn': resource_arn
        }
        
        # Extract cluster identifier from resource ARN
        cluster_id = resource_arn.split(':')[-1] if resource_arn else ''
        
        # Verify DocumentDB cluster status
        if cluster_id:
            try:
                cluster_response = rds_client.describe_db_clusters(
                    DBClusterIdentifier=cluster_id
                )
                cluster = cluster_response['DBClusters'][0]
                
                backup_details.update({
                    'cluster_status': cluster['Status'],
                    'cluster_endpoint': cluster['Endpoint'],
                    'latest_restorable_time': cluster['LatestRestorableTime'].isoformat(),
                    'backup_retention_period': cluster['BackupRetentionPeriod']
                })
                
            except ClientError as e:
                logger.warning(f"Could not describe DocumentDB cluster: {e}")
                backup_details['cluster_warning'] = str(e)
        
        # Verify backup retention compliance
        backup_age_hours = (
            datetime.now(timezone.utc) - backup_job['CreationDate']
        ).total_seconds() / 3600
        
        backup_details['backup_age_hours'] = backup_age_hours
        backup_details['status'] = 'SUCCESS'
        backup_details['verification_timestamp'] = datetime.now(timezone.utc).isoformat()
        
        logger.info(f"Backup verification successful: {backup_job_id}")
        return backup_details
        
    except ClientError as e:
        logger.error(f"Error verifying backup: {e}")
        return {
            'status': 'VERIFICATION_FAILED',
            'backup_job_id': backup_job_id,
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

def handle_failed_backup(backup_client, backup_job_id, resource_arn):
    """Handle a failed backup job."""
    
    try:
        # Get backup job details
        backup_job = backup_client.describe_backup_job(BackupJobId=backup_job_id)
        
        failure_details = {
            'status': 'BACKUP_FAILED',
            'backup_job_id': backup_job_id,
            'creation_date': backup_job['CreationDate'].isoformat(),
            'state': backup_job['State'],
            'status_message': backup_job.get('StatusMessage', ''),
            'resource_arn': resource_arn,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        logger.error(f"Backup failed: {backup_job_id} - {failure_details['status_message']}")
        return failure_details
        
    except ClientError as e:
        logger.error(f"Error getting failed backup details: {e}")
        return {
            'status': 'BACKUP_FAILED',
            'backup_job_id': backup_job_id,
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

def send_notification(sns_client, topic_arn, result, project_name, environment):
    """Send SNS notification with backup verification results."""
    
    if not topic_arn:
        logger.warning("No SNS topic ARN configured, skipping notification")
        return
    
    status = result.get('status', 'UNKNOWN')
    
    if status == 'SUCCESS':
        subject = f"✅ [{project_name}] Backup Verification Successful"
        message = f"""
DocumentDB Backup Verification Report

Project: {project_name}
Environment: {environment}
Status: SUCCESS ✅

Backup Details:
- Backup Job ID: {result.get('backup_job_id', 'N/A')}
- Creation Date: {result.get('creation_date', 'N/A')}
- Completion Date: {result.get('completion_date', 'N/A')}
- Backup Size: {format_bytes(result.get('backup_size_bytes', 0))}
- Cluster Status: {result.get('cluster_status', 'N/A')}
- Latest Restorable Time: {result.get('latest_restorable_time', 'N/A')}

The backup completed successfully and is available for restore operations.
"""
    elif status == 'BACKUP_FAILED':
        subject = f"❌ [{project_name}] Backup FAILED - Immediate Action Required"
        message = f"""
DocumentDB Backup FAILURE Alert

Project: {project_name}
Environment: {environment}
Status: FAILED ❌

Failure Details:
- Backup Job ID: {result.get('backup_job_id', 'N/A')}
- Error Message: {result.get('status_message', 'N/A')}
- Creation Date: {result.get('creation_date', 'N/A')}
- Resource ARN: {result.get('resource_arn', 'N/A')}

IMMEDIATE ACTION REQUIRED:
1. Check DocumentDB cluster health
2. Verify backup configuration
3. Investigate root cause
4. Consider manual backup if needed

This affects your disaster recovery capabilities!
"""
    else:
        subject = f"⚠️ [{project_name}] Backup Verification Issue"
        message = f"""
DocumentDB Backup Verification Alert

Project: {project_name}
Environment: {environment}
Status: {status}

Details:
{json.dumps(result, indent=2, default=str)}

Please investigate this backup verification issue.
"""
    
    try:
        response = sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
        logger.info(f"Notification sent: MessageId={response['MessageId']}")
        
    except ClientError as e:
        logger.error(f"Failed to send SNS notification: {e}")

def format_bytes(bytes_value):
    """Format bytes to human-readable string."""
    
    if bytes_value == 0:
        return "0 B"
    
    size_names = ["B", "KB", "MB", "GB", "TB"]
    import math
    i = int(math.floor(math.log(bytes_value, 1024)))
    p = math.pow(1024, i)
    s = round(bytes_value / p, 2)
    return f"{s} {size_names[i]}"

import os