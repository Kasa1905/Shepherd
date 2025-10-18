# Disaster Recovery Runbook

## Overview

This document provides comprehensive procedures for disaster recovery scenarios in the Shepherd Configuration Management System. Our HA/DR implementation supports multiple deployment targets with defined Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO).

### RTO/RPO Targets
- **RTO (Recovery Time Objective)**: 60 minutes
- **RPO (Recovery Point Objective)**: 15 minutes
- **Backup Retention**: 30 days
- **Cross-region Replication**: Enabled for AWS deployments

## Deployment Scenarios

### 1. Docker Compose (Development/Testing)

#### Architecture
- 3-node MongoDB replica set (mongo-primary, mongo-secondary-1, mongo-secondary-2)
- Automatic replica set initialization
- Local volume persistence

#### Disaster Scenarios

##### Primary Node Failure
**Detection:**
```bash
# Check replica set status
docker exec mongo-primary mongosh --eval "rs.status()"

# Check application health
curl http://localhost:5000/health
```

**Recovery Steps:**
1. **Automatic Failover**: MongoDB will automatically elect a new primary
2. **Verify New Primary**:
   ```bash
   docker exec mongo-secondary-1 mongosh --eval "rs.isMaster()"
   ```
3. **Replace Failed Container**:
   ```bash
   docker-compose stop mongo-primary
   docker-compose rm mongo-primary
   docker-compose up -d mongo-primary
   ```
4. **Re-add to Replica Set**:
   ```bash
   docker exec mongo-secondary-1 mongosh --eval "rs.add('mongo-primary:27017')"
   ```

##### Complete Environment Loss
**Recovery Steps:**
1. **Restore from Backup** (if available):
   ```bash
   # Restore data volume
   docker volume create mongodb_data_primary
   # Copy backup data to volume
   ```
2. **Restart Environment**:
   ```bash
   docker-compose down -v
   docker-compose up -d
   ```
3. **Verify Replica Set**:
   ```bash
   # Wait for initialization
   sleep 30
   docker exec mongo-primary mongosh --eval "rs.status()"
   ```

### 2. AWS (Production)

#### Architecture
- AWS DocumentDB multi-AZ cluster
- Automated backups with 30-day retention
- Cross-region backup replication
- CloudWatch monitoring and SNS alerts

#### Disaster Scenarios

##### Primary Cluster Failure
**Detection:**
- CloudWatch alarms trigger
- SNS notifications sent
- Application health checks fail

**Recovery Steps:**
1. **Check Cluster Status**:
   ```bash
   aws docdb describe-db-clusters --db-cluster-identifier shepherd-cluster
   ```

2. **Automatic Failover**: DocumentDB handles failover automatically
   - Monitor via CloudWatch metrics
   - Update connection string if needed

3. **Manual Recovery** (if automatic fails):
   ```bash
   # Restore from latest backup
   aws docdb restore-db-cluster-from-snapshot \
     --db-cluster-identifier shepherd-cluster-restored \
     --snapshot-identifier $(aws docdb describe-db-cluster-snapshots \
       --db-cluster-identifier shepherd-cluster \
       --query 'DBClusterSnapshots[0].DBClusterSnapshotIdentifier' \
       --output text)
   ```

##### Region-wide Disaster
**Recovery Steps:**
1. **Activate Cross-Region Backup**:
   ```bash
   # List available backups in secondary region
   aws docdb describe-db-cluster-snapshots \
     --region us-east-1 \
     --snapshot-type shared
   ```

2. **Restore in Secondary Region**:
   ```bash
   aws docdb restore-db-cluster-from-snapshot \
     --region us-east-1 \
     --db-cluster-identifier shepherd-cluster-dr \
     --snapshot-identifier <cross-region-snapshot-id>
   ```

3. **Update Application Configuration**:
   ```bash
   # Update Terraform variables
   export TF_VAR_aws_region="us-east-1"
   export TF_VAR_documentdb_cluster_identifier="shepherd-cluster-dr"
   
   # Redeploy application
   terraform plan -target=aws_ecs_service.shepherd
   terraform apply -target=aws_ecs_service.shepherd
   ```

##### Backup Verification Failure
**Detection**: Lambda function alerts via SNS

**Investigation Steps:**
1. **Check Lambda Logs**:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/shepherd-backup-verification
   ```

2. **Manual Backup Verification**:
   ```bash
   # Test backup restoration
   aws docdb restore-db-cluster-from-snapshot \
     --db-cluster-identifier test-restore \
     --snapshot-identifier <backup-id>
   ```

3. **Fix Issues and Re-run**:
   ```bash
   aws lambda invoke \
     --function-name shepherd-backup-verification \
     --payload '{"source":"manual"}' \
     response.json
   ```

### 3. Kubernetes/Helm (Production)

#### Architecture
- MongoDB StatefulSet with 3 replicas
- Persistent Volume Claims
- Backup CronJobs
- Pod anti-affinity rules

#### Disaster Scenarios

##### Pod Failure
**Detection:**
```bash
# Check pod status
kubectl get pods -l app=mongodb

