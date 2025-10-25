#!/bin/bash

# Shepherd Zero-Downtime Deployment Script
# Orchestrates rolling updates with validation and automatic rollback
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Use workspace-relative log file for CI/CD compatibility
LOG_FILE="${LOG_FILE:-${PROJECT_ROOT}/shepherd-deploy.log}"

# Default values
DEFAULT_NAMESPACE="default"
DEFAULT_RELEASE_NAME="shepherd"
DEFAULT_CHART_PATH="$PROJECT_ROOT/helm/shepherd"
DEFAULT_VALUES_FILE="$PROJECT_ROOT/helm/shepherd/values.yaml"
DEFAULT_TIMEOUT=600
DEFAULT_HEALTH_RETRIES=3
DEFAULT_HEALTH_DELAY=10

# Script variables
NAMESPACE="$DEFAULT_NAMESPACE"
RELEASE_NAME="$DEFAULT_RELEASE_NAME"
CHART_PATH="$DEFAULT_CHART_PATH"
VALUES_FILE="$DEFAULT_VALUES_FILE"
TIMEOUT="$DEFAULT_TIMEOUT"
DRY_RUN=false
WAIT=true
SKIP_CONFIRMATION=false
HEALTH_RETRIES="$DEFAULT_HEALTH_RETRIES"
HEALTH_DELAY="$DEFAULT_HEALTH_DELAY"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Zero-downtime deployment script for Shepherd Configuration Management System

OPTIONS:
    -n, --namespace NAMESPACE     Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    -r, --release RELEASE         Helm release name (default: $DEFAULT_RELEASE_NAME)
    -c, --chart PATH              Helm chart path (default: $DEFAULT_CHART_PATH)
    -f, --values FILE             Values file path (default: $DEFAULT_VALUES_FILE)
    -t, --timeout SECONDS         Deployment timeout (default: $DEFAULT_TIMEOUT)
    --dry-run                     Preview changes without applying
    --no-wait                     Don't wait for deployment completion
    -y, --yes                     Skip confirmation prompts
    --health-retries COUNT        Health check retry attempts (default: $DEFAULT_HEALTH_RETRIES)
    --health-delay SECONDS        Delay between health checks (default: $DEFAULT_HEALTH_DELAY)
    -h, --help                    Show this help message

EXAMPLES:
    # Standard deployment
    $0 --namespace production --release shepherd

    # Dry-run to preview changes
    $0 --namespace staging --dry-run

    # Deploy with custom timeout
    $0 --namespace production --timeout 900 --yes

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
            -r|--release)
                RELEASE_NAME="$2"
                shift 2
                ;;
            -c|--chart)
                CHART_PATH="$2"
                shift 2
                ;;
            -f|--values)
                VALUES_FILE="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-wait)
                WAIT=false
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --health-retries)
                HEALTH_RETRIES="$2"
                shift 2
                ;;
            --health-delay)
                HEALTH_DELAY="$2"
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
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."
    
    # Check if kubectl is installed and configured
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Verify namespace exists or create it
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        warn "Namespace '$NAMESPACE' does not exist, creating it..."
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Validate Helm chart syntax
    log "Validating Helm chart syntax..."
    if ! helm lint "$CHART_PATH" &> /dev/null; then
        error "Helm chart validation failed"
        helm lint "$CHART_PATH"
        exit 1
    fi
    
    # Check if values file exists
    if [[ ! -f "$VALUES_FILE" ]]; then
        error "Values file not found: $VALUES_FILE"
        exit 1
    fi
    
    # Verify required secrets exist
    if ! kubectl get secret shepherd-secret -n "$NAMESPACE" &> /dev/null; then
        warn "Required secret 'shepherd-secret' not found in namespace '$NAMESPACE'"
        warn "Make sure to create secrets before deployment"
    fi
    
    # Test MongoDB connectivity if external MongoDB is configured
    if grep -q "external.*enabled.*true" "$VALUES_FILE" 2>/dev/null; then
        log "External MongoDB detected, checking connectivity..."
        # This is a placeholder - in real deployment, you'd test actual connectivity
        log "MongoDB connectivity check passed (placeholder)"
    fi
    
    log "Pre-flight checks completed successfully"
}

# Health check function
check_health() {
    local attempt=1
    local max_attempts="$HEALTH_RETRIES"
    local delay="$HEALTH_DELAY"
    
    log "Running health checks (max attempts: $max_attempts)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Health check attempt $attempt/$max_attempts"
        
        # Wait for all pods to be ready
        if kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance="$RELEASE_NAME" -n "$NAMESPACE" --timeout=60s &> /dev/null; then
            log "All pods are ready"
            
            # Get a ready pod for health endpoint testing
            local pod_name
            pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            
            if [[ -n "$pod_name" ]]; then
                # Test health endpoint
                if kubectl exec -n "$NAMESPACE" "$pod_name" -- curl -f -s http://localhost:5000/api/health &> /dev/null; then
                    log "Health endpoint check passed"
                    
                    # Test metrics endpoint
                    if kubectl exec -n "$NAMESPACE" "$pod_name" -- curl -f -s http://localhost:5000/metrics &> /dev/null; then
                        log "Metrics endpoint check passed"
                        log "Health checks completed successfully"
                        return 0
                    else
                        warn "Metrics endpoint check failed"
                    fi
                else
                    warn "Health endpoint check failed"
                fi
            else
                warn "No pods found for health checking"
            fi
        else
            warn "Pods are not ready yet"
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "Waiting ${delay}s before next health check attempt..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    error "Health checks failed after $max_attempts attempts"
    return 1
}

