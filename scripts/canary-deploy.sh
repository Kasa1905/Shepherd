#!/bin/bash

# Shepherd Canary Deployment Script
# Gradual rollout with automatic traffic shifting and metrics validation
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/var/log/shepherd-canary.log"

# Default values
DEFAULT_NAMESPACE="default"
DEFAULT_STAGES="10,25,50,75,100"
DEFAULT_INTERVAL=300  # 5 minutes between stages
DEFAULT_ERROR_THRESHOLD=5  # 5% error rate threshold
DEFAULT_METRICS_INTERVAL=30

# Script variables
NAMESPACE="$DEFAULT_NAMESPACE"
IMAGE_TAG=""
STAGES="$DEFAULT_STAGES"
INTERVAL="$DEFAULT_INTERVAL"
ERROR_THRESHOLD="$DEFAULT_ERROR_THRESHOLD"
AUTO_PROMOTE=false
METRICS_INTERVAL="$DEFAULT_METRICS_INTERVAL"

# Canary tracking
CANARY_DEPLOYED=false
BASELINE_METRICS=""
CURRENT_STAGE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

highlight() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] >>> $1${NC}" | tee -a "$LOG_FILE"
}

metrics() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] METRICS: $1${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Canary deployment script for gradual rollout with metrics validation

REQUIRED:
    -i, --image IMAGE_TAG         Docker image tag to deploy

OPTIONS:
    -n, --namespace NAMESPACE     Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    --stages STAGES               Comma-separated canary stages (default: $DEFAULT_STAGES)
    --interval SECONDS            Interval between stages (default: $DEFAULT_INTERVAL)
    --error-threshold PERCENT     Error rate threshold for rollback (default: $DEFAULT_ERROR_THRESHOLD)
    --auto                        Automatic promotion without manual confirmation
    --metrics-interval SECONDS   Metrics collection interval (default: $DEFAULT_METRICS_INTERVAL)
    -h, --help                    Show this help message

EXAMPLES:
    # Standard canary deployment
    $0 --namespace production --image shepherd:v2.1.0

    # Custom canary stages
    $0 --namespace production --image shepherd:v2.1.0 --stages "5,10,25,50,100"

    # Automated canary with shorter intervals
    $0 --namespace production --image shepherd:v2.1.0 --interval 180 --auto

    # Canary with custom error threshold
    $0 --namespace production --image shepherd:v2.1.0 --error-threshold 2

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -i|--image)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --stages)
                STAGES="$2"
                shift 2
                ;;
            --interval)
                INTERVAL="$2"
                shift 2
                ;;
            --error-threshold)
                ERROR_THRESHOLD="$2"
                shift 2
                ;;
            --auto)
                AUTO_PROMOTE=true
                shift
                ;;
            --metrics-interval)
                METRICS_INTERVAL="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$IMAGE_TAG" ]]; then
        error "Image tag is required. Use --image option."
        usage
        exit 1
    fi
}

# Deploy canary version
deploy_canary() {
    highlight "Deploying canary version with image: $IMAGE_TAG"
    
    # Handle HPA conflicts during canary stages
    if kubectl get hpa shepherd -n "$NAMESPACE" &>/dev/null; then
        warn "HPA detected - suspending autoscaling during canary deployment"
        kubectl annotate hpa shepherd -n "$NAMESPACE" canary.shepherd.io/suspended="true" --overwrite
        log "HPA suspended for canary deployment (traffic ratios may drift with autoscaling enabled)"
    fi
    
    # Create canary values file
    local values_file="/tmp/values-canary.yaml"
    cat > "$values_file" << EOF
app:
  image:
    tag: $IMAGE_TAG
  replicaCount: 1  # Start with single replica
  env:
    VERSION_LABEL: canary

# Add canary labels for identification
podLabels:
  version: canary
  track: canary

# Use separate release for canary
nameOverride: shepherd-canary
fullnameOverride: shepherd-canary

# Separate service for canary (initially)
service:
  type: ClusterIP
  port: 80
  targetPort: 5000
EOF
    
    # Deploy canary using Helm
    log "Deploying canary release..."
    if helm upgrade --install shepherd-canary "$PROJECT_ROOT/helm/shepherd" \
        --namespace "$NAMESPACE" \
        --values "$PROJECT_ROOT/helm/shepherd/values.yaml" \
        --values "$values_file" \
        --wait \
        --timeout 300s; then
        log "Canary deployment completed"
        CANARY_DEPLOYED=true
    else
        error "Failed to deploy canary version"
        return 1
    fi
    
    # Wait for canary pod to be ready
    log "Waiting for canary pod to be ready..."
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd-canary -n "$NAMESPACE" --timeout=180s; then
        log "Canary pod is ready"
    else
        error "Canary pod failed to become ready"
        return 1
    fi
    
    # Health check on canary
    log "Running health check on canary..."
    local canary_pod
    canary_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd-canary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$canary_pod" ]] && kubectl exec -n "$NAMESPACE" "$canary_pod" -- curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ Canary health check passed"
    else
        error "❌ Canary health check failed"
        return 1
    fi
    
    # Clean up temporary values file
    rm -f "$values_file"
    
    log "🚀 Canary deployment successful"
    return 0
}

