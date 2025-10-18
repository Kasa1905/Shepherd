#!/bin/bash

# Shepherd Blue/Green Deployment Script
# Zero-downtime deployment for major version upgrades
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/var/log/shepherd-blue-green.log"

# Default values
DEFAULT_NAMESPACE="defaul        # Check pod status
        local failing_pods
        failing_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$ACTIVE_ENV --no-headers | grep -v "Running\|Completed" | wc -l)
        
        if [[ "$failing_pods" -gt 0 ]]; then
            error "Detected $failing_pods failing pods in $ACTIVE_ENV environment"
            error_detected=true
            break
        fi
        
        # Check for pod errors
        if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$ACTIVE_ENV | grep -E "CrashLoopBackOff|Error|ImagePullBackOff"; thenRACE_PERIOD=300
DEFAULT_SMOKE_TEST_TIMEOUT=120
DEFAULT_MONITOR_DURATION=120

# Script variables
NAMESPACE="$DEFAULT_NAMESPACE"
IMAGE_TAG=""
AUTO_SWITCH=false
GRACE_PERIOD="$DEFAULT_GRACE_PERIOD"
SMOKE_TEST_TIMEOUT="$DEFAULT_SMOKE_TEST_TIMEOUT"
MONITOR_DURATION="$DEFAULT_MONITOR_DURATION"

# Environment colors
BLUE="blue"
GREEN="green"
ACTIVE_ENV=""
INACTIVE_ENV=""

# Colors for output
RED='\033[0;31m'
GREEN_COLOR='\033[0;32m'
YELLOW='\033[1;33m'
BLUE_COLOR='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN_COLOR}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE_COLOR}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

highlight() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] >>> $1${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Blue/Green deployment script for zero-downtime major version upgrades

REQUIRED:
    -i, --image IMAGE_TAG         Docker image tag to deploy

OPTIONS:
    -n, --namespace NAMESPACE     Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    --auto                        Automatic traffic switch without confirmation
    --grace-period SECONDS        Grace period before cleanup (default: $DEFAULT_GRACE_PERIOD)
    --smoke-timeout SECONDS       Smoke test timeout (default: $DEFAULT_SMOKE_TEST_TIMEOUT)
    --monitor-duration SECONDS    Monitor duration after switch (default: $DEFAULT_MONITOR_DURATION)
    -h, --help                    Show this help message

EXAMPLES:
    # Interactive blue/green deployment
    $0 --namespace production --image shepherd:v2.0.0

    # Automated deployment
    $0 --namespace production --image shepherd:v2.0.0 --auto

    # Deploy with extended grace period
    $0 --namespace production --image shepherd:v2.0.0 --grace-period 600

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
            --auto)
                AUTO_SWITCH=true
                shift
                ;;
            --grace-period)
                GRACE_PERIOD="$2"
                shift 2
                ;;
            --smoke-timeout)
                SMOKE_TEST_TIMEOUT="$2"
                shift 2
                ;;
            --monitor-duration)
                MONITOR_DURATION="$2"
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

# Determine active environment
get_active_env() {
    log "Determining current active environment..."
    
    # Check service selector to determine active environment
    local current_selector
    current_selector=$(kubectl get service shepherd -n "$NAMESPACE" -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "")
    
    if [[ "$current_selector" == "blue" ]]; then
        ACTIVE_ENV="$BLUE"
        INACTIVE_ENV="$GREEN"
    elif [[ "$current_selector" == "green" ]]; then
        ACTIVE_ENV="$GREEN"
        INACTIVE_ENV="$BLUE"
    else
        # Default to blue if no deployment exists or no version selector
        ACTIVE_ENV="$BLUE"
        INACTIVE_ENV="$GREEN"
        warn "No existing version selector found, defaulting active environment to blue"
    fi
    
    log "Active environment: $ACTIVE_ENV"
    log "Inactive environment: $INACTIVE_ENV"
}

