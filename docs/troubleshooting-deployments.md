# Troubleshooting Deployment Issues

A systematic guide for diagnosing and resolving deployment problems in the Shepherd Configuration Management System.

## Table of Contents

- [Overview](#overview)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Diagnostic Tools and Commands](#diagnostic-tools-and-commands)
- [Error Pattern Analysis](#error-pattern-analysis)
- [Resource-Related Issues](#resource-related-issues)
- [Network and Connectivity Issues](#network-and-connectivity-issues)
- [Configuration and Secret Issues](#configuration-and-secret-issues)
- [Image and Registry Issues](#image-and-registry-issues)
- [Database-Related Issues](#database-related-issues)
- [Performance Troubleshooting](#performance-troubleshooting)
- [Rollback Troubleshooting](#rollback-troubleshooting)
- [CI/CD Pipeline Issues](#cicd-pipeline-issues)
- [Monitoring and Alerting Issues](#monitoring-and-alerting-issues)
- [Advanced Debugging Techniques](#advanced-debugging-techniques)

## Overview

This guide provides systematic approaches to diagnose and resolve deployment issues. Each section includes:

- **Symptoms**: How to identify the issue
- **Diagnosis**: Commands to gather information
- **Solutions**: Step-by-step resolution
- **Prevention**: How to avoid the issue in the future

### General Troubleshooting Workflow

```mermaid
graph TD
    A[Deployment Issue Detected] --> B[Identify Symptoms]
    B --> C[Gather Diagnostic Information]
    C --> D[Analyze Logs and Events]
    D --> E[Determine Root Cause]
    E --> F[Apply Solution]
    F --> G[Verify Resolution]
    G --> H[Document Issue and Solution]
    
    F --> I[Implement Prevention Measures]
    G --> J{Issue Resolved?}
    J -->|No| C
    J -->|Yes| H
```

## Common Issues and Solutions

### 1. Pods Stuck in Pending State

**Symptoms**:
- Pods remain in `Pending` status
- New deployment doesn't start
- Kubectl shows pod scheduling issues

**Diagnosis**:
```bash
# Check pod status and events
kubectl get pods -n production -l app.kubernetes.io/name=shepherd
kubectl describe pod <pod-name> -n production

# Check node resources
kubectl describe nodes
kubectl top nodes

# Check for resource quotas
kubectl describe quota -n production
```

**Common Causes and Solutions**:

#### Insufficient Node Resources
```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Capacity:\|Allocatable:"

# Solution: Scale cluster or adjust resource requests
kubectl patch deployment shepherd -n production -p '{"spec":{"template":{"spec":{"containers":[{"name":"shepherd","resources":{"requests":{"cpu":"200m","memory":"256Mi"}}}]}}}}'
```

#### Node Selector/Affinity Issues
```bash
# Check node labels
kubectl get nodes --show-labels

# Verify deployment node selector
kubectl get deployment shepherd -o yaml | grep -A 10 nodeSelector

# Solution: Update node selector or add required labels
kubectl label nodes <node-name> app=shepherd
```

#### Pod Anti-Affinity Conflicts
```bash
# Check affinity rules
kubectl get deployment shepherd -o yaml | grep -A 15 affinity

# Solution: Adjust anti-affinity rules or add more nodes
```

### 2. ImagePullBackOff Errors

**Symptoms**:
- Pods stuck in `ImagePullBackOff` or `ErrImagePull`
- Unable to pull container image
- Deployment fails to start new pods

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod <pod-name> -n production | grep -A 10 Events

# Check image pull secrets
kubectl get secrets -n production | grep docker
kubectl describe secret <image-pull-secret> -n production

# Test image availability
docker pull <image-name>:<tag>
```

**Solutions**:

#### Image Not Found
```bash
# Verify image exists in registry
curl -I https://ghcr.io/v2/<namespace>/shepherd/manifests/<tag>

# Check for typos in image name/tag
kubectl get deployment shepherd -o yaml | grep image

# Solution: Use correct image name/tag
kubectl set image deployment/shepherd shepherd=ghcr.io/<namespace>/shepherd:v1.2.3 -n production
```

#### Registry Authentication Issues
```bash
# Recreate image pull secret
kubectl delete secret shepherd-registry-secret -n production
kubectl create secret docker-registry shepherd-registry-secret \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token> \
  --docker-email=<email>

# Update service account
kubectl patch serviceaccount shepherd -p '{"imagePullSecrets": [{"name": "shepherd-registry-secret"}]}'
```

#### Registry Connectivity Issues
```bash
# Test registry connectivity from cluster
kubectl run test-connectivity --image=curlimages/curl --rm -it --restart=Never -- curl -I https://ghcr.io

# Check firewall/network policies
kubectl get networkpolicies -n production
```

### 3. CrashLoopBackOff

**Symptoms**:
- Pods repeatedly crashing and restarting
- High restart count
- Application fails to start properly

**Diagnosis**:
```bash
# Check pod status and restart count
kubectl get pods -n production -l app.kubernetes.io/name=shepherd

# Examine recent logs
kubectl logs <pod-name> -n production --tail=100
kubectl logs <pod-name> -n production --previous

# Check liveness/readiness probes
kubectl describe pod <pod-name> -n production | grep -A 10 "Liveness\|Readiness"
```

**Common Causes and Solutions**:

#### Application Startup Failure
```bash
# Check environment variables
kubectl describe pod <pod-name> -n production | grep -A 20 "Environment:"

# Verify secrets are properly mounted
kubectl describe pod <pod-name> -n production | grep -A 10 "Mounts:"

# Solution: Fix environment configuration
kubectl edit secret shepherd-secret -n production
```

#### Probe Configuration Issues
```bash
# Check current probe settings
kubectl get deployment shepherd -o yaml | grep -A 10 "livenessProbe\|readinessProbe"

# Solution: Adjust probe timing
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "readinessProbe": {
            "initialDelaySeconds": 60,
            "periodSeconds": 10,
            "timeoutSeconds": 5
          }
        }]
      }
    }
  }
}'
```

#### Resource Limits Too Low
```bash
# Check resource usage
kubectl top pods -n production

# Solution: Increase resource limits
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "resources": {
            "limits": {"cpu": "1000m", "memory": "1024Mi"},
            "requests": {"cpu": "500m", "memory": "512Mi"}
          }
        }]
      }
    }
  }
}'
```

### 4. Service Not Accessible

**Symptoms**:
- API endpoints return connection refused
- Load balancer not routing traffic
- Health checks failing from external systems

**Diagnosis**:
```bash
# Check service configuration
kubectl get service shepherd -n production -o yaml

