#!/bin/bash
# MongoDB Replica Set Initialization Script for Shepherd CMS
# Supports both localhost (inside primary container) and remote execution
# When run inside primary container, leverages localhost exception for auth

set -euo pipefail

# Configuration
REPLICA_SET_NAME="shepherd-rs"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin_password123"
APP_USER="shepherd_user"
APP_PASSWORD="shepherd_password123"
DATABASE_NAME="shepherd"

# Detect execution context
if [ "${HOSTNAME:-}" = "mongo-primary" ] || [ "${MONGODB_LOCALHOST:-false}" = "true" ]; then
    # Running inside primary container - use localhost
    EXECUTION_MODE="localhost"
    PRIMARY_HOST="localhost:27017"
    SECONDARY1_HOST="mongo-secondary-1:27017"
    SECONDARY2_HOST="mongo-secondary-2:27017"
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOCALHOST] $1"
    }
else
    # Running remotely - use external hostnames
    EXECUTION_MODE="remote"
    PRIMARY_HOST="mongo-primary:27017"
    SECONDARY1_HOST="mongo-secondary-1:27017"
    SECONDARY2_HOST="mongo-secondary-2:27017"
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REMOTE] $1"
    }
fi

# Maximum wait time for services (in seconds)
MAX_WAIT_TIME=120
RETRY_INTERVAL=5

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

wait_for_mongo() {
    local host=$1
    local wait_time=0
    
    log "Waiting for MongoDB at $host to be ready..."
    
    while [ $wait_time -lt $MAX_WAIT_TIME ]; do
        if [ "$EXECUTION_MODE" = "localhost" ] && [ "$host" = "$PRIMARY_HOST" ]; then
            # For localhost connections, use simple ping without auth
            if mongosh --eval "db.runCommand('ping').ok" --quiet 2>/dev/null; then
                log "MongoDB at $host is ready"
                return 0
            fi
        else
            # For remote connections or secondary nodes
            if mongosh --host "$host" --eval "db.runCommand('ping').ok" --quiet 2>/dev/null; then
                log "MongoDB at $host is ready"
                return 0
            fi
        fi
        
        log "MongoDB at $host not ready, waiting... ($wait_time/$MAX_WAIT_TIME seconds)"
        sleep $RETRY_INTERVAL
        wait_time=$((wait_time + RETRY_INTERVAL))
    done
    
    error "MongoDB at $host failed to become ready within $MAX_WAIT_TIME seconds"
    return 1
}

wait_for_all_nodes() {
    log "Waiting for all MongoDB nodes to be ready..."
    
    # Always wait for primary first
    wait_for_mongo "$PRIMARY_HOST" || exit 1
    
    if [ "$EXECUTION_MODE" = "localhost" ]; then
        # When running from inside primary, we can't directly check secondaries
        # but we'll wait a bit for them to start
        log "Running in localhost mode, skipping direct secondary checks"
        sleep 10
    else
        # When running remotely, check all nodes
        wait_for_mongo "$SECONDARY1_HOST" || exit 1
        wait_for_mongo "$SECONDARY2_HOST" || exit 1
    fi
    
    log "All accessible MongoDB nodes are ready"
}

initialize_replica_set() {
    log "Initializing replica set: $REPLICA_SET_NAME"
    
    # Use external hostnames for replica set configuration (not localhost)
    local rs_config=$(cat <<EOF
{
  _id: "$REPLICA_SET_NAME",
  version: 1,
  members: [
    {
      _id: 0,
      host: "mongo-primary:27017",
      priority: 2,
      votes: 1
    },
    {
      _id: 1,
      host: "mongo-secondary-1:27017",
      priority: 1,
      votes: 1
    },
    {
      _id: 2,
      host: "mongo-secondary-2:27017",
      priority: 1,
      votes: 1
    }
  ]
}
EOF
)
    
    # Initialize replica set - use localhost interface when available
    if [ "$EXECUTION_MODE" = "localhost" ]; then
        if mongosh --eval "rs.initiate($rs_config)" --quiet; then
            log "Replica set initialization command sent successfully"
        else
            error "Failed to initialize replica set"
            exit 1
        fi
    else
        if mongosh --host "$PRIMARY_HOST" --eval "rs.initiate($rs_config)" --quiet; then
            log "Replica set initialization command sent successfully"
        else
            error "Failed to initialize replica set"
            exit 1
        fi
    fi
}

wait_for_replica_set() {
    log "Waiting for replica set to be ready..."
    local wait_time=0
    
    while [ $wait_time -lt $MAX_WAIT_TIME ]; do
        # Check if we have a primary
        if [ "$EXECUTION_MODE" = "localhost" ]; then
            if mongosh --eval "rs.status().myState" --quiet 2>/dev/null | grep -q "1"; then
                log "Primary node is ready"
                break
            fi
        else
            if mongosh --host "$PRIMARY_HOST" --eval "rs.status().myState" --quiet 2>/dev/null | grep -q "1"; then
                log "Primary node is ready"
                break
            fi
        fi
        
        log "Waiting for primary election... ($wait_time/$MAX_WAIT_TIME seconds)"
        sleep $RETRY_INTERVAL
        wait_time=$((wait_time + RETRY_INTERVAL))
    done
    
    if [ $wait_time -ge $MAX_WAIT_TIME ]; then
        error "Replica set failed to elect primary within $MAX_WAIT_TIME seconds"
        exit 1
    fi
    
    # Wait a bit more for secondaries to catch up
    log "Waiting for secondary nodes to join..."
    sleep 10
}

