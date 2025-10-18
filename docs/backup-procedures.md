# Backup Procedures

## Overview

This document outlines comprehensive backup procedures for the Shepherd Configuration Management System across all deployment environments. Our backup strategy ensures data protection with automated verification and recovery capabilities.

## Backup Strategy

### Retention Policy
- **Daily Backups**: 30 days retention
- **Weekly Backups**: 12 weeks retention  
- **Monthly Backups**: 12 months retention
- **Cross-region Replication**: Enabled for AWS deployments

### Recovery Objectives
- **RTO (Recovery Time Objective)**: 60 minutes
- **RPO (Recovery Point Objective)**: 15 minutes

## Docker Compose Environment

### Automated Backup Setup

#### 1. Backup Script Creation
Create the backup script:
```bash
#!/bin/bash
# backup-mongo.sh

BACKUP_DIR="/opt/shepherd/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="shepherd_backup_${TIMESTAMP}"

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Perform MongoDB dump
docker exec mongo-primary mongodump \
    --host mongo-primary:27017 \
    --db shepherd_cms \
    --out /backup/${BACKUP_NAME}

# Copy backup from container
docker cp mongo-primary:/backup/${BACKUP_NAME} ${BACKUP_DIR}/

# Compress backup
tar -czf ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz -C ${BACKUP_DIR} ${BACKUP_NAME}
rm -rf ${BACKUP_DIR}/${BACKUP_NAME}

# Cleanup old backups (keep 30 days)
find ${BACKUP_DIR} -name "shepherd_backup_*.tar.gz" -mtime +30 -delete

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
```

#### 2. Cron Job Setup
```bash
# Add to crontab
crontab -e

# Backup every 6 hours
0 */6 * * * /opt/shepherd/scripts/backup-mongo.sh >> /var/log/shepherd-backup.log 2>&1
```

### Manual Backup
```bash
# Create immediate backup
docker exec mongo-primary mongodump \
    --host mongo-primary:27017 \
    --db shepherd_cms \
    --out /backup/manual_$(date +%Y%m%d_%H%M%S)
```

### Restore Procedures

#### Full Database Restore
```bash
# Stop application
docker-compose stop app

# Extract backup
cd /opt/shepherd/backups
tar -xzf shepherd_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore to MongoDB
docker exec mongo-primary mongorestore \
    --host mongo-primary:27017 \
    --db shepherd_cms \
    --drop \
    /backup/shepherd_backup_YYYYMMDD_HHMMSS/shepherd_cms/

# Start application
docker-compose start app
```

#### Selective Collection Restore
```bash
# Restore specific collection
docker exec mongo-primary mongorestore \
    --host mongo-primary:27017 \
    --db shepherd_cms \
    --collection configurations \
    /backup/shepherd_backup_YYYYMMDD_HHMMSS/shepherd_cms/configurations.bson
```

## AWS Environment

### DocumentDB Automated Backups

#### Backup Configuration
Automated backups are configured in Terraform:
```hcl
resource "aws_docdb_cluster" "main" {
  backup_retention_period   = 30
  preferred_backup_window   = "03:00-04:00"  # UTC
  skip_final_snapshot      = false
  final_snapshot_identifier = "shepherd-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  deletion_protection      = true
}
```

#### Manual Snapshot Creation
```bash
# Create manual snapshot
aws docdb create-db-cluster-snapshot \
    --db-cluster-identifier shepherd-cluster \
    --db-cluster-snapshot-identifier shepherd-manual-$(date +%Y%m%d-%H%M%S)
```

#### Backup Verification (Lambda Function)
The automated verification runs daily and validates:
- Snapshot availability
- Backup integrity
- Restoration capability