# Check endpoints
kubectl get endpoints shepherd -n production

# Check ingress configuration
kubectl get ingress shepherd -n production -o yaml

# Test internal connectivity
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- curl -f http://shepherd.production.svc.cluster.local:5000/api/health
```

**Solutions**:

#### Service Selector Mismatch
```bash
# Compare service selector with pod labels
kubectl get service shepherd -n production -o yaml | grep -A 5 selector
kubectl get pods -n production -l app.kubernetes.io/name=shepherd --show-labels

# Solution: Fix service selector
kubectl patch service shepherd -n production -p '{"spec":{"selector":{"app.kubernetes.io/name":"shepherd"}}}'
```

#### Ingress Issues
```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Verify ingress annotations
kubectl describe ingress shepherd -n production

# Solution: Update ingress configuration
kubectl patch ingress shepherd -n production -p '{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/backend-protocol": "HTTP",
      "nginx.ingress.kubernetes.io/health-check-path": "/api/health"
    }
  }
}'
```

### 5. Rolling Update Stuck

**Symptoms**:
- Deployment shows old and new replicas running
- Rolling update doesn't complete
- Pods not becoming ready

**Diagnosis**:
```bash
# Check rollout status
kubectl rollout status deployment/shepherd -n production

# Check deployment events
kubectl describe deployment shepherd -n production | grep -A 20 Events

# Check replica sets
kubectl get rs -n production -l app.kubernetes.io/name=shepherd
```

**Solutions**:

#### Readiness Probe Failing
```bash
# Check readiness probe logs
kubectl logs <new-pod-name> -n production

# Test readiness endpoint manually
kubectl exec <new-pod-name> -n production -- curl -f http://localhost:5000/api/health

# Solution: Fix readiness endpoint or adjust probe
```

#### Insufficient Replicas for Rolling Update
```bash
# Check maxUnavailable setting
kubectl get deployment shepherd -o yaml | grep -A 5 rollingUpdate

