#!/bin/bash

# Shepherd Rollback Script
# Quickly revert failed deployments with validation
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Use workspace-relative log file for CI/CD compatibility
LOG_FILE="${LOG_FILE:-${PROJECT_ROOT}/shepherd-rollback.log}"

# Default values
DEFAULT_NAMESPACE="default"
DEFAULT_RELEASE_NAME="shepherd"
DEFAULT_TIMEOUT=300

# Script variables
NAMESPACE="$DEFAULT_NAMESPACE"
RELEASE_NAME="$DEFAULT_RELEASE_NAME"
TARGET_REVISION=""
REASON=""
FORCE_ROLLBACK=false
LIST_REVISIONS=false
TIMEOUT="$DEFAULT_TIMEOUT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback script for quickly reverting failed deployments

OPTIONS:
    -n, --namespace NAMESPACE     Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    -r, --release RELEASE         Helm release name (default: $DEFAULT_RELEASE_NAME)
    --revision REVISION           Target revision number to rollback to
    --reason REASON               Reason for rollback (for logging)
    --force                       Force rollback without confirmation
    --list                        List available revisions and exit
    --timeout SECONDS             Rollback timeout (default: $DEFAULT_TIMEOUT)
    -h, --help                    Show this help message

EXAMPLES:
    # Rollback to previous revision
    $0 --namespace production --release shepherd

    # Rollback to specific revision
    $0 --namespace production --revision 5 --reason "Database migration failed"

    # Force rollback without confirmation
    $0 --namespace production --force

    # List available revisions
    $0 --namespace production --list

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
            --revision)
                TARGET_REVISION="$2"
                shift 2
                ;;
            --reason)
                REASON="$2"
                shift 2
                ;;
            --force)
                FORCE_ROLLBACK=true
                shift
                ;;
            --list)
                LIST_REVISIONS=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
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

# Get deployment history
get_history() {
    log "Retrieving deployment history for $RELEASE_NAME..."
    
    if ! helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        error "Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    echo -e "\n${CYAN}Deployment History for $RELEASE_NAME:${NC}"
    echo "======================================="
    
    # Get history with details
    helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 10 -o table
    
    # Get current revision
    local current_revision
    current_revision=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision' 2>/dev/null || echo "unknown")
    
    echo -e "\n${GREEN}Current revision: $current_revision${NC}"
    
    # Identify last successful deployment
    local last_successful
    last_successful=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '[.[] | select(.status == "superseded" or .status == "deployed")] | sort_by(.revision | tonumber) | .[-2].revision // "none"' 2>/dev/null || echo "none")
    
    if [[ "$last_successful" != "none" ]]; then
        echo -e "${YELLOW}Last successful revision: $last_successful${NC}"
    fi
    
    echo ""
}

# Validate target revision
validate_revision() {
    local revision="$1"
    
    # Check if revision exists
    if ! helm history "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -e ".[] | select(.revision == \"$revision\")" >/dev/null 2>&1; then
        error "Revision $revision does not exist for release $RELEASE_NAME"
        return 1
    fi
    
    # Get current revision
    local current_revision
    current_revision=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision' 2>/dev/null || echo "0")
    
    # Check if trying to rollback to current revision
    if [[ "$revision" == "$current_revision" ]]; then
        error "Cannot rollback to current revision ($current_revision)"
        return 1
    fi
    
    # Get revision details
    local revision_info
    revision_info=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r ".[] | select(.revision == \"$revision\") | \"Status: \\(.status), Updated: \\(.updated)\"" 2>/dev/null || echo "unknown")
    
    # Warn if rolling back to very old revision
    local revisions_ago
    revisions_ago=$((current_revision - revision))
    
    if [[ "$revisions_ago" -gt 5 ]]; then
        warn "Rolling back $revisions_ago revisions (to revision $revision)"
        warn "This is a significant rollback. Please verify this is intended."
        info "Target revision info: $revision_info"
    fi
    
    log "Target revision $revision validated"
    return 0
}

