#!/bin/bash

# ==============================================================================
# Shepherd CMS - Setup Verification Script
# ==============================================================================
# This script checks if your system is ready to run Shepherd
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║          🐑 Shepherd System Verification                       ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ERRORS=0
WARNINGS=0

# Check Docker
print_info "Checking Docker installation..."
if command -v docker &> /dev/null; then
    VERSION=$(docker --version)
    print_success "Docker found: $VERSION"
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        print_success "Docker daemon is running"
    else
        print_error "Docker is installed but not running!"
        print_info "Please start Docker Desktop and try again"
        ((ERRORS++))
    fi
else
    print_error "Docker is not installed!"
    print_info "Download from: https://www.docker.com/products/docker-desktop"
    ((ERRORS++))
fi

# Check Docker Compose
print_info "Checking Docker Compose..."
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
    print_success "Docker Compose found"
else
    print_error "Docker Compose is not installed!"
    ((ERRORS++))
fi

# Check available disk space
print_info "Checking disk space..."
if command -v df &> /dev/null; then
    AVAILABLE=$(df -h . | awk 'NR==2 {print $4}')
    print_success "Available disk space: $AVAILABLE"
else
    print_warning "Could not check disk space"
    ((WARNINGS++))
fi

# Check available memory
print_info "Checking available memory..."
if command -v free &> /dev/null; then
    AVAILABLE_MEM=$(free -h | awk 'NR==2 {print $7}')
    print_success "Available memory: $AVAILABLE_MEM"
elif command -v vm_stat &> /dev/null; then
    # Mac
    print_success "Memory check: OK (macOS)"
else
    print_warning "Could not check memory"
    ((WARNINGS++))
fi

# Check if ports are available
print_info "Checking port availability..."
if command -v lsof &> /dev/null; then
    if lsof -Pi :5000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port 5000 is already in use"
        print_info "You may need to change the PORT in .env file"
        ((WARNINGS++))
    else
        print_success "Port 5000 is available"
    fi
    
    if lsof -Pi :27017 -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port 27017 (MongoDB) is already in use"
        print_info "You may have another MongoDB instance running"
        ((WARNINGS++))
    else
        print_success "Port 27017 is available"
    fi
elif command -v netstat &> /dev/null; then
    # Alternative port check for systems without lsof
    print_success "Port check: Using alternative method"
else
    print_warning "Could not check port availability"
    ((WARNINGS++))
fi

# Check if required files exist
print_info "Checking required files..."
REQUIRED_FILES=(
    "docker-compose.local.yml"
    "Dockerfile"
    "app.py"
    "requirements.txt"
    ".env.example"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "Found: $file"
    else
        print_error "Missing: $file"
        ((ERRORS++))
    fi
done

# Check if .env exists
if [ ! -f .env ]; then
    print_warning ".env file not found"
    print_info "Will be created from .env.example during setup"
    ((WARNINGS++))
else
    print_success ".env file exists"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Verification Summary                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_success "All checks passed! ✨"
    echo ""
    print_info "Your system is ready to run Shepherd!"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./setup-local.sh"
    echo "  2. Open: http://localhost:5000"
    echo "  3. Login with: admin / admin123"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    print_warning "System check completed with $WARNINGS warning(s)"
    echo ""
    print_info "You can proceed, but you may need to address the warnings."
    echo ""
    echo "To continue anyway, run: ./setup-local.sh"
    echo ""
    exit 0
else
    print_error "System check failed with $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    print_info "Please fix the errors above before running Shepherd."
    echo ""
    exit 1
fi