# Solution: Ensure maxUnavailable allows progress
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "strategy": {
      "rollingUpdate": {
        "maxUnavailable": 1,
        "maxSurge": 1
      }
    }
  }
}'
```

## Diagnostic Tools and Commands

### Essential Kubectl Commands

```bash
# Pod status and details
kubectl get pods -n production -l app.kubernetes.io/name=shepherd -o wide
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production --tail=100 --follow

# Deployment information
kubectl get deployment shepherd -n production -o yaml
kubectl describe deployment shepherd -n production
kubectl rollout history deployment/shepherd -n production

# Service and networking
kubectl get service shepherd -n production -o yaml
kubectl get endpoints shepherd -n production
kubectl get ingress shepherd -n production -o yaml

# Events and troubleshooting
kubectl get events -n production --sort-by='.lastTimestamp'
kubectl top pods -n production
kubectl top nodes
```

### Advanced Debugging Commands

```bash
# Resource usage over time
kubectl top pods -n production --containers | grep shepherd

# Network connectivity testing
kubectl run debug-pod --image=nicolaka/netshoot --rm -it --restart=Never

# DNS resolution testing
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup shepherd.production.svc.cluster.local

# Port forwarding for direct access
kubectl port-forward service/shepherd 8080:5000 -n production

# Execute commands in running pods
kubectl exec -it <pod-name> -n production -- /bin/bash
```

### Log Analysis Commands

```bash
# Filter logs by error level
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -i error

# Search for specific patterns
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -E "(traceback|exception|failed)"

# Monitor logs in real-time
kubectl logs -n production -l app.kubernetes.io/name=shepherd --tail=0 -f

# Export logs for analysis
kubectl logs -n production -l app.kubernetes.io/name=shepherd --since=1h > shepherd-logs.txt
```

## Error Pattern Analysis

### Application Startup Errors

**Pattern**: "Connection to database failed"
```bash
# Diagnosis
kubectl logs <pod-name> -n production | grep -i "database\|mongo"

# Check MongoDB connectivity
kubectl exec <pod-name> -n production -- nc -zv mongodb-0.mongodb.svc.cluster.local 27017

# Verify credentials
kubectl get secret shepherd-secret -n production -o yaml | base64 -d
```

**Pattern**: "Environment variable not set"
```bash
# Check environment configuration
kubectl describe pod <pod-name> -n production | grep -A 30 "Environment:"

# Verify secret mounting
kubectl exec <pod-name> -n production -- env | grep -i shepherd
```

**Pattern**: "Permission denied"
```bash
# Check security context
kubectl get deployment shepherd -o yaml | grep -A 10 securityContext

# Check file permissions
kubectl exec <pod-name> -n production -- ls -la /app/
```

### Health Check Failures

**Pattern**: "Readiness probe failed: HTTP probe failed"
```bash
# Test health endpoint from pod
kubectl exec <pod-name> -n production -- curl -v http://localhost:5000/api/health

# Check if application is fully started
kubectl logs <pod-name> -n production | grep -i "server.*start\|listening\|ready"

# Verify port configuration
kubectl get deployment shepherd -o yaml | grep -A 5 "containerPort\|readinessProbe"
```

### Resource Exhaustion Patterns

**Pattern**: "OOMKilled" or "memory limit exceeded"
```bash
# Check memory usage
kubectl top pods -n production | grep shepherd

# Review memory limits
kubectl describe pod <pod-name> -n production | grep -A 5 "Limits:\|Requests:"

# Analyze memory trends
kubectl logs <pod-name> -n production --previous | grep -i "memory\|oom"
```

## Resource-Related Issues

### CPU Throttling

**Symptoms**:
- Slow response times
- High CPU usage metrics
- Timeouts during peak load

**Diagnosis**:
```bash
# Check CPU usage
kubectl top pods -n production -l app.kubernetes.io/name=shepherd

# Check CPU limits and requests
kubectl describe pod <pod-name> -n production | grep -A 10 "Limits:\|Requests:"

# Monitor CPU throttling
kubectl get --raw /api/v1/nodes/<node-name>/proxy/stats/summary | jq .pods[].containers[].cpu
```

**Solutions**:
```bash
# Increase CPU limits
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "resources": {
            "limits": {"cpu": "2000m"},
            "requests": {"cpu": "1000m"}
          }
        }]
      }
    }
  }
}'

