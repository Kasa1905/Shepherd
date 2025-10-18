#!/bin/bash
# Backup Verification Script for Shepherd Configuration Management System
# This script verifies the integrity and completeness of database backups across environments

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${SCRIPT_DIR}/backup-verify.log"
CONFIG_FILE="${SCRIPT_DIR}/backup-verify.conf"

# Default configuration
DEFAULT_BACKUP_DIR="/opt/shepherd/backups"
DEFAULT_RETENTION_DAYS=30
DEFAULT_ENVIRONMENTS="docker-compose,kubernetes,aws"
DEFAULT_MONGODB_HOST="localhost:27017"
DEFAULT_DATABASE_NAME="shepherd_cms"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Help function
show_help() {
    cat << EOF
Backup Verification Script for Shepherd CMS

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    verify          Verify all backups (default)
    verify-latest   Verify only the latest backup
    verify-aws      Verify AWS DocumentDB backups
    verify-docker   Verify Docker Compose backups
    verify-k8s      Verify Kubernetes backups
    cleanup         Remove old backups based on retention policy
    test-restore    Test backup restore functionality
    report          Generate backup status report

OPTIONS:
    -e, --environment ENV       Environment to verify (docker-compose,kubernetes,aws)
    -d, --backup-dir DIR        Backup directory path
    -h, --host HOST             MongoDB host:port
    -db, --database NAME        Database name
    -r, --retention DAYS        Retention period in days
    -v, --verbose               Verbose output
    -q, --quiet                 Quiet mode (errors only)
    --config FILE               Configuration file path
    --help                      Show this help message

EXAMPLES:
    $0 verify                                    # Verify all backups
    $0 verify-aws                               # Verify AWS backups only
    $0 verify -e docker-compose -v             # Verify Docker backups with verbose output
    $0 cleanup -r 30                           # Clean up backups older than 30 days
    $0 test-restore --backup-dir /opt/backups  # Test restore from specific directory

EOF
}

# Load configuration file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_info "No configuration file found, using defaults"
    fi
    
    # Set defaults if not provided
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
    ENVIRONMENTS="${ENVIRONMENTS:-$DEFAULT_ENVIRONMENTS}"
    MONGODB_HOST="${MONGODB_HOST:-$DEFAULT_MONGODB_HOST}"
    DATABASE_NAME="${DATABASE_NAME:-$DEFAULT_DATABASE_NAME}"
}

# Check dependencies
check_dependencies() {
    local deps=("mongosh" "mongodump" "mongorestore" "aws" "kubectl" "docker")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies (may be required for specific environments): ${missing[*]}"
    fi
}

# Verify Docker Compose backups
verify_docker_backups() {
    log_info "Verifying Docker Compose backups..."
    
    local backup_count=0
    local valid_count=0
    
    # Check if Docker containers are running
    if ! docker ps --filter "name=mongo-primary" --format "table {{.Names}}" | grep -q mongo-primary; then
        log_warn "MongoDB containers not running, skipping Docker backup verification"
        return 0
    fi
    
    # Find backup files
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    for backup_file in "$BACKUP_DIR"/shepherd_backup_*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            ((backup_count++))
            log_info "Verifying backup: $(basename "$backup_file")"
            
            # Extract and verify backup
            local temp_dir=$(mktemp -d)
            local backup_name=$(basename "$backup_file" .tar.gz)
            
            if tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
                if [[ -d "$temp_dir/$backup_name/shepherd_cms" ]]; then
                    # Check backup integrity
                    local bson_files=$(find "$temp_dir/$backup_name/shepherd_cms" -name "*.bson" | wc -l)
                    local metadata_files=$(find "$temp_dir/$backup_name/shepherd_cms" -name "*.metadata.json" | wc -l)
                    
                    if [[ $bson_files -gt 0 && $metadata_files -gt 0 ]]; then
                        log_success "✓ Backup valid: $bson_files collections, $metadata_files metadata files"
                        ((valid_count++))
                    else
                        log_error "✗ Backup incomplete: missing BSON or metadata files"
                    fi
                else
                    log_error "✗ Backup structure invalid: missing database directory"
                fi
            else
                log_error "✗ Failed to extract backup archive"
            fi
            
            rm -rf "$temp_dir"
        fi
    done
    
    log_info "Docker backup summary: $valid_count/$backup_count backups valid"
    return 0
}