# Deploy to inactive environment
deploy_inactive() {
    highlight "Deploying new version to $INACTIVE_ENV environment"
    
    # Create values file for inactive environment
    local values_file="/tmp/values-$INACTIVE_ENV.yaml"
    cat > "$values_file" << EOF
app:
  image:
    tag: $IMAGE_TAG
  env:
    VERSION_LABEL: $INACTIVE_ENV

# Add version label for blue/green identification
podLabels:
  version: $INACTIVE_ENV

# Use separate release name for blue/green
nameOverride: shepherd-$INACTIVE_ENV
fullnameOverride: shepherd-$INACTIVE_ENV
EOF
    
    # Deploy to inactive environment using Helm
    log "Deploying Helm chart to $INACTIVE_ENV environment..."
    if helm upgrade --install "shepherd-$INACTIVE_ENV" "$PROJECT_ROOT/helm/shepherd" \
        --namespace "$NAMESPACE" \
        --values "$PROJECT_ROOT/helm/shepherd/values.yaml" \
        --values "$values_file" \
        --wait \
        --timeout 600s; then
        log "$INACTIVE_ENV environment deployment completed"
    else
        error "Failed to deploy to $INACTIVE_ENV environment"
        return 1
    fi
    
    # Wait for all pods to be ready
    log "Waiting for $INACTIVE_ENV pods to be ready..."
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=shepherd-$INACTIVE_ENV -n "$NAMESPACE" --timeout=300s; then
        log "All $INACTIVE_ENV pods are ready"
    else
        error "$INACTIVE_ENV pods failed to become ready"
        return 1
    fi
    
    # Clean up temporary values file
    rm -f "$values_file"
    
    log "✅ $INACTIVE_ENV environment deployment successful"
}

# Run smoke tests on inactive environment
smoke_test() {
    highlight "Running smoke tests on $INACTIVE_ENV environment"
    
    # Create temporary service for testing inactive environment
    log "Creating preview service for $INACTIVE_ENV environment..."
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: shepherd-$INACTIVE_ENV-preview
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: shepherd-preview
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 5000
      protocol: TCP
  selector:
    app.kubernetes.io/instance: shepherd-$INACTIVE_ENV
    version: $INACTIVE_ENV
EOF
    
    # Port forward to inactive environment for testing
    log "Setting up port forwarding for smoke tests..."
    kubectl port-forward -n "$NAMESPACE" "svc/shepherd-$INACTIVE_ENV-preview" 8080:80 &
    local port_forward_pid=$!
    
    # Give port-forward time to establish
    sleep 5
    
    # Run smoke tests
    local test_passed=true
    
    # Test 1: Health endpoint
    log "Testing health endpoint..."
    if timeout "$SMOKE_TEST_TIMEOUT" bash -c 'while ! curl -f -s http://localhost:8080/api/health >/dev/null 2>&1; do sleep 2; done'; then
        log "✅ Health endpoint test passed"
    else
        error "❌ Health endpoint test failed"
        test_passed=false
    fi
    
    # Test 2: API endpoints
    log "Testing API endpoints..."
    if curl -f -s http://localhost:8080/api/health | grep -q "status"; then
        log "✅ API response test passed"
    else
        error "❌ API response test failed"
        test_passed=false
    fi
    
    # Test 3: Metrics endpoint
    log "Testing metrics endpoint..."
    if curl -f -s http://localhost:8080/metrics >/dev/null 2>&1; then
        log "✅ Metrics endpoint test passed"
    else
        warn "⚠️ Metrics endpoint test failed (non-critical)"
    fi
    
    # Clean up port forward
    kill $port_forward_pid 2>/dev/null || true
    
    # Clean up preview service
    kubectl delete service "shepherd-$INACTIVE_ENV-preview" -n "$NAMESPACE" --ignore-not-found=true
    
    if [[ "$test_passed" == "true" ]]; then
        log "🎯 All smoke tests passed on $INACTIVE_ENV environment"
        return 0
    else
        error "💥 Smoke tests failed on $INACTIVE_ENV environment"
        return 1
    fi
}