# Scale horizontally
kubectl scale deployment shepherd --replicas=5 -n production
```

### Memory Issues

**Symptoms**:
- Pods getting OOMKilled
- High memory usage warnings
- Memory leaks over time

**Diagnosis**:
```bash
# Check memory usage trends
kubectl top pods -n production -l app.kubernetes.io/name=shepherd --sort-by=memory

# Check memory limits
kubectl get deployment shepherd -o yaml | grep -A 5 "memory"

# Monitor memory allocation
kubectl exec <pod-name> -n production -- cat /proc/meminfo
```

**Solutions**:
```bash
# Increase memory limits
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "resources": {
            "limits": {"memory": "2Gi"},
            "requests": {"memory": "1Gi"}
          }
        }]
      }
    }
  }
}'

# Enable memory profiling
kubectl set env deployment/shepherd DEBUG_MEMORY=true -n production
```

### Storage Issues

**Symptoms**:
- Disk space exhaustion
- PVC mounting failures
- Log rotation not working

**Diagnosis**:
```bash
# Check disk usage in pods
kubectl exec <pod-name> -n production -- df -h

# Check PVC status
kubectl get pvc -n production

# Check storage class
kubectl get storageclass
```

**Solutions**:
```bash
# Clean up logs
kubectl exec <pod-name> -n production -- find /var/log -name "*.log" -mtime +7 -delete

# Increase PVC size (if supported)
kubectl patch pvc shepherd-data -n production -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

## Network and Connectivity Issues

### DNS Resolution Problems

**Symptoms**:
- "Name resolution failed" errors
- Intermittent connectivity to external services
- DNS timeouts

**Diagnosis**:
```bash
# Test DNS resolution from pod
kubectl exec <pod-name> -n production -- nslookup kubernetes.default.svc.cluster.local

# Check DNS configuration
kubectl get configmap coredns -n kube-system -o yaml

# Test external DNS
kubectl exec <pod-name> -n production -- nslookup google.com
```

**Solutions**:
```bash
# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Update DNS policy
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "dnsPolicy": "ClusterFirst",
        "dnsConfig": {
          "options": [{"name": "ndots", "value": "2"}]
        }
      }
    }
  }
}'
```

### Service Mesh Issues

**Symptoms**:
- Service-to-service communication failures
- mTLS certificate errors
- Traffic routing issues

**Diagnosis**:
```bash
# Check Istio sidecars (if using Istio)
kubectl get pods -n production -o jsonpath='{.items[*].spec.containers[*].name}' | grep istio-proxy

# Check service mesh configuration
kubectl get virtualservice,destinationrule -n production

# Check certificates
kubectl exec <pod-name> -c istio-proxy -n production -- openssl x509 -in /etc/ssl/certs/cert-chain.pem -text
```

### Load Balancer Issues

**Symptoms**:
- External traffic not reaching pods
- SSL/TLS termination issues
- Uneven traffic distribution

**Diagnosis**:
```bash
# Check load balancer status
kubectl get service shepherd -n production -o wide

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Test load balancer endpoints
curl -I -k https://<external-ip>/api/health
```

## Configuration and Secret Issues

### Secret Mounting Problems

**Symptoms**:
- "Secret not found" errors
- Empty environment variables
- Authentication failures

**Diagnosis**:
```bash
# Check secret existence
kubectl get secrets -n production | grep shepherd

# Verify secret contents
kubectl describe secret shepherd-secret -n production

# Check secret mounting in pods
kubectl describe pod <pod-name> -n production | grep -A 10 "Mounts:"

# Verify environment variables
kubectl exec <pod-name> -n production -- env | grep -i shepherd
```

**Solutions**:
```bash
# Recreate secret
kubectl delete secret shepherd-secret -n production
kubectl create secret generic shepherd-secret \
  --from-literal=mongodb-uri="mongodb://user:pass@host/db" \
  --from-literal=secret-key="new-secret-key"

# Update deployment to use secret
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "envFrom": [{"secretRef": {"name": "shepherd-secret"}}]
        }]
      }
    }
  }
}'
```

### ConfigMap Issues

**Symptoms**:
- Configuration not loading
- Default values being used instead of custom config
- Config file not found errors

**Diagnosis**:
```bash
# Check ConfigMap
kubectl get configmap shepherd-config -n production -o yaml

# Verify mounting
kubectl describe pod <pod-name> -n production | grep -A 5 "Volumes:"

# Check file contents in pod
kubectl exec <pod-name> -n production -- cat /etc/config/config.yaml
```