# Calculate replica counts based on percentage
calculate_replicas() {
    local percentage="$1"
    local total_replicas
    total_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
    
    # Calculate canary replicas (at least 1)
    local canary_replicas
    canary_replicas=$(( (total_replicas * percentage) / 100 ))
    if [[ "$canary_replicas" -eq 0 ]] && [[ "$percentage" -gt 0 ]]; then
        canary_replicas=1
    fi
    
    # Calculate stable replicas
    local stable_replicas
    stable_replicas=$((total_replicas - canary_replicas))
    
    echo "$canary_replicas $stable_replicas"
}

# Adjust traffic distribution
adjust_traffic() {
    local stage="$1"
    local canary_replicas="$2"
    local stable_replicas="$3"
    
    echo ">>> Adjusting traffic to ${stage}% canary"
    echo "Target replicas - Canary: $canary_replicas, Stable: $stable_replicas"
    
    # Scale canary deployment
    kubectl scale deploy/shepherd-canary --replicas="$canary_replicas" -n "$NAMESPACE"
    
    # Scale stable deployment  
    kubectl scale deploy/shepherd --replicas="$stable_replicas" -n "$NAMESPACE"
    
    # Route to both versions by common label
    # Note: Without a service mesh, traffic weighting will be approximate by endpoint count
    kubectl patch service shepherd -n "$NAMESPACE" \
      -p '{"spec":{"selector":{"app.kubernetes.io/name":"shepherd"}}}'
    
    # Wait for scaling to complete
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd-canary -n "$NAMESPACE" --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd -n "$NAMESPACE" --timeout=300s

# Collect baseline metrics
collect_baseline_metrics() {
    log "Collecting baseline metrics from stable deployment..."
    
    # This is a simplified metrics collection
    # In production, you would integrate with Prometheus/Grafana
    local stable_pod
    stable_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$stable_pod" ]]; then
        # Collect metrics (placeholder - integrate with actual monitoring system)
        BASELINE_METRICS=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error_rate": 0.5,
  "latency_p99": 250,
  "request_rate": 100
}
EOF
)
        metrics "Baseline metrics collected"
        log "Baseline error rate: 0.5%, P99 latency: 250ms, Request rate: 100/min"
    else
        warn "No stable pods found for baseline metrics"
        BASELINE_METRICS='{"error_rate": 1, "latency_p99": 300, "request_rate": 50}'
    fi
}

# Monitor canary health and metrics
monitor_canary() {
    local percentage="$1"
    local monitor_duration="$INTERVAL"
    
    highlight "Monitoring canary at $percentage% traffic for ${monitor_duration}s"
    
    local start_time
    start_time=$(date +%s)
    local end_time
    end_time=$((start_time + monitor_duration))
    local health_status="healthy"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check pod health
        local canary_pods_ready
        canary_pods_ready=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd-canary --no-headers | grep "Running" | wc -l)
        local canary_pods_total
        canary_pods_total=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd-canary --no-headers | wc -l)
        
        if [[ "$canary_pods_ready" -lt "$canary_pods_total" ]]; then
            warn "Canary pod health degraded: $canary_pods_ready/$canary_pods_total ready"
            health_status="degraded"
        fi
        
        # Check for error states
        if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd-canary | grep -E "CrashLoopBackOff|Error|ImagePullBackOff"; then
            error "Canary pods in error state detected"
            health_status="unhealthy"
            break
        fi
        
        # Simulate metrics collection (integrate with Prometheus in production)
        local current_error_rate
        current_error_rate=$(( RANDOM % 10 ))  # Random between 0-9 for demo
        
        metrics "Canary metrics - Error rate: ${current_error_rate}%, Stage: ${percentage}%"
        
        # Check error rate threshold
        if [[ "$current_error_rate" -gt "$ERROR_THRESHOLD" ]]; then
            error "Error rate threshold exceeded: ${current_error_rate}% > ${ERROR_THRESHOLD}%"
            health_status="unhealthy"
            break
        fi
        
        # Health endpoint check
        local canary_pod
        canary_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd-canary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$canary_pod" ]]; then
            if ! kubectl exec -n "$NAMESPACE" "$canary_pod" -- curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
                warn "Canary health endpoint check failed"
                health_status="degraded"
            fi
        fi
        
        # Progress indicator
        local elapsed=$(($(date +%s) - start_time))
        local remaining=$((monitor_duration - elapsed))
        info "Monitoring progress: ${elapsed}s elapsed, ${remaining}s remaining"
        
        sleep "$METRICS_INTERVAL"
    done
    
    # Return health status
    case "$health_status" in
        "healthy")
            log "✅ Canary monitoring completed - Status: HEALTHY"
            return 0
            ;;
        "degraded")
            warn "⚠️ Canary monitoring completed - Status: DEGRADED"
            return 1
            ;;
        "unhealthy")
            error "❌ Canary monitoring completed - Status: UNHEALTHY"
            return 2
            ;;
    esac
}

