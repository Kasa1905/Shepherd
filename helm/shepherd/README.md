# Shepherd Configuration Management System - Helm Chart

This Helm chart deploys Shepherd Configuration Management System on Kubernetes with full observability features, auto-scaling, and production-ready configurations.

## Quick Start

### Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- MongoDB instance (external or internal)

### Installation

1. **Add the repository** (if published):
```bash
helm repo add shepherd https://charts.shepherd.io
helm repo update
```

2. **Install with minimal configuration**:
```bash
helm install shepherd shepherd/shepherd \
  --set app.secrets.secretKey="your-secret-key" \
  --set mongodb.external.password="mongodb-password"
```

3. **Install with custom values**:
```bash
# Create values file
cat > my-values.yaml << EOF
app:
  secrets:
    secretKey: "your-very-secure-secret-key"
    webhookSecret: "webhook-signing-secret"
  
mongodb:
  external:
    enabled: true
    host: "mongodb.example.com"
    password: "mongodb-password"

ingress:
  enabled: true
  hosts:
    - host: shepherd.example.com
      paths:
        - path: /
          pathType: Prefix

serviceMonitor:
  enabled: true
EOF

# Install
helm install shepherd shepherd/shepherd -f my-values.yaml
```

## Configuration

### Required Values

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `app.secrets.secretKey` | Flask application secret key | `""` | ✅ |
| `mongodb.external.password` | MongoDB password | `""` | ✅ |

### Core Application Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `app.image.repository` | Docker image repository | `shepherd/shepherd` |
| `app.image.tag` | Docker image tag | `latest` |
| `app.replicaCount` | Number of replicas | `2` |
| `app.env.LOG_LEVEL` | Logging level | `INFO` |
| `app.env.METRICS_ENABLED` | Enable Prometheus metrics | `True` |

### MongoDB Configuration

#### External MongoDB (Recommended)

```yaml
mongodb:
  external:
    enabled: true
    host: mongodb.example.com
    port: 27017
    database: shepherd_cms
    username: shepherd
    password: "secure-password"
    authSource: admin
    ssl: true
    replicaSet: "rs0"
```

#### Internal MongoDB (Development)

```yaml
mongodb:
  internal:
    enabled: true
    auth:
      rootPassword: "secure-root-password"
      password: "secure-app-password"
    persistence:
      enabled: true
      size: 10Gi
      storageClass: "fast-ssd"
```

**Required Secrets for Internal MongoDB:**
When using internal MongoDB (`mongodb.internal.enabled=true`), you must provide the following authentication secrets:

```bash
helm install shepherd ./helm/shepherd \
  --set mongodb.internal.auth.rootPassword="your-root-password" \
  --set mongodb.internal.auth.password="your-app-password"
```

The chart creates a separate Secret (`<release-name>-mongodb-secret`) containing:
- `mongodb-root-password`: Root user password for administrative access
- `mongodb-password`: Application user password for database operations

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/tls-acme: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: shepherd.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: shepherd-tls
      hosts:
        - shepherd.example.com
```

### Auto-scaling Configuration

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Monitoring and Observability

#### Prometheus Integration

```yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
  interval: 30s
  labels:
    prometheus: kube-prometheus
```

#### Webhook Configuration

```yaml
webhooks:
  urls:
  # Example Slack webhook URL (placeholder). Do NOT commit real URLs.
  - "https://hooks.slack.com/services/REDACTED/REDACTED/REDACTED"
    - "https://api.example.com/webhooks/shepherd"

app:
  secrets:
    webhookSecret: "webhook-signing-secret"
  env:
    WEBHOOK_EVENTS: "config.created,config.updated,config.rolled_back"
```

#### Structured Logging

```yaml
logging:
  structured: true
  forwarding:
    # ELK Stack
    elk:
      enabled: true
      endpoint: "https://elasticsearch.example.com:9200"
    
    # Datadog
    datadog:
      enabled: true
      apiKey: "your-datadog-api-key"
```

### Security Configuration

```yaml
app:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true

networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
```

### Resource Management

```yaml
app:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 1000m
      memory: 1Gi

nodeSelector:
  node-type: application

tolerations:
  - key: "application"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

## Production Deployment

### High Availability Setup

```yaml
# Production values.yaml
app:
  replicaCount: 3
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 1000m
      memory: 1Gi

mongodb:
  external:
    enabled: true
    host: "mongodb-cluster.example.com"
    ssl: true
    replicaSet: "rs0"

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20

podDisruptionBudget:
  enabled: true
  minAvailable: 2

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - shepherd
        topologyKey: kubernetes.io/hostname
```

