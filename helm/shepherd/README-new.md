# Shepherd Configuration Management System - Helm Chart

This Helm chart deploys Shepherd Configuration Management System on Kubernetes with full observability features, auto-scaling, High Availability, and production-ready configurations including disaster recovery capabilities.

## Architecture Overview

### Standard Deployment Components
- **Deployment**: Shepherd application with auto-scaling
- **Service**: ClusterIP service for internal communication
- **Ingress**: HTTP/HTTPS routing with TLS support
- **ConfigMap**: Application configuration
- **Secret**: Sensitive data management
- **ServiceAccount**: RBAC configuration
- **HPA**: Horizontal Pod Autoscaler
- **PDB**: Pod Disruption Budget

### High Availability & Disaster Recovery Features
- **MongoDB StatefulSet**: Internal 3-replica MongoDB cluster
- **Backup CronJobs**: Automated backup with verification
- **Pod Anti-Affinity**: Distribution across nodes
- **Health Monitoring**: Comprehensive health checks
- **Persistent Storage**: Data persistence with backup capabilities

### RTO/RPO Targets
- **Recovery Time Objective (RTO)**: 60 minutes
- **Recovery Point Objective (RPO)**: 15 minutes
- **Backup Retention**: 30 days
- **Cross-AZ Distribution**: Automatic pod distribution

## Quick Start

### Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- MongoDB instance (external) or sufficient storage for internal MongoDB
- Storage class for persistent volumes (if using internal MongoDB)

### Basic Installation

1. **Install with external MongoDB**:
```bash
helm install shepherd ./helm/shepherd \
  --set app.secrets.secretKey="your-secret-key" \
  --set mongodb.external.enabled=true \
  --set mongodb.external.host="mongodb.example.com" \
  --set mongodb.external.password="mongodb-password"
```

2. **Install with internal MongoDB (HA setup)**:
```bash
helm install shepherd ./helm/shepherd \
  --set app.secrets.secretKey="your-secret-key" \
  --set mongodb.internal.enabled=true \
  --set mongodb.internal.replicaSet.enabled=true \
  --set backup.enabled=true
```

### Production Installation with HA/DR

```bash
# Create production values file
cat > production-values.yaml << EOF
# Application Configuration
app:
  replicaCount: 3
  secrets:
    secretKey: "your-very-secure-secret-key"
    webhookSecret: "webhook-signing-secret"
  
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

  # Anti-affinity for HA
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - shepherd
          topologyKey: kubernetes.io/hostname

# Internal MongoDB with HA
mongodb:
  internal:
    enabled: true
    replicaSet:
      enabled: true
      replicas: 3
    
    persistence:
      enabled: true
      size: 20Gi
      storageClass: "fast-ssd"
    
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"

# Backup Configuration
backup:
  enabled: true
  schedule: "0 */6 * * *"  # Every 6 hours
  retention: "30d"
  storage:
    type: "s3"
    s3:
      bucket: "shepherd-backups"
      region: "us-west-2"

# Ingress with TLS
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: shepherd.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: shepherd-tls
      hosts:
        - shepherd.yourdomain.com

# Auto-scaling
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  minAvailable: 2

# Service Monitor for Prometheus
serviceMonitor:
  enabled: true
  namespace: monitoring
  interval: 30s
EOF

# Install with production configuration
helm install shepherd ./helm/shepherd -f production-values.yaml
```

## High Availability Configuration

### MongoDB Replica Set

The internal MongoDB is deployed as a StatefulSet with replica set configuration:

```yaml
mongodb:
  internal:
    enabled: true
    replicaSet:
      enabled: true
      replicas: 3
      
    # Pod anti-affinity for distribution
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
              - mongodb
          topologyKey: kubernetes.io/hostname
    
    # Persistent storage
    persistence:
      enabled: true
      size: 20Gi
      accessMode: ReadWriteOnce
```

### Application High Availability

```yaml
app:
  replicaCount: 3
  
  # Pod anti-affinity
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - shepherd
          topologyKey: kubernetes.io/hostname

# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  minAvailable: 2
```

## Backup and Disaster Recovery

### Automated Backup Configuration

```yaml
backup:
  enabled: true
  schedule: "0 */6 * * *"  # Every 6 hours
  retention: "30d"
  
  # Storage configuration
  storage:
    type: "s3"  # or "pvc", "gcs"
    s3:
      bucket: "shepherd-backups"
      region: "us-west-2"
      accessKey: "access-key"
      secretKey: "secret-key"
  
  # Backup verification
  verification:
    enabled: true
    schedule: "0 2 * * *"  # Daily at 2 AM
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

### Backup Management Commands

```bash
# Trigger manual backup
kubectl create job --from=cronjob/mongodb-backup mongodb-backup-manual-$(date +%s)

# Check backup status
kubectl get cronjobs
kubectl logs -l job-name=mongodb-backup-<timestamp>

