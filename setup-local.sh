#!/bin/bash

# ==============================================================================
# Shepherd CMS - Local Development Setup Script (Mac/Linux)
# ==============================================================================
# This script helps you get Shepherd running on your local machine quickly.
# ==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Print banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║          🐑 Shepherd Configuration Management System           ║"
echo "║                   Local Development Setup                      ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

# Check for Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed!"
    print_info "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi
print_success "Docker found: $(docker --version)"

# Check for Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed!"
    print_info "Please install Docker Compose from: https://docs.docker.com/compose/install/"
    exit 1
fi
print_success "Docker Compose found"

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running!"
    print_info "Please start Docker Desktop and try again."
    exit 1
fi
print_success "Docker daemon is running"

echo ""
print_info "Prerequisites check complete!"
echo ""

# Setup environment file
if [ ! -f .env ]; then
    print_info "Creating .env file from template..."
    if [ -f .env.example ]; then
        cp .env.example .env
        print_success "Created .env file (you can customize it later)"
    else
        print_warning ".env.example not found, using defaults"
    fi
else
    print_info ".env file already exists"
fi

# Create logs directory
mkdir -p logs
print_success "Created logs directory"

# Ask user which mode to run
echo ""
echo "Choose deployment mode:"
echo "  1) Simple Local Development (recommended for beginners)"
echo "  2) Production-like (with replica set)"
echo ""
read -p "Enter choice [1-2] (default: 1): " mode
mode=${mode:-1}

COMPOSE_FILE="docker-compose.local.yml"
if [ "$mode" = "2" ]; then
    COMPOSE_FILE="docker-compose.yml"
    print_warning "Production mode requires additional setup steps"
fi

# Stop any existing containers
print_info "Stopping any existing Shepherd containers..."
docker-compose -f $COMPOSE_FILE down 2>/dev/null || true
docker-compose down 2>/dev/null || true
print_success "Cleanup complete"

echo ""
print_info "Building and starting Shepherd CMS..."
echo ""

# Build and start containers
if docker-compose -f $COMPOSE_FILE up -d --build; then
    print_success "Containers started successfully!"
else
    print_error "Failed to start containers"
    exit 1
fi

echo ""
print_info "Waiting for services to be healthy..."
sleep 5

# Wait for MongoDB
MAX_WAIT=30
COUNTER=0
until docker-compose -f $COMPOSE_FILE exec -T mongodb mongosh --quiet --eval "db.runCommand('ping').ok" shepherd &>/dev/null || [ $COUNTER -eq $MAX_WAIT ]; do
    printf "."
    sleep 1
    ((COUNTER++))
done
echo ""

if [ $COUNTER -eq $MAX_WAIT ]; then
    print_warning "MongoDB health check timed out, but may still be starting..."
else
    print_success "MongoDB is ready!"
fi

# Wait for app
sleep 3
COUNTER=0
until curl -sf http://localhost:5000/api/health &>/dev/null || [ $COUNTER -eq $MAX_WAIT ]; do
    printf "."
    sleep 1
    ((COUNTER++))
done
echo ""

if [ $COUNTER -eq $MAX_WAIT ]; then
    print_warning "Application health check timed out"
    print_info "Check logs with: docker-compose -f $COMPOSE_FILE logs app"
else
    print_success "Application is ready!"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    🎉 Setup Complete! 🎉                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_success "Shepherd CMS is now running!"
echo ""
echo "📌 Access Points:"
echo "   • Web UI:        http://localhost:5000"
echo "   • API:           http://localhost:5000/api"
echo "   • Health Check:  http://localhost:5000/api/health"
echo "   • Metrics:       http://localhost:5000/metrics"
echo ""
echo "🔐 Default Login:"
echo "   • Username: admin"
echo "   • Password: admin123"
echo "   ⚠️  Change these in production!"
echo ""
echo "📚 Useful Commands:"
echo "   • View logs:         docker-compose -f $COMPOSE_FILE logs -f"
echo "   • Stop services:     docker-compose -f $COMPOSE_FILE down"
echo "   • Restart services:  docker-compose -f $COMPOSE_FILE restart"
echo "   • View containers:   docker-compose -f $COMPOSE_FILE ps"
echo ""
print_info "Opening Shepherd in your browser..."
sleep 2

# Try to open browser (Mac/Linux compatible)
if command -v open &> /dev/null; then
    open http://localhost:5000
elif command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:5000
else
    print_info "Please open http://localhost:5000 in your browser"
fi

echo ""
print_success "Setup script completed successfully!"
echo ""