# Verify AWS DocumentDB backups
verify_aws_backups() {
    log_info "Verifying AWS DocumentDB backups..."
    
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not available, skipping AWS backup verification"
        return 0
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_warn "AWS credentials not configured, skipping AWS backup verification"
        return 0
    fi
    
    # Get backup jobs
    local backup_jobs=$(aws backup list-backup-jobs \
        --by-resource-type DocumentDB \
        --query 'BackupJobs[?State==`COMPLETED`]' \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "$backup_jobs" == "[]" ]]; then
        log_warn "No completed DocumentDB backup jobs found"
        return 0
    fi
    
    local backup_count=$(echo "$backup_jobs" | jq '. | length')
    log_info "Found $backup_count completed backup jobs"
    
    # Verify each backup
    local valid_count=0
    while IFS= read -r backup_job; do
        local backup_id=$(echo "$backup_job" | jq -r '.BackupJobId')
        local creation_date=$(echo "$backup_job" | jq -r '.CreationDate')
        local size=$(echo "$backup_job" | jq -r '.BackupSizeInBytes')
        
        log_info "Verifying backup: $backup_id (Created: $creation_date, Size: $size bytes)"
        
        # Check backup details
        local backup_details=$(aws backup describe-backup-job --backup-job-id "$backup_id" 2>/dev/null || echo '{}')
        local state=$(echo "$backup_details" | jq -r '.State // "UNKNOWN"')
        
        if [[ "$state" == "COMPLETED" ]]; then
            log_success "✓ Backup job completed successfully"
            ((valid_count++))
        else
            log_error "✗ Backup job in unexpected state: $state"
        fi
        
    done < <(echo "$backup_jobs" | jq -c '.[]')
    
    log_info "AWS backup summary: $valid_count/$backup_count backups valid"
    return 0
}

# Verify Kubernetes backups
verify_k8s_backups() {
    log_info "Verifying Kubernetes backups..."
    
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not available, skipping Kubernetes backup verification"
        return 0
    fi
    
    # Check if we can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_warn "Cannot connect to Kubernetes cluster, skipping K8s backup verification"
        return 0
    fi
    
    # Check for backup CronJobs
    local cronjobs=$(kubectl get cronjobs -l app.kubernetes.io/name=shepherd,component=backup -o json 2>/dev/null || echo '{"items":[]}')
    local cronjob_count=$(echo "$cronjobs" | jq '.items | length')
    
    if [[ $cronjob_count -eq 0 ]]; then
        log_warn "No backup CronJobs found in cluster"
        return 0
    fi
    
    log_info "Found $cronjob_count backup CronJob(s)"
    
    # Check recent backup jobs
    local jobs=$(kubectl get jobs -l app.kubernetes.io/name=shepherd,component=backup \
        --sort-by=.metadata.creationTimestamp \
        -o json 2>/dev/null || echo '{"items":[]}')
    
    local recent_jobs=$(echo "$jobs" | jq '.items | map(select(.metadata.creationTimestamp > (now - 24*3600 | strftime("%Y-%m-%dT%H:%M:%SZ"))))')
    local recent_count=$(echo "$recent_jobs" | jq '. | length')
    
    log_info "Found $recent_count backup jobs in the last 24 hours"
    
    local success_count=0
    while IFS= read -r job; do
        local job_name=$(echo "$job" | jq -r '.metadata.name')
        local succeeded=$(echo "$job" | jq -r '.status.succeeded // 0')
        local failed=$(echo "$job" | jq -r '.status.failed // 0')
        
        if [[ $succeeded -gt 0 ]]; then
            log_success "✓ Backup job succeeded: $job_name"
            ((success_count++))
        elif [[ $failed -gt 0 ]]; then
            log_error "✗ Backup job failed: $job_name"
        else
            log_warn "⚠ Backup job still running: $job_name"
        fi
    done < <(echo "$recent_jobs" | jq -c '.[]')
    
    log_info "Kubernetes backup summary: $success_count/$recent_count jobs successful"
    return 0
}

