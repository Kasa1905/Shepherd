#!/bin/bash

# Disaster Recovery Testing Script for Shepherd CMS
# This script automates disaster recovery testing across different deployment environments

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/shepherd-dr-test-$(date +%Y%m%d-%H%M%S).log"
RESULTS_FILE="/tmp/shepherd-dr-results-$(date +%Y%m%d-%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=300  # 5 minutes
RTO_TARGET=3600   # 60 minutes in seconds
RPO_TARGET=900    # 15 minutes in seconds

# Initialize results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=""

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
    esac
}

# Result tracking function
record_test_result() {
    local test_name="$1"
    local status="$2"
    local duration="$3"
    local details="$4"
    
    if [ "$status" = "PASS" ]; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
    
    TEST_RESULTS="$TEST_RESULTS
    {
        \"test_name\": \"$test_name\",
        \"status\": \"$status\",
        \"duration_seconds\": $duration,
        \"details\": \"$details\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    },"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for service to be ready
wait_for_service() {
    local url="$1"
    local timeout="$2"
    local interval=5
    local elapsed=0
    
    log "INFO" "Waiting for service at $url to become ready..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            log "SUCCESS" "Service is ready at $url"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log "INFO" "Waiting... (${elapsed}/${timeout}s)"
    done
    
    log "ERROR" "Service at $url did not become ready within ${timeout}s"
    return 1
}

# Test database connectivity
test_database_connectivity() {
    local test_name="Database Connectivity"
    local start_time=$(date +%s)
    
    log "INFO" "Testing database connectivity..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            if docker exec mongo-primary mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "PASS" "$duration" "MongoDB accessible via Docker"
                log "SUCCESS" "Database connectivity test passed"
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Cannot connect to MongoDB"
                log "ERROR" "Database connectivity test failed"
            fi
            ;;
        "kubernetes")
            if kubectl exec mongodb-0 -- mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "PASS" "$duration" "MongoDB accessible via Kubernetes"
                log "SUCCESS" "Database connectivity test passed"
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Cannot connect to MongoDB"
                log "ERROR" "Database connectivity test failed"
            fi
            ;;
        "aws")
            # For AWS, we would test DocumentDB connectivity
            # This would require proper connection string and credentials
            log "INFO" "AWS DocumentDB connectivity test requires manual verification"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification required for AWS DocumentDB"
            ;;
    esac
}

# Test replica set status
test_replica_set_status() {
    local test_name="Replica Set Status"
    local start_time=$(date +%s)
    
    log "INFO" "Testing replica set status..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            local rs_status=$(docker exec mongo-primary mongosh --quiet --eval "JSON.stringify(rs.status())" 2>/dev/null || echo "{}")
            
            if echo "$rs_status" | jq -e '.set' >/dev/null 2>&1; then
                local primary_count=$(echo "$rs_status" | jq '[.members[] | select(.stateStr == "PRIMARY")] | length')
                local secondary_count=$(echo "$rs_status" | jq '[.members[] | select(.stateStr == "SECONDARY")] | length')
                
                if [ "$primary_count" -eq 1 ] && [ "$secondary_count" -ge 1 ]; then
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "PASS" "$duration" "Replica set healthy: 1 primary, $secondary_count secondaries"
                    log "SUCCESS" "Replica set status test passed"
                else
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "FAIL" "$duration" "Unhealthy replica set: $primary_count primary, $secondary_count secondaries"
                    log "ERROR" "Replica set status test failed"
                fi
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Cannot get replica set status"
                log "ERROR" "Replica set status test failed"
            fi
            ;;
        "kubernetes")
            local rs_status=$(kubectl exec mongodb-0 -- mongosh --quiet --eval "JSON.stringify(rs.status())" 2>/dev/null || echo "{}")
            
            if echo "$rs_status" | jq -e '.set' >/dev/null 2>&1; then
                local primary_count=$(echo "$rs_status" | jq '[.members[] | select(.stateStr == "PRIMARY")] | length')
                local secondary_count=$(echo "$rs_status" | jq '[.members[] | select(.stateStr == "SECONDARY")] | length')
                
                if [ "$primary_count" -eq 1 ] && [ "$secondary_count" -ge 1 ]; then
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "PASS" "$duration" "Replica set healthy: 1 primary, $secondary_count secondaries"
                    log "SUCCESS" "Replica set status test passed"
                else
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "FAIL" "$duration" "Unhealthy replica set: $primary_count primary, $secondary_count secondaries"
                    log "ERROR" "Replica set status test failed"
                fi
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Cannot get replica set status"
                log "ERROR" "Replica set status test failed"
            fi
            ;;
        "aws")
            log "INFO" "AWS DocumentDB replica status requires manual verification"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification required for AWS DocumentDB"
            ;;
    esac
}