# Pre-rollback checks
pre_rollback_checks() {
    log "Running pre-rollback checks..."
    
    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    # Check current deployment status
    log "Current deployment status:"
    kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd 2>/dev/null || warn "No shepherd deployments found"
    
    # Capture current pod logs for debugging
    log "Capturing current pod logs for debugging..."
    local log_dir="/tmp/shepherd-rollback-logs-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$log_dir"
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pods" ]]; then
        for pod in $pods; do
            log "Capturing logs for pod: $pod"
            kubectl logs "$pod" -n "$NAMESPACE" --tail=100 > "$log_dir/${pod}.log" 2>/dev/null || true
            kubectl logs "$pod" -n "$NAMESPACE" --previous --tail=100 > "$log_dir/${pod}-previous.log" 2>/dev/null || true
        done
        log "Pod logs saved to: $log_dir"
    fi
    
    # Take snapshot of current configuration
    log "Taking configuration snapshot..."
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" > "$log_dir/current-values.yaml" 2>/dev/null || true
    kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd -o yaml > "$log_dir/current-deployment.yaml" 2>/dev/null || true
    
    # Verify MongoDB accessibility
    log "Checking database connectivity..."
    local db_test_passed=true
    
    if [[ -n "$pods" ]]; then
        local test_pod
        test_pod=$(echo "$pods" | awk '{print $1}')
        
        if kubectl exec -n "$NAMESPACE" "$test_pod" -- timeout 10 curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
            log "✅ Database connectivity check passed"
        else
            warn "⚠️ Database connectivity check failed (this may be expected if pods are failing)"
            db_test_passed=false
        fi
    fi
    
    log "Pre-rollback checks completed"
}

# Execute rollback
execute_rollback() {
    local revision="$1"
    
    highlight "Executing rollback to revision $revision"
    
    # Display rollback plan
    log "Rollback plan:"
    info "  Release: $RELEASE_NAME"
    info "  Namespace: $NAMESPACE"
    info "  Target revision: $revision"
    info "  Timeout: ${TIMEOUT}s"
    if [[ -n "$REASON" ]]; then
        info "  Reason: $REASON"
    fi
    
    # Confirmation prompt (unless forced)
    if [[ "$FORCE_ROLLBACK" == "false" ]]; then
        echo -e "\n${YELLOW}⚠️  This will rollback the deployment to revision $revision${NC}"
        echo -n "Are you sure you want to proceed? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Rollback cancelled by user"
            exit 0
        fi
    fi
    
    # Execute Helm rollback
    log "Executing Helm rollback..."
    if helm rollback "$RELEASE_NAME" "$revision" -n "$NAMESPACE" --wait --timeout "${TIMEOUT}s"; then
        log "Helm rollback completed successfully"
        
        # Monitor rollback progress
        log "Monitoring rollback progress..."
        if kubectl rollout status deployment/shepherd -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
            log "Rollback deployment status: SUCCESS"
        else
            warn "Rollback deployment status check timed out or failed"
        fi
        
        # Wait for all pods to be ready
        log "Waiting for pods to be ready..."
        if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=shepherd -n "$NAMESPACE" --timeout=180s; then
            log "All pods are ready after rollback"
        else
            warn "Some pods may not be ready after rollback"
        fi
        
        # Verify no pods are in error state
        local error_pods
        error_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd --no-headers | grep -E "CrashLoopBackOff|Error|ImagePullBackOff" | wc -l)
        
        if [[ "$error_pods" -eq 0 ]]; then
            log "✅ No pods in error state"
        else
            warn "⚠️ $error_pods pods in error state after rollback"
        fi
        
        return 0
    else
        error "Helm rollback failed"
        return 1
    fi
}