# List available backups (S3 example)
kubectl exec deployment/shepherd-app -- aws s3 ls s3://shepherd-backups/mongodb-backups/

# Restore from backup
kubectl create job --from=cronjob/mongodb-backup mongodb-restore-$(date +%s) \
  --dry-run=client -o yaml | \
  sed 's/mongodump/mongorestore/' | \
  kubectl apply -f -
```

### Disaster Recovery Procedures

#### Complete Cluster Recovery

```bash
# 1. Deploy Helm chart in new cluster
helm install shepherd ./helm/shepherd -f production-values.yaml

# 2. Scale down application
kubectl scale deployment shepherd-app --replicas=0

# 3. Restore database from backup
kubectl create job mongodb-restore-$(date +%s) --image=mongo:7.0 -- \
  /bin/bash -c "
  aws s3 cp s3://shepherd-backups/mongodb-backups/latest.tar.gz /tmp/ &&
  tar -xzf /tmp/latest.tar.gz -C /tmp/ &&
  mongorestore --host mongodb-0.mongodb:27017 /tmp/backup/
  "

# 4. Scale up application
kubectl scale deployment shepherd-app --replicas=3
```

#### Node Failure Recovery

MongoDB and application pods will automatically reschedule on healthy nodes due to:
- StatefulSet controller for MongoDB
- Deployment controller for application
- Pod anti-affinity rules for distribution

## Monitoring and Observability

### Prometheus Integration

```yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
  interval: 30s
  path: /metrics
  labels:
    release: prometheus
```

### Health Checks

The chart includes comprehensive health checks:

```yaml
app:
  livenessProbe:
    httpGet:
      path: /health
      port: http
    initialDelaySeconds: 30
    periodSeconds: 10
  
  readinessProbe:
    httpGet:
      path: /health/ready
      port: http
    initialDelaySeconds: 5
    periodSeconds: 5
```

### Monitoring Commands

```bash
# Check application health
kubectl get pods -l app.kubernetes.io/name=shepherd
kubectl describe pod <pod-name>

# Check MongoDB replica set status
kubectl exec mongodb-0 -- mongosh --eval "rs.status()"

# View application logs
kubectl logs -f deployment/shepherd-app

# Check backup job logs
kubectl logs -f job/mongodb-backup-<timestamp>

# Monitor resource usage
kubectl top pods
kubectl describe hpa shepherd-app
```

## Configuration Reference

### Application Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `app.replicaCount` | Number of application replicas | `2` |
| `app.image.repository` | Application image repository | `shepherd` |
| `app.image.tag` | Application image tag | `latest` |
| `app.secrets.secretKey` | Application secret key | `""` (required) |
| `app.secrets.webhookSecret` | Webhook signing secret | `""` |

### MongoDB Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mongodb.internal.enabled` | Enable internal MongoDB | `false` |
| `mongodb.internal.replicaSet.enabled` | Enable replica set | `false` |
| `mongodb.internal.replicaSet.replicas` | Number of MongoDB replicas | `3` |
| `mongodb.internal.persistence.enabled` | Enable persistent storage | `true` |
| `mongodb.internal.persistence.size` | Storage size | `8Gi` |
| `mongodb.external.enabled` | Use external MongoDB | `true` |
| `mongodb.external.host` | External MongoDB host | `""` |

### Backup Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `backup.enabled` | Enable automated backup | `false` |
| `backup.schedule` | Backup cron schedule | `"0 */6 * * *"` |
| `backup.retention` | Backup retention period | `"30d"` |
| `backup.storage.type` | Storage type (s3/pvc/gcs) | `"pvc"` |
| `backup.verification.enabled` | Enable backup verification | `true` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts configuration | `[]` |
| `ingress.tls` | TLS configuration | `[]` |

### Auto-scaling Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `2` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | CPU target | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Memory target | `""` |

## Troubleshooting

### Common Issues

#### Pod Startup Issues
```bash
# Check pod status
kubectl describe pod <pod-name>

# View events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check logs
kubectl logs <pod-name> -c <container-name>
```

#### MongoDB Replica Set Issues
```bash
# Check replica set status
kubectl exec mongodb-0 -- mongosh --eval "rs.status()"

# Check MongoDB logs
kubectl logs mongodb-0

# Re-initialize replica set (if needed)
kubectl exec mongodb-0 -- mongosh --eval "rs.initiate()"
```

#### Backup Issues
```bash
# Check backup job status
kubectl describe job mongodb-backup-<timestamp>

# View backup logs
kubectl logs job/mongodb-backup-<timestamp>

# Test backup manually
kubectl create job test-backup --image=mongo:7.0 -- mongodump --host mongodb-0.mongodb:27017
```

For detailed disaster recovery procedures, see [Disaster Recovery Runbook](../../docs/disaster-recovery.md).