# Switch traffic to new environment
switch_traffic() {
    highlight "Switching traffic from $ACTIVE_ENV to $INACTIVE_ENV"
    
    # Check if main service exists, create if missing
    if ! kubectl get svc shepherd -n "$NAMESPACE" &>/dev/null; then
        log "Main service 'shepherd' not found, creating it..."
        kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: shepherd
  labels:
    app.kubernetes.io/name: shepherd
    app.kubernetes.io/instance: shepherd
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: 5000
  selector:
    app.kubernetes.io/instance: shepherd-$INACTIVE_ENV
    version: $INACTIVE_ENV
EOF
        log "Main service created and configured for $INACTIVE_ENV"
        return 0
    fi
    
    # Update main service selector to point to new environment
    log "Updating service selector to route traffic to $INACTIVE_ENV..."
    if kubectl patch service shepherd -n "$NAMESPACE" -p "{\"spec\":{\"selector\":{\"app.kubernetes.io/instance\":\"shepherd-$INACTIVE_ENV\",\"version\":\"$INACTIVE_ENV\"}}}"; then
        log "Service selector updated successfully"
    else
        error "Failed to update service selector"
        return 1
    fi
    
    # Wait for service endpoints to update
    log "Waiting for service endpoints to update..."
    sleep 10
    
    # Verify traffic is flowing to new pods
    log "Verifying traffic routing..."
    local endpoint_count
    endpoint_count=$(kubectl get endpoints shepherd -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses}' | jq length 2>/dev/null || echo "0")
    
    if [[ "$endpoint_count" -gt 0 ]]; then
        log "✅ Traffic successfully routed to $INACTIVE_ENV environment"
        log "Service endpoints: $endpoint_count active"
        
        # Update environment variables
        ACTIVE_ENV="$INACTIVE_ENV"
        INACTIVE_ENV="$([[ "$ACTIVE_ENV" == "$BLUE" ]] && echo "$GREEN" || echo "$BLUE")"
        
        return 0
    else
        error "❌ No active endpoints found after traffic switch"
        return 1
    fi
}

# Monitor new environment for errors
monitor_new_environment() {
    highlight "Monitoring $ACTIVE_ENV environment for $MONITOR_DURATION seconds"
    
    local start_time
    start_time=$(date +%s)
    local end_time
    end_time=$((start_time + MONITOR_DURATION))
    local error_detected=false
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check pod status
        local failing_pods
        failing_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$ACTIVE_ENV --no-headers | grep -v "Running\|Completed" | wc -l)
        
        if [[ "$failing_pods" -gt 0 ]]; then
            error "Detected $failing_pods failing pods in $ACTIVE_ENV environment"
            error_detected=true
            break
        fi
        
        # Check for CrashLoopBackOff or other error states
        if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$ACTIVE_ENV | grep -E "CrashLoopBackOff|Error|ImagePullBackOff"; then
            error "Detected pods in error state in $ACTIVE_ENV environment"
            error_detected=true
            break
        fi
        
        # Test health endpoint periodically
        local pod_name
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$ACTIVE_ENV -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$pod_name" ]]; then
            if ! kubectl exec -n "$NAMESPACE" "$pod_name" -- curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
                error "Health endpoint check failed in $ACTIVE_ENV environment"
                error_detected=true
                break
            fi
        fi
        
        # Show progress
        local elapsed=$(($(date +%s) - start_time))
        local remaining=$((MONITOR_DURATION - elapsed))
        info "Monitoring... ${remaining}s remaining"
        
        sleep 10
    done
    
    if [[ "$error_detected" == "true" ]]; then
        error "💥 Errors detected in $ACTIVE_ENV environment during monitoring"
        return 1
    else
        log "✅ No errors detected during monitoring period"
        return 0
    fi
}

# Cleanup old environment
cleanup_old() {
    highlight "Cleaning up old $INACTIVE_ENV environment"
    
    log "Waiting for grace period of ${GRACE_PERIOD}s before cleanup..."
    sleep "$GRACE_PERIOD"
    
    # Scale down old environment deployment
    log "Scaling down $INACTIVE_ENV deployment to 0 replicas..."
    if kubectl scale deployment "shepherd-$INACTIVE_ENV" -n "$NAMESPACE" --replicas=0; then
        log "$INACTIVE_ENV deployment scaled down"
    else
        warn "Failed to scale down $INACTIVE_ENV deployment"
    fi
    
    # Optionally delete old deployment (commented out for quick rollback capability)
    # kubectl delete deployment "shepherd-$INACTIVE_ENV" -n "$NAMESPACE" --ignore-not-found=true
    
    log "🧹 Cleanup completed (deployment scaled to 0 for quick rollback)"
}