### Environment-Specific Deployments

#### Development

```bash
helm install shepherd-dev shepherd/shepherd \
  --namespace shepherd-dev \
  --create-namespace \
  -f values-dev.yaml
```

#### Staging

```bash
helm install shepherd-staging shepherd/shepherd \
  --namespace shepherd-staging \
  --create-namespace \
  -f values-staging.yaml
```

#### Production

```bash
helm install shepherd-prod shepherd/shepherd \
  --namespace shepherd-prod \
  --create-namespace \
  -f values-prod.yaml
```

## Upgrading

### Standard Upgrade

```bash
helm upgrade shepherd shepherd/shepherd -f my-values.yaml
```

### Rolling Back

```bash
# View release history
helm history shepherd

# Rollback to previous version
helm rollback shepherd 1
```

### Blue-Green Deployment

```bash
# Deploy new version with different name
helm install shepherd-v2 shepherd/shepherd -f my-values.yaml

# Test the new deployment
kubectl port-forward svc/shepherd-v2 8080:80

# Switch ingress traffic and cleanup old deployment
kubectl patch ingress shepherd --type='merge' -p='{"spec":{"rules":[{"host":"shepherd.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"shepherd-v2","port":{"number":80}}}}]}}]}}'
helm uninstall shepherd
```

## Monitoring

### Health Checks

The chart includes comprehensive health checks:

- **Liveness Probe**: `/api/health` endpoint
- **Readiness Probe**: `/api/health` endpoint
- **Startup Probe**: Automatic with reasonable delays

### Metrics Collection

Prometheus metrics are exposed on `/metrics`:

- HTTP request metrics
- Database operation metrics
- Configuration change metrics
- Application performance metrics

### Logging

Structured JSON logging is enabled by default:

- Request correlation IDs
- User context tracking
- Performance metrics
- Error tracking with stack traces

## Troubleshooting

### Common Issues

1. **Pod startup failures**:
```bash
kubectl describe pod -l app.kubernetes.io/name=shepherd
kubectl logs -l app.kubernetes.io/name=shepherd --previous
```

2. **Database connection issues**:
```bash
kubectl exec -it deployment/shepherd -- env | grep MONGODB
kubectl exec -it deployment/shepherd -- nc -zv mongodb-host 27017
```

3. **Ingress not working**:
```bash
kubectl describe ingress shepherd
kubectl get endpoints shepherd
```

### Debugging Commands

```bash
# Check all resources
kubectl get all -l app.kubernetes.io/name=shepherd

# View configuration
kubectl get configmap shepherd-config -o yaml
kubectl get secret shepherd-secret -o yaml

# Check metrics
kubectl port-forward svc/shepherd 8080:80
curl localhost:8080/metrics

# Test health endpoint
curl localhost:8080/api/health
```

## Values Reference

### Complete Values Structure

```yaml
# Global settings
global:
  imageRegistry: ""
  imagePullSecrets: []

# Application configuration
app:
  name: shepherd
  image:
    registry: docker.io
    repository: shepherd/shepherd
    tag: latest
    pullPolicy: IfNotPresent
  replicaCount: 2
  env: {}
  secrets:
    secretKey: ""
    webhookSecret: ""
  resources: {}
  livenessProbe: {}
  readinessProbe: {}
  securityContext: {}

# Service configuration
service:
  type: ClusterIP
  port: 80
  targetPort: 5000

# Ingress configuration
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts: []
  tls: []

# MongoDB configuration
mongodb:
  external:
    enabled: true
    host: ""
    port: 27017
    database: shepherd_cms
    username: shepherd
    password: ""
  internal:
    enabled: false

# Auto-scaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10

# Monitoring
serviceMonitor:
  enabled: false
monitoring:
  prometheus:
    enabled: true

# Security
rbac:
  create: true
podDisruptionBudget:
  enabled: true
networkPolicy:
  enabled: false

# Additional configuration
webhooks:
  urls: []
logging:
  structured: true
persistence:
  enabled: false
```

## Support

- **Documentation**: [Shepherd Docs](https://docs.shepherd.io)
- **Issues**: [GitHub Issues](https://github.com/your-org/shepherd/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/shepherd/discussions)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make changes to chart templates
4. Test with `helm template` and `helm lint`
5. Submit a pull request

## License

This Helm chart is licensed under the same license as the Shepherd project.