create_admin_user() {
    log "Creating admin user..."
    
    local create_admin_script=$(cat <<EOF
use admin
db.createUser({
  user: "$ADMIN_USER",
  pwd: "$ADMIN_PASSWORD",
  roles: [
    { role: "root", db: "admin" }
  ]
})
EOF
)
    
    # Use localhost exception when running inside primary container
    if [ "$EXECUTION_MODE" = "localhost" ]; then
        if mongosh --eval "$create_admin_script" --quiet; then
            log "Admin user created successfully"
        else
            error "Failed to create admin user"
            exit 1
        fi
    else
        if mongosh --host "$PRIMARY_HOST" --eval "$create_admin_script" --quiet; then
            log "Admin user created successfully"
        else
            error "Failed to create admin user"
            exit 1
        fi
    fi
}

create_app_user() {
    log "Creating application user..."
    
    local create_app_script=$(cat <<EOF
use admin
db.auth("$ADMIN_USER", "$ADMIN_PASSWORD")
use $DATABASE_NAME
db.createUser({
  user: "$APP_USER",
  pwd: "$APP_PASSWORD",
  roles: [
    { role: "readWrite", db: "$DATABASE_NAME" }
  ]
})
EOF
)
    
    # Always authenticate for app user creation (admin user now exists)
    if [ "$EXECUTION_MODE" = "localhost" ]; then
        if mongosh --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "$create_app_script" --quiet; then
            log "Application user created successfully"
        else
            error "Failed to create application user"
            exit 1
        fi
    else
        if mongosh --host "$PRIMARY_HOST" --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "$create_app_script" --quiet; then
            log "Application user created successfully"
        else
            error "Failed to create application user"
            exit 1
        fi
    fi
}

create_initial_data() {
    log "Running initial data setup script..."
    
    # Check if init-mongo.js exists and run it
    if [ -f /scripts/init-mongo.js ]; then
        # Run with authentication
        if [ "$EXECUTION_MODE" = "localhost" ]; then
            if mongosh --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin /scripts/init-mongo.js --quiet; then
                log "Initial data setup completed successfully"
            else
                error "Failed to run initial data setup"
                exit 1
            fi
        else
            if mongosh --host "$PRIMARY_HOST" --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin /scripts/init-mongo.js --quiet; then
                log "Initial data setup completed successfully"
            else
                error "Failed to run initial data setup"
                exit 1
            fi
        fi
    else
        log "No initial data script found, skipping..."
    fi
}

verify_replica_set() {
    log "Verifying replica set status..."
    
    local status_script=$(cat <<EOF
use admin
db.auth("$ADMIN_USER", "$ADMIN_PASSWORD")
var status = rs.status()
print("Replica Set: " + status.set)
print("Primary: " + status.members.find(m => m.stateStr === "PRIMARY").name)
print("Secondaries: " + status.members.filter(m => m.stateStr === "SECONDARY").map(m => m.name).join(", "))
print("Total members: " + status.members.length)
status.members.forEach(function(member) {
  print("  " + member.name + ": " + member.stateStr + " (health: " + member.health + ")")
})
EOF
)
    
    if [ "$EXECUTION_MODE" = "localhost" ]; then
        if mongosh --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "$status_script" --quiet; then
            log "Replica set verification completed"
        else
            error "Failed to verify replica set status"
            exit 1
        fi
    else
        if mongosh --host "$PRIMARY_HOST" --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "$status_script" --quiet; then
            log "Replica set verification completed"
        else
            error "Failed to verify replica set status"
            exit 1
        fi
    fi
}

main() {
    log "Starting MongoDB replica set initialization"
    log "Execution mode: $EXECUTION_MODE"
    log "Replica set name: $REPLICA_SET_NAME"
    log "Database name: $DATABASE_NAME"
    
    # Step 1: Wait for all nodes to be ready
    wait_for_all_nodes
    
    # Step 2: Initialize replica set
    initialize_replica_set
    
    # Step 3: Wait for replica set to be ready
    wait_for_replica_set
    
    # Step 4: Create admin user (uses localhost exception when in localhost mode)
    create_admin_user
    
    # Step 5: Create application user (uses authentication)
    create_app_user
    
    # Step 6: Run initial data setup
    create_initial_data
    
    # Step 7: Verify replica set
    verify_replica_set
    
    log "MongoDB replica set initialization completed successfully!"
    log "Connection string: mongodb://$APP_USER:$APP_PASSWORD@mongo-primary:27017,mongo-secondary-1:27018,mongo-secondary-2:27019/$DATABASE_NAME?authSource=$DATABASE_NAME&replicaSet=$REPLICA_SET_NAME"
    
    exit 0
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main