# Rollback to previous environment
rollback_blue_green() {
    local reason="${1:-Error detected in new environment}"
    warn "Initiating blue/green rollback due to: $reason"
    
    # Switch service selector back to previous environment
    log "Switching traffic back to $INACTIVE_ENV environment..."
    if kubectl patch service shepherd -n "$NAMESPACE" -p "{\"spec\":{\"selector\":{\"app.kubernetes.io/instance\":\"shepherd-$INACTIVE_ENV\",\"version\":\"$INACTIVE_ENV\"}}}"; then
        log "Service selector reverted successfully"
    else
        error "Failed to revert service selector"
        return 1
    fi
    
    # Check if old environment pods are still running
    local old_pod_count
    old_pod_count=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$INACTIVE_ENV --no-headers | wc -l)
    
    if [[ "$old_pod_count" -eq 0 ]]; then
        log "Scaling up $INACTIVE_ENV deployment for rollback..."
        kubectl scale deployment "shepherd-$INACTIVE_ENV" -n "$NAMESPACE" --replicas=2
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=shepherd-$INACTIVE_ENV -n "$NAMESPACE" --timeout=180s
    fi
    
    # Verify health on old environment
    log "Verifying health on rolled-back environment..."
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=shepherd-$INACTIVE_ENV -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]] && kubectl exec -n "$NAMESPACE" "$pod_name" -- curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "🔄 Rollback completed successfully"
        
        # Log rollback event
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] BLUE-GREEN-ROLLBACK: shepherd in $NAMESPACE - Reason: $reason" >> "$LOG_FILE"
        return 0
    else
        error "Rollback health checks failed"
        return 1
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    error "Blue/Green deployment failed with exit code: $exit_code"
    
    # Attempt automatic rollback on failure
    rollback_blue_green "Deployment script encountered an error"
    
    exit $exit_code
}

# Set up error handling
trap handle_error ERR

# Main execution
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "=== Shepherd Blue/Green Deployment Started ==="
    log "Command: $0 $*"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Determine current environment
    get_active_env
    
    # Deploy to inactive environment
    if ! deploy_inactive; then
        error "Failed to deploy to inactive environment"
        exit 1
    fi
    
    # Run smoke tests
    if ! smoke_test; then
        error "Smoke tests failed"
        exit 1
    fi
    
    # Confirm traffic switch (unless auto mode)
    if [[ "$AUTO_SWITCH" == "false" ]]; then
        echo -e "\n${CYAN}🔄 Ready to switch traffic from $ACTIVE_ENV to $INACTIVE_ENV${NC}"
        echo -e "${YELLOW}Current active environment: $ACTIVE_ENV${NC}"
        echo -e "${GREEN_COLOR}New environment ready: $INACTIVE_ENV${NC}"
        echo -n "Proceed with traffic switch? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Traffic switch cancelled by user"
            log "New environment remains available at shepherd-$INACTIVE_ENV service"
            exit 0
        fi
    fi
    
    # Switch traffic
    if ! switch_traffic; then
        error "Failed to switch traffic"
        rollback_blue_green "Traffic switch failed"
        exit 1
    fi
    
    # Monitor new environment
    if ! monitor_new_environment; then
        error "Issues detected during monitoring"
        rollback_blue_green "Errors detected during monitoring period"
        exit 1
    fi
    
    # Cleanup old environment
    cleanup_old
    
    # Success summary
    highlight "🎉 Blue/Green deployment completed successfully!"
    info "Traffic switched from $INACTIVE_ENV to $ACTIVE_ENV"
    info "Image deployed: $IMAGE_TAG"
    info "Old environment available for quick rollback: shepherd-$INACTIVE_ENV"
    
    log "=== Blue/Green Deployment Script Completed ==="
    exit 0
}

# Run main function with all arguments
main "$@"