# Get current revision for rollback purposes
get_current_revision() {
    helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json 2>/dev/null | jq -r '.[0].revision // "0"' 2>/dev/null || echo "0"
}

# Deployment function
deploy() {
    log "Starting deployment of $RELEASE_NAME to namespace $NAMESPACE"
    
    # Get current revision before deployment
    local current_revision
    current_revision=$(get_current_revision)
    log "Current revision: $current_revision"
    
    # Build Helm command
    local helm_cmd="helm upgrade --install $RELEASE_NAME $CHART_PATH"
    helm_cmd+=" --namespace $NAMESPACE"
    helm_cmd+=" --values $VALUES_FILE"
    
    if [[ "$WAIT" == "true" ]]; then
        helm_cmd+=" --wait --timeout ${TIMEOUT}s"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        helm_cmd+=" --dry-run"
        log "Dry-run mode: $helm_cmd"
        eval "$helm_cmd"
        return 0
    fi
    
    # Show deployment plan
    log "Deployment plan:"
    info "  Release: $RELEASE_NAME"
    info "  Namespace: $NAMESPACE"
    info "  Chart: $CHART_PATH"
    info "  Values: $VALUES_FILE"
    info "  Timeout: ${TIMEOUT}s"
    
    # Confirmation prompt
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo -n "Proceed with deployment? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute Helm upgrade
    log "Executing Helm upgrade..."
    if eval "$helm_cmd"; then
        log "Helm upgrade completed successfully"
        
        # Monitor rollout status
        log "Monitoring rollout status..."
        deploy_name=$(kubectl get deploy -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
        if kubectl rollout status deployment/$deploy_name -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
            log "Rollout completed successfully"
            
            # Run post-deployment health checks
            if check_health; then
                log "Post-deployment health checks passed"
                
                # Display deployment summary
                display_deployment_summary "$current_revision"
                
                log "🎉 Deployment completed successfully!"
                return 0
            else
                error "Post-deployment health checks failed"
                return 1
            fi
        else
            error "Rollout status check failed"
            return 1
        fi
    else
        error "Helm upgrade failed"
        return 1
    fi
}

# Display deployment summary
display_deployment_summary() {
    local previous_revision="$1"
    local new_revision
    new_revision=$(get_current_revision)
    
    log "Deployment Summary:"
    info "  Previous revision: $previous_revision"
    info "  New revision: $new_revision"
    
    # Show current pod status
    log "Current pod status:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    
    # Show service status
    log "Service endpoints:"
    service_name=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$service_name" ]]; then
        kubectl get endpoints -n "$NAMESPACE" "$service_name" 2>/dev/null || info "Service endpoints not available"
    else
        info "Service not found for release $RELEASE_NAME"
    fi
}

# Rollback function
rollback() {
    local reason="${1:-Deployment failed health checks}"
    warn "Initiating rollback due to: $reason"
    
    # Get previous revision
    local previous_revision
    previous_revision=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 2 -o json | jq -r '.[1].revision // "1"' 2>/dev/null || echo "1")
    
    if [[ "$previous_revision" == "1" ]] && [[ "$(get_current_revision)" == "1" ]]; then
        error "No previous revision available for rollback"
        return 1
    fi
    
    log "Rolling back to revision $previous_revision"
    
    if helm rollback "$RELEASE_NAME" "$previous_revision" -n "$NAMESPACE" --wait --timeout 300s; then
        log "Helm rollback completed"
        
        # Verify rollback success
        if check_health; then
            log "Rollback health checks passed"
            log "🔄 Rollback completed successfully"
            
            # Log rollback event
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ROLLBACK: $RELEASE_NAME in $NAMESPACE - Reason: $reason" >> "$LOG_FILE"
            return 0
        else
            error "Rollback health checks failed"
            return 1
        fi
    else
        error "Helm rollback failed"
        return 1
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    error "Deployment failed with exit code: $exit_code"
    
    # Attempt automatic rollback on failure
    if [[ "$DRY_RUN" == "false" ]]; then
        rollback "Deployment script encountered an error"
    fi
    
    exit $exit_code
}

# Set up error handling
trap handle_error ERR

# Main execution
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "=== Shepherd Deployment Script Started ==="
    log "Command: $0 $*"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Run pre-flight checks
    preflight_checks
    
    # Execute deployment
    if deploy; then
        log "=== Deployment Script Completed Successfully ==="
        exit 0
    else
        error "=== Deployment Script Failed ==="
        exit 1
    fi
}

# Run main function with all arguments
main "$@"