# Check replica set status
kubectl exec mongodb-0 -- mongosh --eval "rs.status()"
```

**Recovery Steps:**
1. **Automatic Recovery**: Kubernetes will restart failed pods
2. **Manual Intervention** (if needed):
   ```bash
   # Delete problematic pod
   kubectl delete pod mongodb-X
   
   # Verify replica set health
   kubectl exec mongodb-0 -- mongosh --eval "rs.status()"
   ```

##### Persistent Volume Loss
**Recovery Steps:**
1. **Check Backup Status**:
   ```bash
   kubectl get cronjobs mongodb-backup
   kubectl logs -l job-name=mongodb-backup-<timestamp>
   ```

2. **Restore from Backup**:
   ```bash
   # Scale down StatefulSet
   kubectl scale statefulset mongodb --replicas=0
   
   # Restore data from backup
   kubectl create job --from=cronjob/mongodb-backup mongodb-restore-$(date +%s)
   
   # Scale up StatefulSet
   kubectl scale statefulset mongodb --replicas=3
   ```

##### Cluster-wide Failure
**Recovery Steps:**
1. **Backup Current State** (if accessible):
   ```bash
   kubectl create job --from=cronjob/mongodb-backup emergency-backup-$(date +%s)
   ```

2. **Redeploy to New Cluster**:
   ```bash
   # Install Helm chart in new cluster
   helm install shepherd ./helm/shepherd \
     --values ./helm/shepherd/values.yaml \
     --set mongodb.internal.enabled=true
   ```

3. **Restore Data**:
   ```bash
   # Copy backup data to new cluster
   kubectl cp <backup-data> mongodb-0:/tmp/restore/
   
   # Restore database
   kubectl exec mongodb-0 -- mongorestore /tmp/restore/
   ```

## Testing Procedures

### Automated DR Testing
Run the automated DR test script:
```bash
./scripts/test-dr.sh
```

### Manual Testing Checklist

#### Docker Compose
- [ ] Primary node failure simulation
- [ ] Network partition testing
- [ ] Data persistence verification
- [ ] Application connectivity testing

#### AWS
- [ ] Backup restoration testing
- [ ] Cross-region failover
- [ ] Monitoring alert verification
- [ ] RTO/RPO measurement

#### Kubernetes
- [ ] Pod failure simulation
- [ ] PVC backup/restore
- [ ] StatefulSet scaling
- [ ] Service discovery testing

## Monitoring and Alerting

### Key Metrics to Monitor
1. **Database Health**:
   - Connection success rate
   - Query response time
   - Replica set lag

2. **Backup Status**:
   - Backup success rate
   - Backup size and duration
   - Restore test results

3. **Infrastructure Health**:
   - Node/pod availability
   - Resource utilization
   - Network connectivity

### Alert Thresholds
- Replica lag > 60 seconds
- Backup failure > 1 consecutive failure
- Connection failure rate > 5%
- Query response time > 5 seconds

## Recovery Validation

After any recovery procedure:

1. **Verify Application Functionality**:
   ```bash
   # Health check
   curl http://localhost:5000/health
   
   # Database operations
   curl -X POST http://localhost:5000/api/config \
     -H "Content-Type: application/json" \
     -d '{"config_id":"test","app_name":"test","environment":"test","settings":{}}'
   ```

2. **Verify Data Integrity**:
   ```bash
   # Check document counts
   # Verify recent transactions
   # Compare with pre-disaster state
   ```

3. **Performance Testing**:
   ```bash
   # Run load tests
   # Measure response times
   # Verify throughput
   ```

## Emergency Contacts

- **Primary On-call**: [Contact Information]
- **Database Administrator**: [Contact Information]
- **Infrastructure Team**: [Contact Information]
- **Management Escalation**: [Contact Information]

## Post-Incident Review

After any disaster recovery event:

1. Document timeline of events
2. Analyze RTO/RPO achievement
3. Identify improvement opportunities
4. Update procedures based on lessons learned
5. Conduct team debrief session

## Appendix

### Useful Commands

#### MongoDB
```bash
# Check replica set status
rs.status()

# Check oplog size
db.oplog.rs.stats()

# Initiate replica set
rs.initiate()

# Add replica set member
rs.add("hostname:port")
```

#### Docker
```bash
# View container logs
docker logs mongodb-primary

# Execute commands in container
docker exec -it mongodb-primary mongosh

# Copy files to/from container
docker cp file.txt mongodb-primary:/tmp/
```

#### Kubernetes
```bash
# Check pod logs
kubectl logs mongodb-0