**Solutions**:
```bash
# Update ConfigMap
kubectl create configmap shepherd-config --from-file=config.yaml --dry-run=client -o yaml | kubectl apply -n production -f -

# Restart deployment to pick up changes
kubectl rollout restart deployment/shepherd -n production
```

## Image and Registry Issues

### Registry Authentication

**Symptoms**:
- "unauthorized" errors when pulling images
- ImagePullBackOff with authentication failures
- Token expired errors

**Solutions**:
```bash
# Create new registry secret
kubectl create secret docker-registry shepherd-registry \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_TOKEN \
  --docker-email=$GITHUB_EMAIL \
  -n production

# Update service account
kubectl patch serviceaccount shepherd -n production -p '{"imagePullSecrets": [{"name": "shepherd-registry"}]}'
```

### Image Build Issues

**Symptoms**:
- Wrong architecture images (ARM vs x86)
- Missing dependencies in image
- Outdated base images

**Diagnosis**:
```bash
# Check image details
docker manifest inspect ghcr.io/namespace/shepherd:tag

# Verify image architecture
kubectl describe pod <pod-name> -n production | grep -A 5 "Image:"
```

**Solutions**:
```bash
# Build multi-architecture image
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/namespace/shepherd:tag .

# Use specific architecture
kubectl set image deployment/shepherd shepherd=ghcr.io/namespace/shepherd:tag-amd64 -n production
```

## Database-Related Issues

### MongoDB Connection Issues

**Symptoms**:
- "Failed to connect to MongoDB" errors
- Authentication failures
- Connection timeouts

**Diagnosis**:
```bash
# Test MongoDB connectivity
kubectl exec <pod-name> -n production -- nc -zv mongodb-0.mongodb.svc.cluster.local 27017

# Check MongoDB logs
kubectl logs mongodb-0 -n mongodb

# Test authentication
kubectl exec <pod-name> -n production -- mongosh "mongodb://user:pass@mongodb-0.mongodb.svc.cluster.local:27017/db" --eval "db.adminCommand('ping')"
```

**Solutions**:
```bash
# Update MongoDB URI
kubectl patch secret shepherd-secret -n production -p '{"data":{"mongodb-uri":"'$(echo -n "mongodb://newuser:newpass@mongodb-0.mongodb.svc.cluster.local:27017/shepherd_cms" | base64)'"}}'

# Restart pods to pick up new credentials
kubectl rollout restart deployment/shepherd -n production
```

### Database Performance Issues

**Symptoms**:
- Slow query responses
- Connection pool exhaustion
- Database timeouts

**Diagnosis**:
```bash
# Check database performance metrics
kubectl exec mongodb-0 -n mongodb -- mongosh --eval "db.serverStatus().metrics"

# Monitor slow queries
kubectl exec mongodb-0 -n mongodb -- mongosh --eval "db.setProfilingLevel(2, {slowms: 100})"
kubectl exec mongodb-0 -n mongodb -- mongosh --eval "db.system.profile.find().limit(5).sort({ts:-1}).pretty()"
```

**Solutions**:
```bash
# Add database indexes
kubectl exec <pod-name> -n production -- python -c "
from pymongo import MongoClient
import os
client = MongoClient(os.environ['MONGODB_URI'])
db = client[os.environ['DATABASE_NAME']]
db.configurations.create_index([('environment', 1), ('service', 1)])
"

# Increase connection pool size
kubectl set env deployment/shepherd MONGODB_MAX_POOL_SIZE=50 -n production
```

## Performance Troubleshooting

### High Latency

**Symptoms**:
- Slow API response times
- Request timeouts
- User complaints about performance

**Diagnosis**:
```bash
# Check response times
kubectl exec <pod-name> -n production -- curl -w "@curl-format.txt" -o /dev/null -s http://localhost:5000/api/health

# Monitor request duration
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -E "request.*duration|response.*time"

# Check resource usage
kubectl top pods -n production -l app.kubernetes.io/name=shepherd
```

**Solutions**:
```bash
# Enable performance profiling
kubectl set env deployment/shepherd ENABLE_PROFILING=true -n production

# Scale up replicas
kubectl scale deployment shepherd --replicas=5 -n production

# Increase resource limits
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "shepherd",
          "resources": {
            "limits": {"cpu": "2000m", "memory": "2Gi"},
            "requests": {"cpu": "1000m", "memory": "1Gi"}
          }
        }]
      }
    }
  }
}'
```