# Test application health
test_application_health() {
    local test_name="Application Health"
    local start_time=$(date +%s)
    
    log "INFO" "Testing application health..."
    
    local health_url=""
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            health_url="http://localhost:5000/health"
            ;;
        "kubernetes")
            # Port forward to access the service
            kubectl port-forward service/shepherd-app 8080:5000 &
            local port_forward_pid=$!
            sleep 5
            health_url="http://localhost:8080/health"
            ;;
        "aws")
            # Would use load balancer URL
            log "INFO" "AWS health check requires load balancer URL"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification required for AWS deployment"
            return
            ;;
    esac
    
    if wait_for_service "$health_url" 60; then
        local health_response=$(curl -s "$health_url" 2>/dev/null || echo "{}")
        
        if echo "$health_response" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "PASS" "$duration" "Application health check passed"
            log "SUCCESS" "Application health test passed"
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "FAIL" "$duration" "Application health check failed: $health_response"
            log "ERROR" "Application health test failed"
        fi
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        record_test_result "$test_name" "FAIL" "$duration" "Application not accessible"
        log "ERROR" "Application health test failed"
    fi
    
    # Cleanup port forward if used
    if [ "$DEPLOYMENT_TYPE" = "kubernetes" ] && [ -n "${port_forward_pid:-}" ]; then
        kill $port_forward_pid >/dev/null 2>&1 || true
    fi
}

# Test primary node failover simulation
test_primary_failover() {
    local test_name="Primary Node Failover"
    local start_time=$(date +%s)
    
    log "INFO" "Testing primary node failover..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            # Get current primary
            local current_primary=$(docker exec mongo-primary mongosh --quiet --eval "JSON.stringify(rs.status())" | jq -r '.members[] | select(.stateStr == "PRIMARY") | .name' 2>/dev/null || echo "")
            
            if [ -z "$current_primary" ]; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Cannot identify current primary"
                log "ERROR" "Primary failover test failed: Cannot identify current primary"
                return
            fi
            
            log "INFO" "Current primary: $current_primary"
            
            # Stop primary container
            log "INFO" "Stopping primary container..."
            docker stop mongo-primary >/dev/null 2>&1
            
            # Wait for election
            log "INFO" "Waiting for new primary election..."
            sleep 30
            
            # Check if new primary elected
            local new_primary=$(docker exec mongo-secondary-1 mongosh --quiet --eval "JSON.stringify(rs.status())" | jq -r '.members[] | select(.stateStr == "PRIMARY") | .name' 2>/dev/null || echo "")
            
            if [ -n "$new_primary" ] && [ "$new_primary" != "$current_primary" ]; then
                log "SUCCESS" "New primary elected: $new_primary"
                
                # Restart original primary
                docker start mongo-primary >/dev/null 2>&1
                sleep 10
                
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "PASS" "$duration" "Failover successful: $current_primary -> $new_primary"
                log "SUCCESS" "Primary failover test passed"
            else
                # Restart original primary
                docker start mongo-primary >/dev/null 2>&1
                
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "No new primary elected"
                log "ERROR" "Primary failover test failed"
            fi
            ;;
        "kubernetes")
            # Similar logic for Kubernetes
            log "INFO" "Kubernetes failover test requires careful pod management"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification recommended for Kubernetes"
            ;;
        "aws")
            log "INFO" "AWS DocumentDB handles failover automatically"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Automatic failover in AWS DocumentDB"
            ;;
    esac
}

# Test backup and restore
test_backup_restore() {
    local test_name="Backup and Restore"
    local start_time=$(date +%s)
    
    log "INFO" "Testing backup and restore functionality..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            # Create test data
            local test_doc='{"test_id":"dr_test_'$(date +%s)'","test_data":"disaster recovery test"}'
            
            docker exec mongo-primary mongosh shepherd_cms --quiet --eval "
                db.dr_test.insertOne($test_doc);
                print('Test document inserted');
            " >/dev/null 2>&1
            
            # Create backup
            local backup_name="dr_test_$(date +%Y%m%d_%H%M%S)"
            log "INFO" "Creating backup: $backup_name"
            
            docker exec mongo-primary mongodump \
                --host mongo-primary:27017 \
                --db shepherd_cms \
                --collection dr_test \
                --out "/backup/$backup_name" >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                # Drop collection
                docker exec mongo-primary mongosh shepherd_cms --quiet --eval "db.dr_test.drop()" >/dev/null 2>&1
                
                # Restore from backup
                log "INFO" "Restoring from backup..."
                docker exec mongo-primary mongorestore \
                    --host mongo-primary:27017 \
                    --db shepherd_cms \
                    "/backup/$backup_name/shepherd_cms/" >/dev/null 2>&1
                
                # Verify restored data
                local restored_count=$(docker exec mongo-primary mongosh shepherd_cms --quiet --eval "db.dr_test.countDocuments()" 2>/dev/null || echo "0")
                
                if [ "$restored_count" -gt 0 ]; then
                    # Cleanup
                    docker exec mongo-primary mongosh shepherd_cms --quiet --eval "db.dr_test.drop()" >/dev/null 2>&1
                    docker exec mongo-primary rm -rf "/backup/$backup_name" >/dev/null 2>&1
                    
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "PASS" "$duration" "Backup and restore successful"
                    log "SUCCESS" "Backup and restore test passed"
                else
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    record_test_result "$test_name" "FAIL" "$duration" "Data not restored correctly"
                    log "ERROR" "Backup and restore test failed"
                fi
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                record_test_result "$test_name" "FAIL" "$duration" "Backup creation failed"
                log "ERROR" "Backup and restore test failed"
            fi
            ;;
        "kubernetes")
            log "INFO" "Kubernetes backup test requires CronJob verification"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification recommended"
            ;;
        "aws")
            log "INFO" "AWS backup test requires snapshot verification"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "SKIP" "$duration" "Manual verification recommended"
            ;;
    esac
}

