#!/bin/bash
# Helper script to initialize MongoDB replica set using localhost exception
# This script executes initialization commands inside the primary container

set -euo pipefail

# Configuration
COMPOSE_PROJECT_NAME="shepherd"
PRIMARY_CONTAINER="mongo-primary"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Check if Docker Compose is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    error "Docker Compose is not available"
    exit 1
fi

# Check if primary container is running
if ! docker compose ps --services --filter "status=running" | grep -q "$PRIMARY_CONTAINER"; then
    error "Primary container '$PRIMARY_CONTAINER' is not running"
    log "Please start the services first: docker compose up -d"
    exit 1
fi

log "Starting MongoDB replica set initialization..."

# Step 1: Wait for primary to be ready
log "Waiting for primary MongoDB to be ready..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" bash -c "
    timeout 60 bash -c 'until mongosh --eval \"db.runCommand('ping').ok\" --quiet; do sleep 2; done'
"; then
    error "Primary MongoDB failed to become ready"
    exit 1
fi

# Step 2: Initialize replica set using localhost interface
log "Initializing replica set..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" mongosh --eval "
rs.initiate({
  _id: 'shepherd-rs',
  version: 1,
  members: [
    { _id: 0, host: 'mongo-primary:27017', priority: 2, votes: 1 },
    { _id: 1, host: 'mongo-secondary-1:27017', priority: 1, votes: 1 },
    { _id: 2, host: 'mongo-secondary-2:27017', priority: 1, votes: 1 }
  ]
})
" --quiet; then
    error "Failed to initialize replica set"
    exit 1
fi

# Step 3: Wait for primary election
log "Waiting for primary election..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" bash -c "
    timeout 60 bash -c 'until mongosh --eval \"rs.status().myState\" --quiet | grep -q \"1\"; do sleep 2; done'
"; then
    error "Primary election failed"
    exit 1
fi

# Step 4: Create admin user using localhost exception
log "Creating admin user..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" mongosh --eval "
use admin
db.createUser({
  user: 'admin',
  pwd: 'admin_password123',
  roles: [{ role: 'root', db: 'admin' }]
})
" --quiet; then
    error "Failed to create admin user"
    exit 1
fi

# Step 5: Create application user with authentication
log "Creating application user..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" mongosh --username admin --password admin_password123 --authenticationDatabase admin --eval "
use shepherd
db.createUser({
  user: 'shepherd_user',
  pwd: 'shepherd_password123',
  roles: [{ role: 'readWrite', db: 'shepherd' }]
})
" --quiet; then
    error "Failed to create application user"
    exit 1
fi

# Step 6: Run initial data setup if script exists
if docker compose exec -T "$PRIMARY_CONTAINER" test -f /scripts/init-mongo.js; then
    log "Running initial data setup..."
    if ! docker compose exec -T "$PRIMARY_CONTAINER" mongosh --username admin --password admin_password123 --authenticationDatabase admin /scripts/init-mongo.js --quiet; then
        error "Failed to run initial data setup"
        exit 1
    fi
else
    log "No initial data script found, skipping..."
fi

# Step 7: Verify replica set status
log "Verifying replica set status..."
if ! docker compose exec -T "$PRIMARY_CONTAINER" mongosh --username admin --password admin_password123 --authenticationDatabase admin --eval "
var status = rs.status()
print('Replica Set: ' + status.set)
print('Primary: ' + status.members.find(m => m.stateStr === 'PRIMARY').name)
print('Secondaries: ' + status.members.filter(m => m.stateStr === 'SECONDARY').map(m => m.name).join(', '))
status.members.forEach(function(member) {
  print('  ' + member.name + ': ' + member.stateStr + ' (health: ' + member.health + ')')
})
" --quiet; then
    error "Failed to verify replica set status"
    exit 1
fi

log "MongoDB replica set initialization completed successfully!"
log ""
log "Connection string:"
log "mongodb://shepherd_user:shepherd_password123@mongo-primary:27017,mongo-secondary-1:27018,mongo-secondary-2:27019/shepherd?authSource=shepherd&replicaSet=shepherd-rs&readPreference=secondaryPreferred"
log ""
log "You can now start the application: docker compose up -d shepherd-app"

exit 0