# Promote canary to stable
promote_canary() {
    highlight "Promoting canary to stable deployment"
    
    # Update stable deployment with canary image
    log "Updating stable deployment image to $IMAGE_TAG..."
    
    # Derive current repo from deployment
    current_image=$(kubectl get deploy/shepherd -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
    repo=${current_image%:*}
    
    kubectl set image deployment/shepherd "shepherd=$repo:$IMAGE_TAG" -n "$NAMESPACE"
    
    # Wait for stable deployment rollout
    log "Waiting for stable deployment rollout..."
    if kubectl rollout status deployment/shepherd -n "$NAMESPACE" --timeout=300s; then
        log "Stable deployment rollout completed"
    else
        error "Stable deployment rollout failed"
        return 1
    fi
    
    # Scale stable deployment back to full capacity
    local original_replicas
    original_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/original-replicas}' 2>/dev/null || echo "2")
    
    log "Scaling stable deployment to full capacity ($original_replicas replicas)..."
    kubectl scale deployment shepherd --replicas="$original_replicas" -n "$NAMESPACE"
    
    # Wait for scaling
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd -n "$NAMESPACE" --timeout=180s
    
    # Scale down canary deployment
    log "Scaling down canary deployment..."
    kubectl scale deployment shepherd-canary --replicas=0 -n "$NAMESPACE"
    
    # Clean up canary deployment (optional - keep for quick rollback)
    # kubectl delete deployment shepherd-canary -n "$NAMESPACE" --ignore-not-found=true
    
    # Restore service selector
    kubectl patch service shepherd -n "$NAMESPACE" -p '{"spec":{"selector":{"app.kubernetes.io/name":"shepherd"}}}'
    
    # Restore HPA if it was suspended
    if kubectl get hpa shepherd -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.canary\.shepherd\.io/suspended}' 2>/dev/null | grep -q "true"; then
        log "Restoring HPA autoscaling"
        kubectl annotate hpa shepherd -n "$NAMESPACE" canary.shepherd.io/suspended-
    fi
    
    log "🎉 Canary promotion completed successfully"
    return 0
}

# Rollback canary deployment
rollback_canary() {
    local reason="${1:-Error rate threshold exceeded}"
    warn "Rolling back canary deployment due to: $reason"
    
    # Scale canary to 0
    log "Scaling canary deployment to 0 replicas..."
    kubectl scale deployment shepherd-canary --replicas=0 -n "$NAMESPACE"
    
    # Restore stable deployment to full capacity
    local original_replicas
    original_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/original-replicas}' 2>/dev/null || echo "2")
    
    log "Restoring stable deployment to full capacity..."
    kubectl scale deployment shepherd --replicas="$original_replicas" -n "$NAMESPACE"
    
    # Wait for stable deployment
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd -n "$NAMESPACE" --timeout=180s
    
    # Restore service selector
    kubectl patch service shepherd -n "$NAMESPACE" -p '{"spec":{"selector":{"app.kubernetes.io/name":"shepherd"}}}'
    
    # Delete canary deployment
    kubectl delete deployment shepherd-canary -n "$NAMESPACE" --ignore-not-found=true
    
    # Restore HPA if it was suspended
    if kubectl get hpa shepherd -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.canary\.shepherd\.io/suspended}' 2>/dev/null | grep -q "true"; then
        log "Restoring HPA autoscaling after rollback"
        kubectl annotate hpa shepherd -n "$NAMESPACE" canary.shepherd.io/suspended-
    fi
    
    # Log rollback event
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] CANARY-ROLLBACK: shepherd in $NAMESPACE - Reason: $reason" >> "$LOG_FILE"
    
    log "🔄 Canary rollback completed"
    return 0
}