# Execute commands in pod
kubectl exec -it mongodb-0 -- mongosh

# Port forward for access
kubectl port-forward mongodb-0 27017:27017
```

#### AWS
```bash
# Check DocumentDB status
aws docdb describe-db-clusters

# Create manual snapshot
aws docdb create-db-cluster-snapshot

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics
```

## Automated DR Testing

### Overview
Regular disaster recovery testing ensures our procedures remain effective and teams stay prepared. The automated DR testing framework validates:

- RTO/RPO compliance
- Backup integrity
- Failover procedures
- Recovery workflows
- Monitoring alerting

### Running DR Tests

#### Automated Test Suite
```bash
# Run comprehensive DR tests
./scripts/test-dr.sh --environment production --type full

# Test specific scenarios
./scripts/test-dr.sh --test failover --deployment kubernetes

# Generate test reports
./scripts/test-dr.sh --report --output /tmp/dr-report.json
```

#### Test Categories

**1. Connectivity Tests**
- Database connectivity validation
- Application health verification
- Network connectivity checks

**2. Failover Tests**
- Primary node failure simulation
- Replica set election verification
- Application reconnection testing

**3. Backup & Recovery Tests**
- Backup integrity validation
- Point-in-time recovery testing
- Cross-region restore verification

**4. Performance Tests**
- RTO measurement (target: 60 minutes)
- RPO validation (target: 15 minutes)
- Service degradation assessment

### Monitoring & Alerting

#### Key Metrics
- **Replica Set Health**: Member status, replication lag
- **Backup Status**: Success rate, backup size, completion time
- **Application Health**: Response time, error rate, uptime
- **Infrastructure**: CPU, memory, disk, network utilization

#### Alert Thresholds
```yaml
replication_lag_seconds: 60
backup_failure_count: 1
response_time_ms: 5000
error_rate_percent: 5
disk_usage_percent: 85
```

#### Alert Channels
- **Critical**: PagerDuty, SMS, Phone
- **Warning**: Email, Slack
- **Info**: Dashboard, Logs

### DR Runbook Validation

#### Monthly Checklist
- [ ] Verify backup completeness and integrity
- [ ] Test primary failover procedure
- [ ] Validate recovery time objectives
- [ ] Update emergency contact list
- [ ] Review and update documentation
- [ ] Train new team members on procedures

#### Quarterly Reviews
- [ ] Full disaster recovery drill
- [ ] RTO/RPO target assessment
- [ ] Infrastructure capacity planning
- [ ] Vendor SLA review
- [ ] Business continuity plan update

### Emergency Response Procedures

#### Incident Classification

**P0 - Critical**
- Complete service outage
- Data loss detected
- Security breach
- RTO: 30 minutes

**P1 - High**
- Partial service degradation
- Primary database failure
- Backup failure
- RTO: 60 minutes

**P2 - Medium**
- Performance degradation
- Secondary service issues
- Monitoring alerts
- RTO: 4 hours

#### Escalation Matrix
1. **On-call Engineer** (0-15 minutes)
2. **Team Lead** (15-30 minutes)
3. **Engineering Manager** (30-60 minutes)
4. **Director of Engineering** (60+ minutes)

#### Communication Templates

**Initial Response (5 minutes)**
```
Subject: [P0] Shepherd CMS Service Outage - Initial Alert

Status: Investigating
Impact: [Describe user impact]
ETA: Investigating
Updates: Every 15 minutes

Next Update: [Time]
```

**Status Update Template**
```
Subject: [P0] Shepherd CMS Service Outage - Update #N

Status: [Investigating/Identified/Fixing/Resolved]
Progress: [What has been done]
Next Steps: [What's being done next]
ETA: [Estimated resolution time]

Next Update: [Time]
```

**Resolution Template**
```
Subject: [P0] Shepherd CMS Service Outage - RESOLVED

Status: RESOLVED
Resolution: [Brief description of fix]
Duration: [Total outage time]
Root Cause: [To be provided in post-mortem]

Post-mortem: [Date/time of review meeting]
```

### Post-Incident Procedures

#### Immediate Actions (0-24 hours)
1. Verify complete service restoration
2. Document timeline of events
3. Gather relevant logs and metrics
4. Prepare preliminary incident report
5. Schedule post-mortem meeting

#### Post-Mortem Process (1-7 days)
1. **Root Cause Analysis**
   - Technical failure points
   - Process breakdowns
   - Human factors

2. **Action Items**
   - Immediate fixes
   - Long-term improvements
   - Prevention measures

3. **Documentation Updates**
   - Runbook improvements
   - Monitoring enhancements
   - Training updates

#### Lessons Learned Integration
- Update DR procedures based on incidents
- Enhance monitoring and alerting
- Improve team training and preparedness
- Review and adjust RTO/RPO targets