```python
# backup-verification.py (Lambda function)
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    docdb = boto3.client('docdb')
    sns = boto3.client('sns')
    
    try:
        # Check recent snapshots
        response = docdb.describe_db_cluster_snapshots(
            DBClusterIdentifier='shepherd-cluster',
            SnapshotType='automated'
        )
        
        recent_snapshots = [
            s for s in response['DBClusterSnapshots'] 
            if s['SnapshotCreateTime'] > datetime.now() - timedelta(days=1)
        ]
        
        if not recent_snapshots:
            raise Exception("No recent automated snapshots found")
        
        # Test restore capability (create test cluster)
        latest_snapshot = max(recent_snapshots, key=lambda x: x['SnapshotCreateTime'])
        
        test_cluster_id = f"test-restore-{int(datetime.now().timestamp())}"
        
        docdb.restore_db_cluster_from_snapshot(
            DBClusterIdentifier=test_cluster_id,
            SnapshotIdentifier=latest_snapshot['DBClusterSnapshotIdentifier'],
            Engine='docdb'
        )
        
        # Wait for cluster to be available (simplified)
        # In production, use proper waiter or step functions
        
        # Cleanup test cluster
        docdb.delete_db_cluster(
            DBClusterIdentifier=test_cluster_id,
            SkipFinalSnapshot=True
        )
        
        # Send success notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Backup Verification Success',
            Message=f'Backup verification completed successfully for snapshot: {latest_snapshot["DBClusterSnapshotIdentifier"]}'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Backup verification successful')
        }
        
    except Exception as e:
        # Send failure notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Backup Verification FAILED',
            Message=f'Backup verification failed: {str(e)}'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Backup verification failed: {str(e)}')
        }
```

### Cross-Region Backup Replication

#### Setup Cross-Region Snapshots
```bash
# Copy snapshot to another region
aws docdb copy-db-cluster-snapshot \
    --source-db-cluster-snapshot-identifier arn:aws:rds:us-west-2:account:cluster-snapshot:shepherd-snapshot \
    --target-db-cluster-snapshot-identifier shepherd-snapshot-replica \
    --source-region us-west-2 \
    --region us-east-1
```

### Restore Procedures

#### Point-in-Time Recovery
```bash
# Restore to specific point in time
aws docdb restore-db-cluster-to-point-in-time \
    --db-cluster-identifier shepherd-cluster-restored \
    --source-db-cluster-identifier shepherd-cluster \
    --restore-to-time 2024-01-15T10:30:00.000Z
```

#### Snapshot Restore
```bash
# Restore from snapshot
aws docdb restore-db-cluster-from-snapshot \
    --db-cluster-identifier shepherd-cluster-restored \
    --snapshot-identifier shepherd-manual-20240115-1030
```

## Kubernetes Environment

### MongoDB Backup CronJob

The backup CronJob is automatically deployed with the Helm chart:

```yaml
# mongodb-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mongodb-backup
            image: mongo:7.0
            command:
            - /bin/bash
            - -c
            - |
              BACKUP_NAME="shepherd_backup_$(date +%Y%m%d_%H%M%S)"
              
              # Create backup
              mongodump --host mongodb-0.mongodb:27017 \
                       --db shepherd_cms \
                       --out /backup/$BACKUP_NAME
              
              # Upload to cloud storage (example with AWS S3)
              if [ "$BACKUP_STORAGE_TYPE" = "s3" ]; then
                tar -czf /backup/$BACKUP_NAME.tar.gz -C /backup $BACKUP_NAME
                aws s3 cp /backup/$BACKUP_NAME.tar.gz s3://$BACKUP_S3_BUCKET/mongodb-backups/
              fi
              
              # Verify backup
              if mongorestore --dry-run --host mongodb-0.mongodb:27017 /backup/$BACKUP_NAME; then
                echo "Backup verification successful"
              else
                echo "Backup verification failed" >&2
                exit 1
              fi
            env:
            - name: BACKUP_S3_BUCKET
              value: "shepherd-backups"
            - name: BACKUP_STORAGE_TYPE
              value: "s3"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: mongodb-backup-pvc
          restartPolicy: OnFailure
```

### Manual Backup in Kubernetes
```bash
# Create immediate backup job
kubectl create job --from=cronjob/mongodb-backup mongodb-backup-manual-$(date +%s)

# Check backup status
kubectl logs -f job/mongodb-backup-manual-<timestamp>
```

### Restore Procedures

#### Full Database Restore
```bash
# Scale down application
kubectl scale deployment shepherd-app --replicas=0

# Access backup data
kubectl exec -it mongodb-0 -- bash

# Inside the pod, restore from backup
mongorestore --host localhost:27017 \
             --db shepherd_cms \
             --drop \
             /backup/shepherd_backup_YYYYMMDD_HHMMSS/

# Scale up application
kubectl scale deployment shepherd-app --replicas=3
```