### Memory Leaks

**Symptoms**:
- Gradually increasing memory usage
- Pods getting OOMKilled after running for a while
- Performance degradation over time

**Diagnosis**:
```bash
# Monitor memory usage over time
kubectl top pods -n production -l app.kubernetes.io/name=shepherd --sort-by=memory

# Check for memory leaks in logs
kubectl logs <pod-name> -n production | grep -i "memory\|gc\|heap"

# Generate memory dump
kubectl exec <pod-name> -n production -- python -c "
import tracemalloc
tracemalloc.start()
# ... your application code ...
current, peak = tracemalloc.get_traced_memory()
print(f'Current memory usage: {current / 1024 / 1024} MB')
print(f'Peak memory usage: {peak / 1024 / 1024} MB')
"
```

**Solutions**:
```bash
# Enable garbage collection logging
kubectl set env deployment/shepherd PYTHONHASHSEED=0 -n production
kubectl set env deployment/shepherd PYTHONDONTWRITEBYTECODE=1 -n production

# Implement memory limits per request
kubectl set env deployment/shepherd MAX_REQUEST_MEMORY=100MB -n production

# Restart pods periodically
kubectl patch deployment shepherd -n production -p '{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "scheduler.alpha.kubernetes.io/critical-pod": "true"
        }
      }
    }
  }
}'
```

## Rollback Troubleshooting

### Rollback Failures

**Symptoms**:
- Rollback command fails to complete
- Pods stuck in old version after rollback
- Rollback script errors

**Diagnosis**:
```bash
# Check rollback history
helm history shepherd -n production

# Check current revision
kubectl rollout status deployment/shepherd -n production

# Check for blocking issues
kubectl get events -n production --sort-by='.lastTimestamp' | head -20
```

**Solutions**:
```bash
# Force rollback to specific revision
kubectl rollout undo deployment/shepherd --to-revision=3 -n production

# If Helm rollback fails, use kubectl
kubectl patch deployment shepherd -n production -p '{"spec":{"template":{"spec":{"containers":[{"name":"shepherd","image":"ghcr.io/namespace/shepherd:v1.1.0"}]}}}}'

# Clear stuck rollout
kubectl rollout restart deployment/shepherd -n production
```

### Cascading Rollback Issues

**Symptoms**:
- Multiple versions failing
- Unable to find stable version
- Rollback loops

**Solutions**:
```bash
# Find last known good revision
helm history shepherd -n production | grep DEPLOYED

# Force rollback to known good version
./scripts/rollback.sh \
  --namespace production \
  --revision 2 \
  --force \
  --reason "Cascading failure - emergency rollback"

# If all else fails, redeploy from scratch
helm uninstall shepherd -n production
helm install shepherd ./helm/shepherd -f helm/shepherd/values-prod.yaml -n production
```

## CI/CD Pipeline Issues

### GitHub Actions Failures

**Symptoms**:
- Deployment workflow fails
- Authentication errors in CI/CD
- Timeout errors during deployment

**Diagnosis**:
```bash
# Check workflow logs in GitHub Actions UI
# Verify secrets are properly configured
# Check resource quotas in cluster
```

**Common Solutions**:

#### Kubeconfig Issues
```yaml
# Update kubeconfig secret in GitHub
# Ensure proper RBAC permissions
# Verify cluster connectivity
```

#### Resource Quotas
```bash
# Check quotas
kubectl describe quota -n production

# Request quota increase or clean up resources
kubectl delete old-deployments -n production
```

#### Timeout Issues
```yaml
# Increase timeout in workflow
- name: Deploy to Production
  run: ./scripts/deploy.sh --namespace production --timeout 1800
```

### Secret Management in CI/CD

**Symptoms**:
- Secrets not available in pipeline
- Authentication failures during deployment
- Environment variable not set errors

**Solutions**:
```bash
# Verify secrets in GitHub repository settings
# Check secret references in workflow files
# Ensure proper secret mounting in deployment
```

## Monitoring and Alerting Issues

### Missing Metrics

**Symptoms**:
- Prometheus not scraping metrics
- Grafana dashboards showing no data
- Alerting rules not firing