# Test backup restore functionality
test_restore() {
    log_info "Testing backup restore functionality..."
    
    local latest_backup=""
    local restore_success=false
    
    # Find latest backup for Docker environment
    if [[ -d "$BACKUP_DIR" ]]; then
        latest_backup=$(ls -t "$BACKUP_DIR"/shepherd_backup_*.tar.gz 2>/dev/null | head -n1)
    fi
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backup files found for restore test"
        return 1
    fi
    
    log_info "Testing restore with backup: $(basename "$latest_backup")"
    
    # Create temporary test database
    local test_db="shepherd_restore_test_$(date +%s)"
    local temp_dir=$(mktemp -d)
    local backup_name=$(basename "$latest_backup" .tar.gz)
    
    # Extract backup
    if tar -xzf "$latest_backup" -C "$temp_dir"; then
        log_info "Backup extracted successfully"
        
        # Perform test restore
        if mongorestore --host "$MONGODB_HOST" --db "$test_db" "$temp_dir/$backup_name/shepherd_cms" &> /dev/null; then
            log_success "✓ Restore test successful"
            restore_success=true
            
            # Verify restored data
            local collection_count=$(mongosh --host "$MONGODB_HOST" --eval "use $test_db; db.getCollectionNames().length" --quiet 2>/dev/null || echo "0")
            log_info "Restored $collection_count collections"
            
            # Cleanup test database
            mongosh --host "$MONGODB_HOST" --eval "use $test_db; db.dropDatabase()" --quiet &> /dev/null || true
        else
            log_error "✗ Restore test failed"
        fi
    else
        log_error "Failed to extract backup for restore test"
    fi
    
    rm -rf "$temp_dir"
    
    if [[ "$restore_success" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Clean up old backups
cleanup_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local deleted_count=0
    
    if [[ -d "$BACKUP_DIR" ]]; then
        # Find and delete old backup files
        while IFS= read -r -d '' backup_file; do
            log_info "Deleting old backup: $(basename "$backup_file")"
            rm -f "$backup_file"
            ((deleted_count++))
        done < <(find "$BACKUP_DIR" -name "shepherd_backup_*.tar.gz" -mtime +$RETENTION_DAYS -print0 2>/dev/null)
    fi
    
    log_info "Deleted $deleted_count old backup files"
    return 0
}

# Generate backup status report
generate_report() {
    log_info "Generating backup status report..."
    
    local report_file="${SCRIPT_DIR}/backup-status-$(date +%Y%m%d).txt"
    
    {
        echo "# Shepherd CMS Backup Status Report"
        echo "Generated: $(date)"
        echo ""
        
        echo "## Configuration"
        echo "Backup Directory: $BACKUP_DIR"
        echo "Retention Period: $RETENTION_DAYS days"
        echo "MongoDB Host: $MONGODB_HOST"
        echo "Database: $DATABASE_NAME"
        echo ""
        
        echo "## Environment Status"
        
        # Docker backups
        if [[ -d "$BACKUP_DIR" ]]; then
            local docker_count=$(ls "$BACKUP_DIR"/shepherd_backup_*.tar.gz 2>/dev/null | wc -l)
            echo "Docker Compose Backups: $docker_count files"
            
            if [[ $docker_count -gt 0 ]]; then
                local latest_docker=$(ls -t "$BACKUP_DIR"/shepherd_backup_*.tar.gz 2>/dev/null | head -n1)
                echo "Latest Docker Backup: $(basename "$latest_docker")"
                echo "Size: $(du -h "$latest_docker" 2>/dev/null | cut -f1)"
            fi
        else
            echo "Docker Compose Backups: Directory not found"
        fi
        
        # AWS backups
        if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
            local aws_count=$(aws backup list-backup-jobs --by-resource-type DocumentDB --query 'BackupJobs[?State==`COMPLETED`] | length(@)' --output text 2>/dev/null || echo "0")
            echo "AWS DocumentDB Backups: $aws_count completed jobs"
        else
            echo "AWS DocumentDB Backups: AWS CLI not configured"
        fi
        
        # Kubernetes backups
        if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
            local k8s_jobs=$(kubectl get jobs -l app.kubernetes.io/name=shepherd,component=backup --no-headers 2>/dev/null | wc -l)
            echo "Kubernetes Backup Jobs: $k8s_jobs total"
        else
            echo "Kubernetes Backup Jobs: kubectl not configured"
        fi
        
        echo ""
        echo "## Recommendations"
        
        if [[ $docker_count -lt 7 ]]; then
            echo "- Consider increasing backup frequency for Docker environment"
        fi
        
        echo "- Regularly test backup restore procedures"
        echo "- Monitor backup job success rates"
        echo "- Verify cross-region replication for AWS deployments"
        
    } > "$report_file"
    
    log_success "Report generated: $report_file"
    cat "$report_file"
}

# Main verification function
verify_all() {
    log_info "Starting comprehensive backup verification..."
    
    local errors=0
    
    if [[ "$ENVIRONMENTS" == *"docker-compose"* ]]; then
        verify_docker_backups || ((errors++))
    fi
    
    if [[ "$ENVIRONMENTS" == *"aws"* ]]; then
        verify_aws_backups || ((errors++))
    fi
    
    if [[ "$ENVIRONMENTS" == *"kubernetes"* ]]; then
        verify_k8s_backups || ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All backup verifications completed successfully"
        return 0
    else
        log_error "$errors verification(s) failed"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENTS="$2"
                shift 2
                ;;
            -d|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -h|--host)
                MONGODB_HOST="$2"
                shift 2
                ;;
            -db|--database)
                DATABASE_NAME="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -q|--quiet)
                exec > /dev/null 2>&1
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            verify)
                COMMAND="verify"
                shift
                ;;
            verify-latest)
                COMMAND="verify-latest"
                shift
                ;;
            verify-aws)
                COMMAND="verify-aws"
                ENVIRONMENTS="aws"
                shift
                ;;
            verify-docker)
                COMMAND="verify-docker"
                ENVIRONMENTS="docker-compose"
                shift
                ;;
            verify-k8s)
                COMMAND="verify-k8s"
                ENVIRONMENTS="kubernetes"
                shift
                ;;
            cleanup)
                COMMAND="cleanup"
                shift
                ;;
            test-restore)
                COMMAND="test-restore"
                shift
                ;;
            report)
                COMMAND="report"
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    local COMMAND="${COMMAND:-verify}"
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "Starting backup verification script (PID: $$)"
    
    # Load configuration
    load_config
    
    # Check dependencies
    check_dependencies
    
    # Execute command
    case "$COMMAND" in
        verify|verify-latest)
            verify_all
            ;;
        verify-aws)
            verify_aws_backups
            ;;
        verify-docker)
            verify_docker_backups
            ;;
        verify-k8s)
            verify_k8s_backups
            ;;
        cleanup)
            cleanup_backups
            ;;
        test-restore)
            test_restore
            ;;
        report)
            generate_report
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Parse arguments and run main function
parse_args "$@"
main