# Post-rollback validation
post_rollback_validation() {
    log "Running post-rollback validation..."
    
    # Test health endpoints
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pods" ]]; then
        local test_pod
        test_pod=$(echo "$pods" | awk '{print $1}')
        
        # Test health endpoint
        log "Testing health endpoint..."
        if kubectl exec -n "$NAMESPACE" "$test_pod" -- curl -f -s http://localhost:5000/api/health >/dev/null 2>&1; then
            log "✅ Health endpoint test passed"
        else
            error "❌ Health endpoint test failed"
            return 1
        fi
        
        # Test basic API functionality
        log "Testing API functionality..."
        if kubectl exec -n "$NAMESPACE" "$test_pod" -- curl -f -s http://localhost:5000/api/health | grep -q "status"; then
            log "✅ API functionality test passed"
        else
            error "❌ API functionality test failed"
            return 1
        fi
        
        # Test metrics endpoint
        log "Testing metrics endpoint..."
        if kubectl exec -n "$NAMESPACE" "$test_pod" -- curl -f -s http://localhost:5000/metrics >/dev/null 2>&1; then
            log "✅ Metrics endpoint test passed"
        else
            warn "⚠️ Metrics endpoint test failed (non-critical)"
        fi
    else
        error "No pods found for validation"
        return 1
    fi
    
    # Verify replica count matches expected
    local current_replicas
    current_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local expected_replicas
    expected_replicas=$(kubectl get deployment shepherd -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$current_replicas" == "$expected_replicas" ]] && [[ "$current_replicas" -gt 0 ]]; then
        log "✅ Replica count validation passed ($current_replicas/$expected_replicas ready)"
    else
        warn "⚠️ Replica count mismatch: $current_replicas ready, $expected_replicas expected"
    fi
    
    # Monitor for errors for 60 seconds
    log "Monitoring for errors (60 seconds)..."
    local monitor_start
    monitor_start=$(date +%s)
    local errors_detected=false
    
    while [[ $(($(date +%s) - monitor_start)) -lt 60 ]]; do
        if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=shepherd | grep -E "CrashLoopBackOff|Error|ImagePullBackOff"; then
            error "Errors detected in pods during monitoring"
            errors_detected=true
            break
        fi
        sleep 5
    done
    
    if [[ "$errors_detected" == "false" ]]; then
        log "✅ No errors detected during monitoring period"
    else
        error "❌ Errors detected during monitoring period"
        return 1
    fi
    
    log "🎯 Post-rollback validation completed successfully"
    return 0
}

# Send notification
send_notification() {
    local status="$1"
    local revision="$2"
    local operator="${USER:-unknown}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Log rollback event
    local log_entry="[$timestamp] ROLLBACK: $RELEASE_NAME in $NAMESPACE"
    log_entry+=" - Status: $status"
    log_entry+=" - Target revision: $revision"
    log_entry+=" - Operator: $operator"
    if [[ -n "$REASON" ]]; then
        log_entry+=" - Reason: $REASON"
    fi
    
    echo "$log_entry" >> "$LOG_FILE"
    
    # Optional: Send webhook notification (implement if webhook URL is configured)
    # This is a placeholder for integration with monitoring/alerting systems
    log "Rollback event logged"
}

# Main execution
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "=== Shepherd Rollback Script Started ==="
    log "Command: $0 $*"
    
    # Parse command line arguments
    parse_args "$@"
    
    # List revisions and exit if requested
    if [[ "$LIST_REVISIONS" == "true" ]]; then
        get_history
        exit 0
    fi
    
    # Get and display deployment history
    get_history
    
    # Determine target revision if not specified
    if [[ -z "$TARGET_REVISION" ]]; then
        log "No revision specified, determining previous revision..."
        
        TARGET_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '[.[] | select(.status == "superseded" or .status == "deployed")] | sort_by(.revision | tonumber) | .[-2].revision // "1"' 2>/dev/null || echo "1")
        
        if [[ "$TARGET_REVISION" == "1" ]]; then
            local current_rev
            current_rev=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision' 2>/dev/null || echo "1")
            
            if [[ "$current_rev" == "1" ]]; then
                error "No previous revision available for rollback (only revision 1 exists)"
                exit 1
            else
                TARGET_REVISION=$((current_rev - 1))
            fi
        fi
        
        log "Selected target revision: $TARGET_REVISION"
    fi
    
    # Validate target revision
    if ! validate_revision "$TARGET_REVISION"; then
        exit 1
    fi
    
    # Run pre-rollback checks
    pre_rollback_checks
    
    # Execute rollback
    if execute_rollback "$TARGET_REVISION"; then
        # Run post-rollback validation
        if post_rollback_validation; then
            # Send success notification
            send_notification "SUCCESS" "$TARGET_REVISION"
            
            highlight "🎉 Rollback completed successfully!"
            info "Rolled back to revision: $TARGET_REVISION"
            if [[ -n "$REASON" ]]; then
                info "Reason: $REASON"
            fi
            
            log "=== Rollback Script Completed Successfully ==="
            exit 0
        else
            error "Post-rollback validation failed"
            
            # Attempt cascading rollback to even earlier version
            warn "Attempting cascading rollback to earlier version..."
            local earlier_revision=$((TARGET_REVISION - 1))
            
            if [[ "$earlier_revision" -gt 0 ]] && validate_revision "$earlier_revision" 2>/dev/null; then
                log "Attempting rollback to revision $earlier_revision"
                if execute_rollback "$earlier_revision" && post_rollback_validation; then
                    send_notification "CASCADED_SUCCESS" "$earlier_revision"
                    log "🔄 Cascading rollback to revision $earlier_revision completed"
                    exit 0
                fi
            fi
            
            send_notification "FAILED" "$TARGET_REVISION"
            error "=== Rollback Script Failed ==="
            exit 1
        fi
    else
        send_notification "FAILED" "$TARGET_REVISION"
        error "=== Rollback Execution Failed ==="
        exit 1
    fi
}

# Run main function with all arguments
main "$@"