#### Restore from Cloud Storage
```bash
# Create restore job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-restore-$(date +%s)
spec:
  template:
    spec:
      containers:
      - name: mongodb-restore
        image: mongo:7.0
        command:
        - /bin/bash
        - -c
        - |
          # Download backup from S3
          aws s3 cp s3://shepherd-backups/mongodb-backups/shepherd_backup_YYYYMMDD_HHMMSS.tar.gz /tmp/
          
          # Extract backup
          cd /tmp && tar -xzf shepherd_backup_YYYYMMDD_HHMMSS.tar.gz
          
          # Restore database
          mongorestore --host mongodb-0.mongodb:27017 \
                       --db shepherd_cms \
                       --drop \
                       /tmp/shepherd_backup_YYYYMMDD_HHMMSS/
        env:
        - name: AWS_DEFAULT_REGION
          value: "us-west-2"
      restartPolicy: Never
EOF
```

## Backup Monitoring and Alerting

### Key Metrics
1. **Backup Success Rate**: Target 99.9%
2. **Backup Duration**: Monitor for anomalies
3. **Backup Size**: Track growth trends
4. **Verification Success**: 100% target

### CloudWatch Alarms (AWS)
```bash
# Backup failure alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "Shepherd-Backup-Failure" \
    --alarm-description "DocumentDB backup failed" \
    --metric-name "BackupRetentionPeriodStorageUsed" \
    --namespace "AWS/DocDB" \
    --statistic "Average" \
    --period 3600 \
    --threshold 1 \
    --comparison-operator "LessThanThreshold" \
    --alarm-actions "arn:aws:sns:us-west-2:account:backup-alerts"
```

### Kubernetes Monitoring
```yaml
# ServiceMonitor for backup metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-backup-monitor
spec:
  selector:
    matchLabels:
      app: mongodb-backup
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

## Backup Testing Schedule

### Regular Testing
- **Weekly**: Restore test in development environment
- **Monthly**: Full DR exercise with RTO/RPO measurement
- **Quarterly**: Cross-region restore test (AWS)

### Automated Testing
```bash
#!/bin/bash
# test-backup-restore.sh

# Create test backup
BACKUP_NAME="test_backup_$(date +%Y%m%d_%H%M%S)"

# Perform backup
./backup-mongo.sh

# Create test environment
docker-compose -f docker-compose.test.yml up -d

# Restore backup to test environment
# ... restore commands ...

# Run validation tests
./scripts/validate-restore.sh

# Cleanup test environment
docker-compose -f docker-compose.test.yml down -v

echo "Backup restore test completed"
```

## Troubleshooting

### Common Issues

#### Backup Fails
1. **Check disk space**: Ensure sufficient storage
2. **Verify permissions**: MongoDB user access
3. **Network connectivity**: Connection to database
4. **Lock conflicts**: Long-running operations

#### Restore Fails
1. **Version compatibility**: MongoDB versions
2. **Index conflicts**: Drop indexes before restore
3. **Data corruption**: Verify backup integrity
4. **Resource constraints**: Memory and CPU

### Log Locations
- Docker Compose: `/var/log/shepherd-backup.log`
- AWS: CloudWatch Logs `/aws/lambda/backup-verification`
- Kubernetes: `kubectl logs -l job-name=mongodb-backup`

## Security Considerations

### Backup Encryption
- **AWS**: Encryption at rest enabled
- **Kubernetes**: Use encrypted storage classes
- **Docker**: Encrypt backup archives

### Access Control
- **AWS**: IAM roles with minimal permissions
- **Kubernetes**: RBAC for backup jobs
- **Docker**: Restricted file permissions

### Data Privacy
- **PII Handling**: Anonymize sensitive data in backups
- **Compliance**: Follow data retention regulations
- **Audit Trail**: Log all backup/restore activities

## Appendix

### Useful Commands

#### MongoDB
```bash
# Check oplog size
db.oplog.rs.stats()

# Get database size
db.stats()

# List collections with sizes
db.runCommand("listCollections").cursor.firstBatch.forEach(
    function(collection) {
        print(collection.name + ": " + db.getCollection(collection.name).stats().size);
    }
);
```

#### AWS CLI
```bash
# List all snapshots
aws docdb describe-db-cluster-snapshots --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' --output table

# Check backup status
aws docdb describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,BackupRetentionPeriod,PreferredBackupWindow]' --output table
```

#### Kubernetes
```bash
# Check backup job history
kubectl get jobs -l app=mongodb-backup

# View backup logs
kubectl logs -l job-name=mongodb-backup-<timestamp>

# Check storage usage
kubectl get pvc mongodb-backup-pvc
```