# Generate results report
generate_report() {
    log "INFO" "Generating test results report..."
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    local success_rate=0
    
    if [ $total_tests -gt 0 ]; then
        success_rate=$(( (TESTS_PASSED * 100) / total_tests ))
    fi
    
    # Remove trailing comma from TEST_RESULTS
    TEST_RESULTS=$(echo "$TEST_RESULTS" | sed 's/,$//')
    
    cat > "$RESULTS_FILE" << EOF
{
    "test_summary": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "deployment_type": "$DEPLOYMENT_TYPE",
        "total_tests": $total_tests,
        "tests_passed": $TESTS_PASSED,
        "tests_failed": $TESTS_FAILED,
        "success_rate_percent": $success_rate,
        "rto_target_seconds": $RTO_TARGET,
        "rpo_target_seconds": $RPO_TARGET
    },
    "test_results": [$TEST_RESULTS
    ]
}
EOF
    
    log "SUCCESS" "Test results saved to: $RESULTS_FILE"
    
    # Display summary
    echo -e "\n${BLUE}=== DISASTER RECOVERY TEST SUMMARY ===${NC}"
    echo -e "Deployment Type: ${YELLOW}$DEPLOYMENT_TYPE${NC}"
    echo -e "Total Tests: ${BLUE}$total_tests${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Success Rate: ${YELLOW}${success_rate}%${NC}"
    echo -e "Log File: ${BLUE}$LOG_FILE${NC}"
    echo -e "Results File: ${BLUE}$RESULTS_FILE${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "\n${RED}WARNING: Some tests failed. Please review the logs.${NC}"
        return 1
    else
        echo -e "\n${GREEN}All tests passed successfully!${NC}"
        return 0
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Shepherd CMS - Disaster Recovery Testing${NC}"
    echo -e "========================================"
    
    # Determine deployment type
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ] && command_exists docker-compose; then
        DEPLOYMENT_TYPE="docker-compose"
    elif command_exists kubectl && kubectl get nodes >/dev/null 2>&1; then
        DEPLOYMENT_TYPE="kubernetes"
    elif command_exists aws && [ -n "${AWS_DEFAULT_REGION:-}" ]; then
        DEPLOYMENT_TYPE="aws"
    else
        log "ERROR" "Cannot determine deployment type or required tools not available"
        exit 1
    fi
    
    log "INFO" "Detected deployment type: $DEPLOYMENT_TYPE"
    log "INFO" "Starting disaster recovery tests..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check prerequisites
    case "$DEPLOYMENT_TYPE" in
        "docker-compose")
            if ! command_exists docker || ! command_exists docker-compose; then
                log "ERROR" "Docker and docker-compose are required"
                exit 1
            fi
            ;;
        "kubernetes")
            if ! command_exists kubectl; then
                log "ERROR" "kubectl is required"
                exit 1
            fi
            ;;
        "aws")
            if ! command_exists aws; then
                log "ERROR" "AWS CLI is required"
                exit 1
            fi
            ;;
    esac
    
    # Check for jq (required for JSON parsing)
    if ! command_exists jq; then
        log "ERROR" "jq is required for JSON processing"
        exit 1
    fi
    
    # Run tests
    test_database_connectivity
    test_replica_set_status
    test_application_health
    test_primary_failover
    test_backup_restore
    
    # Generate report
    generate_report
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --rto-target)
            RTO_TARGET="$2"
            shift 2
            ;;
        --rpo-target)
            RPO_TARGET="$2"
            shift 2
            ;;
        --deployment-type)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --timeout SECONDS        Test timeout (default: 300)"
            echo "  --rto-target SECONDS     RTO target in seconds (default: 3600)"
            echo "  --rpo-target SECONDS     RPO target in seconds (default: 900)"
            echo "  --deployment-type TYPE   Force deployment type (docker-compose|kubernetes|aws)"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"