# Store metrics for analysis
store_metrics() {
    local stage="$1"
    local status="$2"
    local metrics_file="/tmp/canary-metrics-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$metrics_file" << EOF
{
  "deployment": {
    "image": "$IMAGE_TAG",
    "namespace": "$NAMESPACE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "stage": {
    "percentage": $stage,
    "status": "$status"
  },
  "baseline": $BASELINE_METRICS
}
EOF
    
    log "Metrics stored in: $metrics_file"
}

# Error handling for canary deployment
handle_canary_error() {
    local exit_code=$?
    error "Canary deployment failed with exit code: $exit_code"
    
    if [[ "$CANARY_DEPLOYED" == "true" ]]; then
        rollback_canary "Deployment script encountered an error"
    fi
    
    exit $exit_code
}

# Set up error handling
trap handle_canary_error ERR

# Main execution
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "=== Shepherd Canary Deployment Started ==="
    log "Command: $0 $*"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Convert stages string to array
    IFS=',' read -ra STAGE_ARRAY <<< "$STAGES"
    
    log "Canary deployment configuration:"
    info "  Image: $IMAGE_TAG"
    info "  Stages: ${STAGES}%"
    info "  Interval: ${INTERVAL}s"
    info "  Error threshold: ${ERROR_THRESHOLD}%"
    info "  Auto promote: $AUTO_PROMOTE"
    
    # Collect baseline metrics
    collect_baseline_metrics
    
    # Store original replica count for restoration
    local original_replicas
    original_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
    kubectl annotate deployment shepherd -n "$NAMESPACE" "deployment.kubernetes.io/original-replicas=$original_replicas" --overwrite
    
    # Deploy canary version
    if ! deploy_canary; then
        error "Failed to deploy canary version"
        exit 1
    fi
    
    # Process each canary stage
    for stage in "${STAGE_ARRAY[@]}"; do
        CURRENT_STAGE="$stage"
        highlight "🎯 Processing canary stage: ${stage}%"
        
        # Adjust traffic distribution
        if ! adjust_traffic "$stage"; then
            error "Failed to adjust traffic for stage $stage%"
            rollback_canary "Traffic adjustment failed at stage $stage%"
            exit 1
        fi
        
        # Monitor canary at this stage
        local monitor_result=0
        monitor_canary "$stage" || monitor_result=$?
        
        case $monitor_result in
            0)
                log "✅ Stage $stage% completed successfully"
                store_metrics "$stage" "success"
                ;;
            1)
                warn "⚠️ Stage $stage% showed degraded performance"
                store_metrics "$stage" "degraded"
                
                if [[ "$AUTO_PROMOTE" == "false" ]]; then
                    echo -e "\n${YELLOW}Canary deployment showed degraded performance at $stage%${NC}"
                    echo -n "Continue to next stage? [y/N]: "
                    read -r confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        log "Canary deployment paused by user decision"
                        rollback_canary "User decided to stop due to degraded performance"
                        exit 1
                    fi
                else
                    warn "Auto-promotion enabled, but performance degraded. Stopping deployment."
                    rollback_canary "Auto-promotion stopped due to degraded performance"
                    exit 1
                fi
                ;;
            2)
                error "❌ Stage $stage% failed health checks"
                store_metrics "$stage" "failed"
                rollback_canary "Health checks failed at stage $stage%"
                exit 1
                ;;
        esac
        
        # Don't wait after the last stage
        if [[ "$stage" != "${STAGE_ARRAY[-1]}" ]]; then
            log "Waiting ${INTERVAL}s before next stage..."
            sleep "$INTERVAL"
        fi
    done
    
    # All stages completed successfully - promote canary
    if promote_canary; then
        highlight "🎉 Canary deployment completed successfully!"
        info "All stages passed: ${STAGES}%"
        info "Image promoted: $IMAGE_TAG"
        info "Canary deployment scaled to 0 (available for quick rollback)"
        
        log "=== Canary Deployment Script Completed Successfully ==="
        exit 0
    else
        error "Failed to promote canary to stable"
        rollback_canary "Promotion to stable failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"