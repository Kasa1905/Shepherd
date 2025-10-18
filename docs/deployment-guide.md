# Shepherd Deployment Guide

A comprehensive guide for zero-downtime deployment strategies and procedures.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Rolling Update Deployments](#rolling-update-deployments)
- [Blue/Green Deployments](#blue-green-deployments)
- [Canary Deployments](#canary-deployments)
- [Rollback Procedures](#rollback-procedures)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)
- [Deployment Checklist](#deployment-checklist)
- [Post-Deployment Validation](#post-deployment-validation)
- [Emergency Procedures](#emergency-procedures)

## Introduction

The Shepherd Configuration Management System supports multiple deployment strategies to ensure zero-downtime deployments across different scenarios:

- **Rolling Updates**: Default strategy for routine updates, configuration changes, and bug fixes
- **Blue/Green**: Zero-downtime strategy for major version upgrades and breaking changes
- **Canary**: Gradual rollout with metrics validation for high-risk changes

### When to Use Each Strategy

| Strategy | Use Case | Downtime | Rollback Speed | Resource Overhead |
|----------|----------|----------|----------------|-------------------|
| Rolling Update | Routine updates, bug fixes | Zero | Fast (2-5 min) | Low (1x resources) |
| Blue/Green | Major versions, breaking changes | Zero | Instant (<30s) | High (2x resources) |
| Canary | High-risk changes, performance testing | Zero | Fast (1-2 min) | Medium (1.1-1.5x resources) |

## Prerequisites

### Required Tools

- `kubectl` (v1.24+) - Kubernetes command-line tool
- `helm` (v3.8+) - Kubernetes package manager
- `bash` (v4.0+) - Shell for running deployment scripts
- `jq` (v1.6+) - JSON processor for parsing responses
- `curl` - HTTP client for health checks

### Cluster Access and Permissions

Ensure you have the following Kubernetes RBAC permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: shepherd-deployer
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
```

### Environment Setup

1. **Configure kubectl context:**
   ```bash
   kubectl config use-context <your-cluster-context>
   kubectl cluster-info
   ```

2. **Verify namespace access:**
   ```bash
   kubectl get namespaces
   kubectl get pods -n staging
   kubectl get pods -n production
   ```

3. **Check Helm repositories:**
   ```bash
   helm repo list
   helm repo update
   ```

### Secret Management

Ensure the following secrets exist in each namespace:

```bash
# Check required secrets
kubectl get secret shepherd-secret -n staging
kubectl get secret shepherd-secret -n production

# Example secret creation
kubectl create secret generic shepherd-secret \
  --from-literal=secret-key="your-secret-key" \
  --from-literal=webhook-secret="your-webhook-secret" \
  --from-literal=mongodb-uri="mongodb://user:pass@host:port/db" \
  --from-literal=mongodb-username="shepherd" \
  --from-literal=mongodb-password="password" \
  --from-literal=mongodb-auth-source="shepherd_cms" \
  -n production
```

## Rolling Update Deployments

Rolling updates are the default deployment strategy for routine updates, configuration changes, and bug fixes.

### Overview

Rolling updates gradually replace old pods with new ones, ensuring continuous service availability. The deployment process:

1. Creates new pods with the updated version
2. Waits for new pods to become ready
3. Terminates old pods one by one
4. Continues until all pods are updated

### When to Use

- Minor version updates (e.g., v1.2.0 → v1.2.1)
- Configuration changes
- Bug fixes
- Security patches
- Dependency updates

### Procedure

#### Basic Rolling Update

```bash
# Navigate to project directory
cd /path/to/shepherd

# Deploy to staging
./scripts/deploy.sh \
  --namespace staging \
  --release shepherd \
  --values helm/shepherd/values-staging.yaml

# Deploy to production
./scripts/deploy.sh \
  --namespace production \
  --release shepherd \
  --values helm/shepherd/values-prod.yaml
```

#### Advanced Options

```bash
# Dry-run to preview changes
./scripts/deploy.sh \
  --namespace production \
  --dry-run

# Deploy with custom timeout and skip confirmation
./scripts/deploy.sh \
  --namespace production \
  --timeout 900 \
  --yes

# Deploy with specific values file
./scripts/deploy.sh \
  --namespace production \
  --values custom-values.yaml
```

### Monitoring Rolling Updates

Monitor the deployment progress:

```bash
# Watch rollout status
kubectl rollout status deployment/shepherd -n production

# Monitor pods in real-time
kubectl get pods -n production -l app.kubernetes.io/name=shepherd -w

# Check deployment events
kubectl get events -n production --sort-by='.lastTimestamp'
```

### Validation

After deployment, verify the update:

```bash
# Check pod status
kubectl get pods -n production -l app.kubernetes.io/name=shepherd

# Test health endpoint
POD_NAME=$(kubectl get pods -n production -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n production $POD_NAME -- curl -f http://localhost:5000/api/health

# Check service endpoints
kubectl get endpoints shepherd -n production
```

### Rollback

If issues are detected:

```bash
# Automatic rollback (triggered by health check failures)
# The deploy.sh script automatically rolls back on failure

# Manual rollback
./scripts/rollback.sh --namespace production --reason "Performance degradation detected"
```

## Blue/Green Deployments

Blue/Green deployments provide instant rollback capabilities for major version upgrades and breaking changes.

### Overview

Blue/Green deployment maintains two identical production environments:
- **Blue**: Current production version
- **Green**: New version being deployed

The deployment process:
1. Deploy new version to the inactive environment (Green)
2. Run comprehensive smoke tests
3. Switch traffic from Blue to Green
4. Monitor the new environment
5. Clean up the old environment

### When to Use

- Major version upgrades (e.g., v1.x → v2.x)
- Breaking API changes
- Database schema migrations
- Architecture changes
- High-risk deployments requiring instant rollback

### Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │    │   Service       │
│                 │────│   (Selector)    │
└─────────────────┘    └─────────────────┘
                                │
                  ┌─────────────┼─────────────┐
                  │             │             │
                  ▼             ▼             ▼
           ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
           │    Blue     │ │   Green     │ │  Preview    │
           │ Environment │ │ Environment │ │  Service    │
           │  (Active)   │ │ (Inactive)  │ │             │
           └─────────────┘ └─────────────┘ └─────────────┘
```

### Procedure

#### Interactive Blue/Green Deployment

```bash
# Deploy new version to inactive environment
./scripts/deploy-blue-green.sh \
  --namespace production \
  --image shepherd:v2.0.0

# The script will:
# 1. Determine current active environment (blue/green)
# 2. Deploy to inactive environment
# 3. Run smoke tests
# 4. Prompt for traffic switch confirmation
# 5. Switch traffic
# 6. Monitor new environment
# 7. Clean up old environment
```

#### Automated Blue/Green Deployment

```bash
# Fully automated deployment (no confirmations)
./scripts/deploy-blue-green.sh \
  --namespace production \
  --image shepherd:v2.0.0 \
  --auto
```

#### Custom Configuration

```bash
# Deploy with extended grace period
./scripts/deploy-blue-green.sh \
  --namespace production \
  --image shepherd:v2.0.0 \
  --grace-period 600  # 10 minutes

# Deploy with custom smoke test timeout
./scripts/deploy-blue-green.sh \
  --namespace production \
  --image shepherd:v2.0.0 \
  --smoke-timeout 300  # 5 minutes
```

### Smoke Testing

The blue/green script runs comprehensive smoke tests on the inactive environment:

1. **Health Endpoint Test**: Verifies `/api/health` responds correctly
2. **API Response Test**: Validates API response format and content
3. **Metrics Endpoint Test**: Checks `/metrics` endpoint availability
4. **Database Connectivity**: Verifies MongoDB connection through health endpoint

### Traffic Switching

Traffic switching is performed by updating the Kubernetes service selector:

```bash
# Before switch (Blue active)
kubectl get service shepherd -o yaml | grep selector
# selector:
#   app.kubernetes.io/name: shepherd-blue
#   version: blue

# After switch (Green active)
# selector:
#   app.kubernetes.io/name: shepherd-green
#   version: green
```

### Instant Rollback

Blue/Green deployments support instant rollback:

```bash
# Manual rollback
./scripts/deploy-blue-green.sh --rollback

# Or use the rollback script
./scripts/rollback.sh \
  --namespace production \
  --reason "Error rate spike detected"
```

Rollback process:
1. Switch service selector back to previous environment
2. Scale up old environment (if scaled down)
3. Verify health on old environment
4. Log rollback event

## Canary Deployments

Canary deployments provide gradual rollout with real-time metrics validation for high-risk changes.

### Overview

Canary deployment gradually shifts traffic from the stable version to the new version while monitoring metrics:

**Default Stages**: 10% → 25% → 50% → 75% → 100%

The deployment process:
1. Deploy canary version alongside stable version
2. Gradually increase traffic percentage
3. Monitor metrics at each stage
4. Automatically rollback if error thresholds are exceeded
5. Promote canary to stable once all stages pass

### When to Use

- Performance-critical changes
- Algorithm updates
- High-traffic applications
- Changes requiring gradual validation
- A/B testing scenarios

### Metrics Monitoring

Canary deployments monitor the following metrics:

- **Error Rate**: HTTP 5xx responses
- **Latency**: Response time percentiles (P99)
- **Request Rate**: Requests per minute
- **Health Check Status**: Application health endpoint

### Procedure

#### Standard Canary Deployment

```bash
# Deploy with default stages (10,25,50,75,100)
./scripts/canary-deploy.sh \
  --namespace production \
  --image shepherd:v2.1.0
```

#### Custom Canary Stages

```bash
# Deploy with custom stages
./scripts/canary-deploy.sh \
  --namespace production \
  --image shepherd:v2.1.0 \
  --stages "5,10,25,50,100"
```

#### Automated Canary

```bash
# Fully automated canary deployment
./scripts/canary-deploy.sh \
  --namespace production \
  --image shepherd:v2.1.0 \
  --auto \
  --interval 180  # 3 minutes between stages
```

#### Custom Error Threshold

```bash
# Deploy with lower error threshold
./scripts/canary-deploy.sh \
  --namespace production \
  --image shepherd:v2.1.0 \
  --error-threshold 2  # 2% error rate threshold
```

### Monitoring at Each Stage

The script provides real-time monitoring output:

```
🎯 Processing canary stage: 25%
>>> Adjusting traffic to 25% canary
Target replicas - Canary: 1, Stable: 3
✅ Traffic adjustment completed successfully
>>> Monitoring canary at 25% traffic for 300s
METRICS: Canary metrics - Error rate: 1%, Stage: 25%
Monitoring progress: 60s elapsed, 240s remaining
✅ Stage 25% completed successfully
```

### Automatic Rollback

Canary deployments automatically rollback if:

- Error rate exceeds threshold (default: 5%)
- Pods enter CrashLoopBackOff or Error state
- Health endpoint checks fail
- Manual intervention required (in non-auto mode)

### Promotion

After all stages complete successfully, the canary is promoted:

```bash
🎉 Canary deployment completed successfully!
All stages passed: 10,25,50,75,100%
Image promoted: shepherd:v2.1.0
Canary deployment scaled to 0 (available for quick rollback)
```

## Rollback Procedures

Quick and safe rollback procedures for when deployments fail or issues are detected.

### When to Rollback

- **Application Errors**: HTTP 5xx error rate spike
- **Performance Degradation**: Increased latency or timeouts
- **Health Check Failures**: Readiness/liveness probe failures
- **Database Issues**: Connection failures or query errors
- **User Reports**: Customer complaints or support tickets
- **Monitoring Alerts**: Prometheus/Grafana alerts firing

### Automatic Rollback

All deployment scripts include automatic rollback on failure:

```bash
# Automatic rollback triggers:
# - Health check failures after deployment
# - Pod crash loops
# - Deployment timeout
# - Error rate threshold exceeded (canary only)
```

### Manual Rollback

#### Quick Rollback to Previous Version

```bash
# Rollback to previous revision
./scripts/rollback.sh --namespace production

# The script will automatically:
# 1. Identify the previous successful revision
# 2. Execute Helm rollback
# 3. Wait for pods to be ready
# 4. Run health checks
# 5. Log the rollback event
```

#### Rollback to Specific Revision

```bash
# List available revisions
./scripts/rollback.sh --namespace production --list

# Rollback to specific revision
./scripts/rollback.sh \
  --namespace production \
  --revision 5 \
  --reason "Database migration failed"
```

#### Force Rollback

```bash
# Force rollback without confirmation
./scripts/rollback.sh \
  --namespace production \
  --force \
  --reason "Critical security issue"
```

### Verification After Rollback

The rollback script automatically verifies:

1. **Pod Status**: All pods running and ready
2. **Health Endpoint**: `/api/health` returns 200 OK
3. **API Functionality**: API responses are valid
4. **Metrics Endpoint**: `/metrics` is accessible
5. **Replica Count**: Matches expected number
6. **Error Monitoring**: No errors detected for 60 seconds

### Cascading Rollback

If the rollback target also has issues, the script attempts cascading rollback:

```bash
# If rollback to revision N fails, try revision N-1
Attempting cascading rollback to earlier version...
Attempting rollback to revision 4
🔄 Cascading rollback to revision 4 completed
```

## CI/CD Integration

### Automated Staging Deployments

Staging deployments are triggered automatically on merge to main:

```yaml
# .github/workflows/ci-cd.yml
deploy-staging:
  name: Deploy to Staging
  runs-on: ubuntu-latest
  needs: [build, push-ghcr]
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  environment: staging
```

### Manual Production Deployments

Production deployments require manual trigger with strategy selection:

#### Trigger via GitHub UI
1. Go to Actions tab in GitHub repository
2. Select "CI/CD Pipeline" workflow
3. Click "Run workflow"
4. Select deployment strategy and parameters

#### Trigger via GitHub CLI

```bash
# Rolling update deployment
gh workflow run ci-cd.yml \
  --ref main \
  -f deployment_strategy=rolling

# Blue/Green deployment
gh workflow run ci-cd.yml \
  --ref main \
  -f deployment_strategy=blue-green \
  -f image_tag=v2.0.0

# Canary deployment
gh workflow run ci-cd.yml \
  --ref main \
  -f deployment_strategy=canary \
  -f image_tag=v2.1.0 \
  -f auto_promote=true
```

### Rollback via GitHub Actions

```bash
# Trigger rollback workflow
gh workflow run rollback.yml \
  --ref main \
  -f environment=production \
  -f reason="Performance degradation detected"
```

### Environment Protection Rules

Production environment requires:
- Manual approval from designated reviewers
- Branch protection (only main branch)
- Required status checks

## Best Practices

### Pre-Deployment

1. **Always Test in Staging First**
   ```bash
   # Deploy to staging before production
   ./scripts/deploy.sh --namespace staging
   # Run tests and validation
   ./scripts/deploy.sh --namespace production
   ```

2. **Use Specific Image Tags**
   ```yaml
   # ❌ Don't use latest in production
   image:
     tag: latest
   
   # ✅ Use specific version tags
   image:
     tag: v1.2.3
   ```

3. **Validate Configuration**
   ```bash
   # Dry-run to preview changes
   ./scripts/deploy.sh --namespace production --dry-run
   
   # Lint Helm chart
   helm lint helm/shepherd
   ```

### During Deployment

4. **Monitor Metrics**
   - Watch CPU/Memory usage
   - Monitor error rates
   - Check response times
   - Verify database connections

5. **Use Appropriate Strategy**
   - Rolling updates for routine changes
   - Blue/Green for major versions
   - Canary for high-risk changes

6. **Deploy During Low-Traffic Periods**
   ```bash
   # Schedule deployments during maintenance windows
   # Typically 2-4 AM in your primary user timezone
   ```

### Post-Deployment

7. **Monitor for Extended Period**
   ```bash
   # Monitor for at least 30 minutes after deployment
   # Watch for:
   # - Error rate spikes
   # - Memory leaks
   # - Performance degradation
   ```

8. **Document Changes**
   ```bash
   # Log deployment details
   echo "$(date): Deployed v1.2.3 to production - Rolling update" >> deployment.log
   ```

9. **Keep Rollback Plan Ready**
   ```bash
   # Know your rollback commands before deploying
   ./scripts/rollback.sh --namespace production --list
   ```

### Operational Excellence

10. **Automate Health Checks**
    ```bash
    # Use automated health monitoring
    # Set up alerts for deployment failures
    ```

11. **Use Feature Flags**
    ```yaml
    # Control features independently of deployments
    env:
      FEATURE_NEW_API: "false"
    ```

12. **Implement Circuit Breakers**
    ```python
    # Fail fast to prevent cascade failures
    # Implement retry logic with exponential backoff
    ```

## Deployment Checklist

### Pre-Deployment Checklist

- [ ] **Code Review Complete**
  - [ ] All changes peer-reviewed
  - [ ] Security review completed (if required)
  - [ ] Performance impact assessed

- [ ] **Testing Complete**
  - [ ] Unit tests passing (100% coverage for new code)
  - [ ] Integration tests passing
  - [ ] End-to-end tests passing
  - [ ] Load testing completed (if applicable)

- [ ] **Environment Preparation**
  - [ ] Staging deployment successful
  - [ ] Configuration validated
  - [ ] Secrets updated (if required)
  - [ ] Database migrations tested

- [ ] **Operational Readiness**
  - [ ] Monitoring dashboards prepared
  - [ ] Alerting rules updated
  - [ ] On-call engineer available
  - [ ] Rollback plan documented

- [ ] **Communication**
  - [ ] Stakeholders notified
  - [ ] Deployment window scheduled
  - [ ] Change request approved (if required)

### During Deployment Checklist

- [ ] **Pre-Flight Checks**
  - [ ] Cluster connectivity verified
  - [ ] Required secrets exist
  - [ ] Helm chart linted successfully
  - [ ] Dry-run completed without errors

- [ ] **Deployment Execution**
  - [ ] Appropriate deployment strategy selected
  - [ ] Deployment command executed
  - [ ] Rollout monitoring active
  - [ ] Health checks passing

- [ ] **Real-Time Monitoring**
  - [ ] Pod status healthy
  - [ ] Service endpoints updated
  - [ ] Error rates normal
  - [ ] Response times acceptable

### Post-Deployment Checklist

- [ ] **Validation**
  - [ ] Health endpoint returning 200 OK
  - [ ] API smoke tests passing
  - [ ] Database connectivity verified
  - [ ] Metrics endpoint accessible

- [ ] **Monitoring**
  - [ ] Application metrics normal
  - [ ] Error logs reviewed
  - [ ] Performance baseline established
  - [ ] No alerts firing

- [ ] **Documentation**
  - [ ] Deployment logged
  - [ ] Configuration changes documented
  - [ ] Known issues documented
  - [ ] Rollback plan updated

- [ ] **Communication**
  - [ ] Deployment success communicated
  - [ ] Stakeholders notified
  - [ ] Support team informed
  - [ ] Post-mortem scheduled (if issues occurred)

## Post-Deployment Validation

### Automated Validation

The deployment scripts automatically perform basic validation:

```bash
# Health endpoint check
kubectl exec -n production $POD_NAME -- curl -f http://localhost:5000/api/health

# Service endpoints verification
kubectl get endpoints shepherd -n production

# Pod readiness check
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd -n production
```

### Manual Validation Steps

#### 1. Application Health

```bash
# Check pod status
kubectl get pods -n production -l app.kubernetes.io/name=shepherd

# Verify all pods are Running and Ready
# Example output:
# NAME                        READY   STATUS    RESTARTS   AGE
# shepherd-7d4b8c8f4b-abc12   1/1     Running   0          2m
# shepherd-7d4b8c8f4b-def34   1/1     Running   0          2m
# shepherd-7d4b8c8f4b-ghi56   1/1     Running   0          2m
```

#### 2. API Functionality

```bash
# Test health endpoint
curl -f https://shepherd.example.com/api/health

# Expected response:
# {
#   "status": "healthy",
#   "database": "connected",
#   "timestamp": "2024-01-15T10:30:00Z"
# }

# Test metrics endpoint
curl -f https://shepherd.example.com/metrics | head -20
```

#### 3. Database Connectivity

```bash
# Verify MongoDB connection through application
POD_NAME=$(kubectl get pods -n production -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[0].metadata.name}')

# Check database connectivity
kubectl exec -n production $POD_NAME -- python -c "
from pymongo import MongoClient
import os
client = MongoClient(os.environ['MONGODB_URI'])
db = client[os.environ['DATABASE_NAME']]
print('Database connection successful:', db.name)
print('Collections:', db.list_collection_names())
"
```

#### 4. Performance Baseline

```bash
# Load test to establish performance baseline
# Using Apache Bench (ab)
ab -n 1000 -c 10 https://shepherd.example.com/api/health

# Using curl for response time
curl -w "@curl-format.txt" -o /dev/null -s https://shepherd.example.com/api/health

# curl-format.txt contents:
#      time_namelookup:  %{time_namelookup}\n
#         time_connect:  %{time_connect}\n
#      time_appconnect:  %{time_appconnect}\n
#     time_pretransfer:  %{time_pretransfer}\n
#        time_redirect:  %{time_redirect}\n
#   time_starttransfer:  %{time_starttransfer}\n
#                      ----------\n
#           time_total:  %{time_total}\n
```

#### 5. Error Rate Monitoring

Monitor for the first 30 minutes after deployment:

```bash
# Check application logs for errors
kubectl logs -n production -l app.kubernetes.io/name=shepherd --tail=100 | grep -i error

# Monitor HTTP error rates (if using ingress with metrics)
# This example assumes Prometheus metrics are available
curl -s 'http://prometheus:9090/api/v1/query?query=rate(nginx_ingress_controller_requests{status=~"5.."}[5m])' | jq .

# Check for any CrashLoopBackOff or failed pods
kubectl get pods -n production -l app.kubernetes.io/name=shepherd | grep -E "CrashLoop|Error|Pending"
```

### Monitoring Dashboard Validation

After deployment, verify your monitoring dashboards show:

1. **Application Metrics**
   - Request rate returning to normal
   - Response time within acceptable range
   - Error rate < 1%
   - Memory and CPU usage stable

2. **Infrastructure Metrics**
   - Pod restart count = 0
   - All pods in Running state
   - Service discovery working (endpoints populated)

3. **Business Metrics**
   - Configuration reads/writes functioning
   - API calls completing successfully
   - Database queries performing normally

## Emergency Procedures

### Complete Service Outage

**Symptoms**: All API endpoints returning errors, no healthy pods

**Immediate Actions**:
1. **Check Cluster Health**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   kubectl top nodes
   ```

2. **Verify MongoDB Availability**
   ```bash
   kubectl get pods -n mongodb  # or wherever MongoDB is deployed
   # Test MongoDB connectivity
   kubectl exec -it mongodb-0 -- mongosh --eval "db.adminCommand('ping')"
   ```

3. **Check Recent Deployments**
   ```bash
   helm history shepherd -n production
   kubectl get events -n production --sort-by='.lastTimestamp' | head -20
   ```

4. **Immediate Rollback**
   ```bash
   ./scripts/rollback.sh \
     --namespace production \
     --force \
     --reason "Complete service outage - emergency rollback"
   ```

5. **Scale Up If Needed**
   ```bash
   kubectl scale deployment shepherd --replicas=5 -n production
   ```

6. **Notify Stakeholders**
   ```bash
   # Send immediate notification
   echo "CRITICAL: Shepherd service outage detected. Emergency rollback initiated." | \
   curl -X POST -H 'Content-type: application/json' \
   --data '{"text":"CRITICAL: Shepherd service outage detected. Emergency rollback initiated."}' \
   $SLACK_WEBHOOK_URL
   ```

### Partial Outage (Some Pods Failing)

**Symptoms**: Some pods in CrashLoopBackOff, degraded performance

**Actions**:
1. **Identify Failing Pods**
   ```bash
   kubectl get pods -n production -l app.kubernetes.io/name=shepherd
   kubectl describe pod <failing-pod-name> -n production
   ```

2. **Check Logs**
   ```bash
   kubectl logs <failing-pod-name> -n production --previous
   kubectl logs <failing-pod-name> -n production --tail=100
   ```

3. **Restart Failing Pods**
   ```bash
   kubectl delete pod <failing-pod-name> -n production
   # Or restart all pods
   kubectl rollout restart deployment/shepherd -n production
   ```

4. **Monitor Recovery**
   ```bash
   kubectl get pods -n production -l app.kubernetes.io/name=shepherd -w
   ```

5. **Investigate Root Cause**
   ```bash
   # Check resource usage
   kubectl top pods -n production
   # Check events
   kubectl get events -n production --field-selector involvedObject.name=<failing-pod>
   ```

### Performance Degradation

**Symptoms**: Increased response times, timeouts, high CPU/memory usage

**Actions**:
1. **Check Resource Utilization**
   ```bash
   kubectl top pods -n production -l app.kubernetes.io/name=shepherd
   kubectl top nodes
   ```

2. **Review Metrics**
   ```bash
   # Check Prometheus metrics (example queries)
   # HTTP request duration
   curl 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99, http_request_duration_seconds)'
   
   # CPU usage
   curl 'http://prometheus:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total[5m])'
   ```

3. **Scale Up if Needed**
   ```bash
   kubectl scale deployment shepherd --replicas=6 -n production
   ```

4. **Check Database Performance**
   ```bash
   # MongoDB slow query log
   kubectl exec -it mongodb-0 -- mongosh --eval "db.setProfilingLevel(2, {slowms: 100})"
   kubectl exec -it mongodb-0 -- mongosh --eval "db.system.profile.find().limit(5).sort({ts:-1}).pretty()"
   ```

5. **Consider Rollback**
   ```bash
   # If performance doesn't improve within 15 minutes
   ./scripts/rollback.sh \
     --namespace production \
     --reason "Performance degradation - rollback to stable version"
   ```

### Database Connection Issues

**Symptoms**: Health checks failing, database connection errors in logs

**Actions**:
1. **Verify MongoDB Status**
   ```bash
   kubectl get pods -n mongodb
   kubectl logs mongodb-0 -n mongodb --tail=50
   ```

2. **Check Network Connectivity**
   ```bash
   # Test from application pod
   POD_NAME=$(kubectl get pods -n production -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n production $POD_NAME -- nc -zv mongodb-0.mongodb-headless.mongodb.svc.cluster.local 27017
   ```

3. **Verify Secrets**
   ```bash
   kubectl get secret shepherd-secret -n production -o yaml
   # Check if MongoDB credentials are correct
   ```

4. **Check DNS Resolution**
   ```bash
   kubectl exec -n production $POD_NAME -- nslookup mongodb-0.mongodb-headless.mongodb.svc.cluster.local
   ```

5. **Restart Application Pods**
   ```bash
   kubectl rollout restart deployment/shepherd -n production
   ```

### Container Registry Issues

**Symptoms**: ImagePullBackOff, ErrImagePull errors

**Actions**:
1. **Check Image Availability**
   ```bash
   docker pull <image-name>:<tag>
   # or
   kubectl run test-image --image=<image-name>:<tag> --rm -it --restart=Never -- /bin/sh
   ```

2. **Verify Image Pull Secrets**
   ```bash
   kubectl get secrets -n production | grep docker
   kubectl describe secret <image-pull-secret> -n production
   ```

3. **Check Registry Connectivity**
   ```bash
   # Test from cluster
   kubectl run test-connectivity --image=curlimages/curl --rm -it --restart=Never -- curl -I https://registry-1.docker.io/v2/
   ```

4. **Use Previous Working Image**
   ```bash
   ./scripts/rollback.sh \
     --namespace production \
     --reason "Container registry unavailable"
   ```

### When to Escalate

Escalate to senior engineering or on-call if:

- **Service outage exceeds 15 minutes**
- **Rollback attempts fail**
- **Data corruption suspected**
- **Security incident detected**
- **Cluster-wide issues observed**
- **Root cause unknown after 30 minutes investigation**

### Escalation Contacts

```bash
# Example escalation procedure
echo "ESCALATION REQUIRED: Shepherd deployment issue" | \
curl -X POST -H 'Content-type: application/json' \
--data '{"text":"ESCALATION: Shepherd deployment requires immediate attention"}' \
$PAGERDUTY_WEBHOOK_URL
```

---

## Summary

This deployment guide provides comprehensive procedures for:

- ✅ **Rolling Updates**: For routine deployments with zero downtime
- ✅ **Blue/Green**: For major versions with instant rollback
- ✅ **Canary**: For gradual rollout with metrics validation
- ✅ **Rollback**: For quick recovery from failed deployments
- ✅ **CI/CD Integration**: For automated deployment workflows
- ✅ **Emergency Procedures**: For critical incident response

Follow the appropriate strategy based on your change type and risk level. Always test in staging first and have a rollback plan ready.

For troubleshooting specific deployment issues, see the [Troubleshooting Deployments Guide](troubleshooting-deployments.md).