**Diagnosis**:
```bash
# Check metrics endpoint
curl http://shepherd.production.svc.cluster.local:5000/metrics

# Verify ServiceMonitor
kubectl get servicemonitor -n production

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then visit http://localhost:9090/targets
```

**Solutions**:
```bash
# Update ServiceMonitor
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: shepherd
  namespace: production
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: shepherd
  endpoints:
  - port: http
    path: /metrics
EOF

# Restart Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

### Alert Fatigue

**Symptoms**:
- Too many false positive alerts
- Important alerts being ignored
- Alert storms during deployments

**Solutions**:
```bash
# Implement alert silencing during deployments
# Tune alert thresholds
# Group related alerts
# Implement escalation policies
```

## Advanced Debugging Techniques

### Pod Network Debugging

```bash
# Create debug pod with network tools
kubectl run debug-net --image=nicolaka/netshoot --rm -it --restart=Never

# Inside debug pod:
# Test connectivity to service
nc -zv shepherd.production.svc.cluster.local 5000

# Check routing table
ip route

# Test DNS resolution
dig shepherd.production.svc.cluster.local

# Trace network path
traceroute shepherd.production.svc.cluster.local
```

### Application Performance Profiling

```bash
# Enable Python profiling
kubectl set env deployment/shepherd ENABLE_PROFILING=true -n production

# Generate flame graph
kubectl exec <pod-name> -n production -- python -m cProfile -o profile.stats app.py

# Memory profiling
kubectl exec <pod-name> -n production -- python -m memory_profiler app.py
```

### Cluster-Level Debugging

```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get componentstatuses

# Check system pods
kubectl get pods -n kube-system

# Check resource usage across cluster
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check etcd health
kubectl exec -n kube-system etcd-master -- etcdctl endpoint health
```

### Using Debug Containers (Kubernetes 1.18+)

```bash
# Attach debug container to running pod
kubectl debug <pod-name> -it --image=busybox --target=shepherd -n production

# Create debug copy of pod
kubectl debug <pod-name> -it --image=busybox --copy-to=debug-copy -n production
```

## Prevention Strategies

### Proactive Monitoring

1. **Implement Comprehensive Health Checks**
   ```yaml
   readinessProbe:
     httpGet:
       path: /api/health
       port: 5000
     initialDelaySeconds: 30
     periodSeconds: 10
   ```

2. **Set Up Resource Monitoring**
   ```bash
   # Monitor resource trends
   # Set up alerts for resource exhaustion
   # Implement automatic scaling
   ```

3. **Log Aggregation and Analysis**
   ```bash
   # Centralize logs with ELK stack or similar
   # Set up log-based alerts
   # Implement log retention policies
   ```

### Testing Strategies

1. **Comprehensive Testing Pipeline**
   ```bash
   # Unit tests
   # Integration tests
   # Load tests
   # Chaos engineering
   ```

2. **Environment Parity**
   ```bash
   # Keep staging environment similar to production
   # Test deployment procedures in staging
   # Validate configuration changes
   ```

### Documentation and Training

1. **Maintain Runbooks**
   - Update troubleshooting guides regularly
   - Document common issues and solutions
   - Include escalation procedures

2. **Team Training**
   - Regular kubernetes training
   - Incident response drills
   - Knowledge sharing sessions

---

## Quick Reference

### Emergency Commands
```bash
# Immediate rollback
./scripts/rollback.sh --namespace production --force

# Scale up quickly
kubectl scale deployment shepherd --replicas=10 -n production

# Check pod health
kubectl get pods -n production -l app.kubernetes.io/name=shepherd

# View recent events
kubectl get events -n production --sort-by='.lastTimestamp' | head -10

# Emergency pod restart
kubectl rollout restart deployment/shepherd -n production
```

### Common Log Patterns
```bash
# Connection errors
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -i "connection.*refused\|timeout\|unreachable"

# Authentication errors
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -i "auth.*fail\|unauthorized\|forbidden"

# Resource errors
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -i "memory\|cpu\|resource.*limit"

# Application errors
kubectl logs -n production -l app.kubernetes.io/name=shepherd | grep -E "(error|exception|traceback)" -A 5 -B 5
```

This troubleshooting guide provides systematic approaches to diagnose and resolve common deployment issues. Keep this guide updated as you encounter new issues and develop additional solutions.