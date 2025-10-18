# Shepherd Configuration Management System

[![CI/CD Pipeline](https://github.com/Kasa1905/Shepherd/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Kasa1905/Shepherd/actions/workflows/ci-cd.yml)

A robust configuration management system with versioning capabilities, built with Flask and MongoDB. Shepherd provides both REST API endpoints and a responsive web interface for managing application configurations across different environments.

## 🌟 Features

- **Configuration Management**: Store and manage application configurations with versioning
- **Environment Support**: Organize configurations by environment (development, staging, production)
- **Version Control**: Automatic versioning with complete history tracking
- **Metadata Tracking**: Track who made changes and why with updated_by and change_notes fields
- **Create UI**: Intuitive web interface for creating configurations with schema templates
- **Version Comparison**: Visual diff tool to compare any two configuration versions
- **Rollback Functionality**: Easy rollback to any previous configuration version
- **REST API**: Comprehensive API for programmatic access with metadata support
- **Web Interface**: Responsive web UI built with Pico CSS
- **Role-Based Access**: Support for viewer, editor, and admin roles
- **Docker Support**: Production-ready containerization
- **Search & Query**: Advanced configuration discovery capabilities
- **Comprehensive Testing**: Full test suite with pytest including Phase 8 features
- **📊 Observability & Monitoring**: Comprehensive Phase 9 observability features
  - **Structured Logging**: JSON-formatted logs with request correlation and context
  - **Prometheus Metrics**: Database operations, HTTP requests, and application performance metrics
  - **Webhook System**: Event-driven notifications with retry mechanisms and delivery tracking
  - **Health Monitoring**: Application health checks and system status endpoints
  - **Infrastructure as Code**: Terraform and Helm templates with built-in observability

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Zero-Downtime Deployments](#-zero-downtime-deployments)
- [High Availability & Disaster Recovery](#️-high-availability--disaster-recovery)
- [Docker Deployment](#docker-deployment)
- [Local Development](#local-development)
- [Observability & Monitoring](#-observability--monitoring)
  - [Structured Logging](#structured-logging)
  - [Prometheus Metrics](#prometheus-metrics)
  - [Webhook System](#webhook-system)
  - [Health Monitoring](#health-monitoring)
- [API Reference](#api-reference)
- [Web Interface](#web-interface)
- [Configuration](#configuration)
- [Testing](#testing)
- [Infrastructure Templates](#-infrastructure-templates)
  - [Terraform (AWS)](#terraform-aws)
  - [Helm Chart](#helm-chart)
- [CI/CD Pipeline](#cicd-pipeline)
- [Production Deployment](#production-deployment)
- [Contributing](#contributing)

## 🚀 Quick Start

### Using Docker (Recommended)

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd shepherd
   ```

2. **Start the services**:
   ```bash
   docker-compose up -d
   ```

3. **Access the application**:
   - Web Interface: http://localhost:5000
   - API: http://localhost:5000/api
   - MongoDB Admin (optional): http://localhost:8081

4. **Verify installation**:
   ```bash
   curl http://localhost:5000/api/health -H "X-API-Key: <your-api-key>"
   ```

## � Zero-Downtime Deployments

Shepherd supports multiple deployment strategies for zero-downtime operations in production environments, ensuring continuous service availability during updates and maintenance.

### Deployment Strategies

| Strategy | Use Case | Downtime | Rollback Speed | Resource Overhead |
|----------|----------|----------|----------------|-------------------|
| **Rolling Update** | Routine updates, bug fixes | Zero | Fast (2-5 min) | Low (1x resources) |
| **Blue/Green** | Major versions, breaking changes | Zero | Instant (<30s) | High (2x resources) |
| **Canary** | High-risk changes, performance testing | Zero | Fast (1-2 min) | Medium (1.1-1.5x resources) |

### Quick Deployment Examples

#### Rolling Updates (Default)
```bash
# Deploy to staging
./scripts/deploy.sh \
  --namespace staging \
  --values helm/shepherd/values-staging.yaml

# Deploy to production
./scripts/deploy.sh \
  --namespace production \
  --values helm/shepherd/values-prod.yaml
```

#### Blue/Green Deployment
```bash
# Zero-downtime deployment with instant rollback capability
./scripts/deploy-blue-green.sh \
  --namespace production \
  --image shepherd:v2.0.0
```

#### Canary Deployment
```bash
# Gradual rollout with metrics validation
./scripts/canary-deploy.sh \
  --namespace production \
  --image shepherd:v2.1.0 \
  --stages "10,25,50,100"
```

#### Emergency Rollback
```bash
# Instant rollback to previous version
./scripts/rollback.sh \
  --namespace production \
  --reason "Performance issue detected"
```

### Automated CI/CD Integration

Deployments are integrated with GitHub Actions for automated staging deployments and manual production deployments:

#### Trigger Production Deployment
```bash
# Via GitHub CLI
gh workflow run ci-cd.yml \
  --ref main \
  -f deployment_strategy=blue-green \
  -f image_tag=v2.0.0

# Via GitHub Actions UI
# 1. Go to Actions tab
# 2. Select "CI/CD Pipeline"
# 3. Click "Run workflow"
# 4. Select deployment strategy
```

#### Emergency Rollback via CI/CD
```bash
gh workflow run rollback.yml \
  --ref main \
  -f environment=production \
  -f reason="Critical issue detected"
```

### Deployment Features

- ✅ **Pre-flight Validation**: Comprehensive checks before deployment
- ✅ **Health Monitoring**: Real-time health validation during deployments
- ✅ **Automatic Rollback**: Triggers on health check failures or error thresholds
- ✅ **Smoke Testing**: Validates functionality before traffic switching
- ✅ **Metrics Monitoring**: Error rate and performance tracking during canary deployments
- ✅ **Traffic Shifting**: Gradual traffic migration with configurable stages
- ✅ **Environment Parity**: Consistent deployment across staging and production

### Documentation & Troubleshooting

- **[Comprehensive Deployment Guide](docs/deployment-guide.md)**: Complete procedures for all strategies
- **[Troubleshooting Guide](docs/troubleshooting-deployments.md)**: Systematic issue resolution
- **[Emergency Procedures](docs/deployment-guide.md#emergency-procedures)**: Critical incident response

### Prerequisites

For zero-downtime deployments, ensure:
- Kubernetes cluster with appropriate RBAC permissions
- Helm 3.8+ installed and configured
- kubectl configured for target clusters
- Proper secrets management (MongoDB credentials, API keys)
- Monitoring and alerting configured (optional but recommended)

## �🛡️ High Availability & Disaster Recovery

Shepherd includes enterprise-grade HA/DR capabilities across all deployment environments with comprehensive backup and monitoring solutions.

### HA/DR Overview

| Deployment | Architecture | RTO Target | RPO Target | Backup Retention |
|------------|-------------|------------|------------|------------------|
| Docker Compose | 3-node MongoDB replica set | 60 minutes | 15 minutes | 30 days |
| AWS | DocumentDB multi-AZ cluster | 60 minutes | 15 minutes | 30 days |
| Kubernetes | MongoDB StatefulSet (3 replicas) | 60 minutes | 15 minutes | 30 days |

### Key Features

- **Automated Replica Set Management**: Self-healing MongoDB clusters
- **Cross-Region Backup Replication**: AWS DocumentDB with automated verification
- **Health Monitoring**: Application and database health checks with failover detection
- **Automated Backup Verification**: Lambda-based backup testing and validation
- **Disaster Recovery Testing**: Automated DR testing scripts and procedures

### Quick HA Setup

#### Docker Compose (Development/Testing)
```bash
# Start 3-node replica set
docker-compose up -d

# Verify replica set status
docker exec mongo-primary mongosh --eval "rs.status()"
```

#### AWS Production
```bash
# Deploy with Terraform
cd terraform/aws
terraform init
terraform plan -var="documentdb_backup_retention_period=30"
terraform apply
```

#### Kubernetes Production
```bash
# Deploy with Helm
helm install shepherd ./helm/shepherd \
  --set mongodb.internal.enabled=true \
  --set mongodb.internal.replicaSet.enabled=true \
  --set backup.enabled=true
```

### Disaster Recovery Testing
```bash
# Run automated DR tests
./scripts/test-dr.sh

# Check results
cat /tmp/shepherd-dr-results-*.json
```

### Documentation
- **[Disaster Recovery Runbook](docs/disaster-recovery.md)**: Complete DR procedures
- **[Backup Procedures](docs/backup-procedures.md)**: Backup and restore operations
- **[Monitoring Guide](docs/monitoring.md)**: HA monitoring setup

### Recovery Time Objectives (RTO)
- **Primary Node Failure**: < 5 minutes (automatic failover)
- **Complete Environment Recovery**: < 60 minutes
- **Cross-Region Failover**: < 60 minutes

### Recovery Point Objectives (RPO)
- **Local Replica Lag**: < 1 minute
- **Backup Point-in-Time**: < 15 minutes
- **Cross-Region Replication**: < 15 minutes

## 🐳 Docker Deployment

### Standard Deployment

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Stop and remove volumes (⚠️ This will delete all data)
docker-compose down -v
```

### Development with Debug Tools

```bash
# Start with MongoDB Express admin interface
docker-compose --profile debug up -d

# Access MongoDB Express at http://localhost:8081
# Username: admin, Password: admin123
```

### Production Deployment

```bash
# Build and deploy for production
docker-compose -f docker-compose.yml up -d

# Scale the application (multiple replicas)
docker-compose up -d --scale shepherd-app=3
```

## 💻 Local Development

### Prerequisites

- Python 3.11 or higher
- MongoDB 4.4 or higher
- pip (Python package manager)

### Setup

1. **Clone and setup environment**:
   ```bash
   git clone <repository-url>
   cd shepherd
   cp .env.example .env
   ```

2. **Create virtual environment**:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment variables** (edit `.env`):
   ```bash
   MONGODB_HOST=localhost
   MONGODB_PORT=27017
   MONGODB_DATABASE=shepherd
   FLASK_ENV=development
   FLASK_DEBUG=True
   ```

5. **Start MongoDB** (if not using Docker):
   ```bash
   # macOS with Homebrew
   brew services start mongodb-community

   # Ubuntu/Debian
   sudo systemctl start mongod

   # Docker
   docker run -d -p 27017:27017 --name mongodb mongo:7.0
   ```

6. **Run the application**:
   ```bash
   python app.py
   ```

7. **Access the application**:
   - Web Interface: http://localhost:5000
   - API: http://localhost:5000/api

## � Observability & Monitoring

Shepherd includes comprehensive observability features introduced in Phase 9, providing deep insights into application performance, request flows, and system health.

### Structured Logging

Shepherd implements structured JSON logging with request correlation and contextual information:

**Features:**
- **JSON Format**: All logs are structured in JSON format for easy parsing and analysis
- **Request Correlation**: Each request gets a unique `request_id` that traces through all related operations
- **Response Headers**: Request ID is returned in the `X-Request-ID` response header for client correlation
- **Contextual Information**: Logs include user information, operation details, and timing data
- **Log Levels**: Configurable logging levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- **Performance Tracking**: Automatic timing of database operations and API requests

**Configuration:**
```bash
# Environment Variables
LOG_LEVEL=INFO                    # Set logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
LOG_FORMAT=json                   # Enable structured logging (json or text)
LOG_FILE=/var/log/shepherd.log    # Optional file path for log output
LOG_TO_CONSOLE=True              # Enable console logging (default: True)
LOG_REQUEST_ID=True              # Include request IDs in logs (default: True)
LOG_USER_CONTEXT=True            # Include user info in logs (default: True)
```

**Request ID Header:**
All API responses include the request ID for correlation:
```bash
curl -v http://localhost:5000/api/health -H "X-API-Key: <your-api-key>"
# Response includes:
# X-Request-ID: 550e8400-e29b-41d4-a716-446655440000
```

**Example Log Output:**
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "level": "INFO",
  "message": "Configuration created successfully",
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "admin",
  "operation": "create_config",
  "environment": "production",
  "config_name": "api-settings",
  "version": 1,
  "duration_ms": 45.67,
  "module": "logging_config"
}
```

**Integration Reference:**
The structured logging is implemented in `logging_config.py` with the `setup_logging()` function and Flask hooks for request/response correlation.

### Prometheus Metrics

Shepherd exposes detailed metrics for monitoring application performance and health:

**Available Metrics:**
- **HTTP Request Metrics**: `http_requests_total`, `http_request_duration_seconds`, `http_requests_in_progress`
- **Configuration Metrics**: `config_total`, `config_versions_total`, `config_operations_total`
- **Database Metrics**: `mongodb_operations_total`, `mongodb_operation_duration_seconds`, `mongodb_documents_total`
- **Authentication Metrics**: `auth_attempts_total`, `api_key_usage_total`, `active_sessions`

**Metrics Endpoint:**
```bash
# Access Prometheus metrics
curl http://localhost:5000/metrics

# Example metrics output
http_requests_total{method="GET",endpoint="get_latest_configuration",status_code="200"} 1247
http_requests_total{method="POST",endpoint="create_config",status_code="201"} 156
http_requests_total{method="PUT",endpoint="update_configuration",status_code="200"} 523
http_request_duration_seconds_bucket{method="GET",endpoint="query_configurations",le="0.05"} 245
http_request_duration_seconds_bucket{method="GET",endpoint="query_configurations",le="0.1"} 567
http_request_duration_seconds_bucket{method="GET",endpoint="query_configurations",le="+Inf"} 1247
http_request_duration_seconds_sum{method="GET",endpoint="query_configurations"} 23.4
http_request_duration_seconds_count{method="GET",endpoint="query_configurations"} 1247
http_requests_in_progress 3
config_total{app_name="myapp",environment="production"} 42
config_versions_total{config_id="myapp_prod"} 156
config_operations_total{operation="create",status="success"} 523
mongodb_operations_total{operation="insert",collection="configurations"} 523
mongodb_operation_duration_seconds{operation="find",collection="users"} 0.012
mongodb_documents_total{collection="configurations"} 42
auth_attempts_total{status="success"} 1024
api_key_usage_total{user="admin"} 256
active_sessions 5
```

**Content Type and Behavior:**
- Content-Type: `text/plain; version=0.0.4; charset=utf-8` (Prometheus format)
- Returns HTTP 503 when metrics are disabled via `METRICS_ENABLED=False`
- Updates automatically every 60 seconds for database-derived metrics
- **Note**: The `endpoint` label uses the Flask endpoint name (function name), not the URL path

**Integration with Monitoring Stack:**
```yaml
# prometheus.yml configuration
scrape_configs:
  - job_name: 'shepherd'
    static_configs:
      - targets: ['localhost:5000']
    metrics_path: /metrics
    scrape_interval: 15s
    scrape_timeout: 10s
```

### Webhook System

Event-driven webhook system for real-time notifications and integrations:

**Features:**
- **Event Types**: Configuration changes, user actions, system events
- **Retry Mechanism**: Automatic retry with exponential backoff
- **Delivery Tracking**: Success/failure tracking with detailed logging
- **HMAC Signature Verification**: Secure webhook payloads with SHA256 signatures
- **Environment-Driven Configuration**: Fully configurable via environment variables

**Environment Configuration:**
```bash
# Environment Variables
WEBHOOK_ENABLED=True                                    # Enable/disable webhook dispatch
WEBHOOK_URLS=https://api.example.com/webhook,https://backup.example.com/hook  # Comma-separated URLs
WEBHOOK_SECRET=your-shared-secret-key                   # HMAC signing secret
WEBHOOK_EVENTS=config.created,config.updated,config.rolled_back  # Event types to dispatch
WEBHOOK_TIMEOUT=10                                      # Request timeout in seconds
WEBHOOK_RETRY_ATTEMPTS=3                               # Maximum retry attempts
WEBHOOK_RETRY_DELAY=1                                  # Initial retry delay in seconds
```

**Admin Endpoints:**
```bash
# List configured webhooks (admin-only, secrets redacted)
curl -X GET http://localhost:5000/api/webhooks \
  -H "X-API-Key: <admin-api-key>"

# Dispatch test event (admin-only)
curl -X POST http://localhost:5000/api/webhooks/test \
  -H "X-API-Key: <admin-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"event_type": "test.event"}'

# Get delivery statistics (admin-only)
curl -X GET http://localhost:5000/api/webhooks/stats \
  -H "X-API-Key: <admin-api-key>"
```

**HMAC Signature Verification:**
Webhooks are signed with HMAC-SHA256 using the `WEBHOOK_SECRET`. The signature is sent in the `X-Shepherd-Signature` header:

```python
import hmac
import hashlib

def verify_webhook_signature(payload: str, signature: str, secret: str) -> bool:
    """Verify webhook HMAC signature."""
    expected = hmac.new(
        secret.encode(), 
        payload.encode(), 
        hashlib.sha256
    ).hexdigest()
    expected_signature = f"sha256={expected}"
    return hmac.compare_digest(expected_signature, signature)

# Usage example
payload = request.get_data(as_text=True)
signature = request.headers.get('X-Shepherd-Signature')
secret = 'your-shared-secret-key'

if verify_webhook_signature(payload, signature, secret):
    # Process webhook
    pass
else:
    # Invalid signature
    abort(401)
```

**Event Payload Example:**
```json
{
  "event_type": "config.updated",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "request_id": "req_abc123xyz",
  "data": {
    "config_name": "api-settings",
    "environment": "production",
    "version": 2,
    "updated_by": "admin",
    "change_notes": "Updated timeout values"
  },
  "metadata": {
    "source": "shepherd-cms",
    "version": "1.0.0"
  }
}
```

### Health Monitoring

Comprehensive health check system for monitoring application and dependency status:

**Health Endpoints:**
```bash
# Basic health check (requires API key)
curl http://localhost:5000/api/health \
  -H "X-API-Key: <your-api-key>"
```

**Health Response Example:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "version": "1.0.0",
  "uptime_seconds": 86400,
  "checks": {
    "database": {
      "status": "healthy",
      "response_time_ms": 12.5,
      "connections": {
        "active": 2,
        "max": 10
      }
    },
    "memory": {
      "status": "healthy",
      "usage_mb": 256,
      "usage_percent": 25.6
    },
    "disk": {
      "status": "healthy",
      "free_gb": 45.8,
      "usage_percent": 62.3
    }
  }
}
```

**Monitoring Integration:**
- **Kubernetes**: Readiness and liveness probes
- **Docker**: Health check configuration
- **Load Balancers**: Upstream health validation
- **Monitoring Tools**: Integration with Datadog, New Relic, etc.

## �📚 API Reference

### Base URL
```
http://localhost:5000/api
```

### Endpoints

#### Health Check
```http
GET /api/health
```
Returns the health status of the application.

#### Create Configuration
```http
POST /api/config
Content-Type: application/json

{
    "config_id": "database-config-dev",
    "app_name": "database-config",
    "environment": "development",
    "settings": {
        "host": "localhost",
        "port": 5432,
        "database": "myapp"
    },
    "updated_by": "john.doe",
    "change_notes": "Initial database configuration setup"
}
```

#### Update Configuration
```http
PUT /api/config/{config_id}
Content-Type: application/json

{
    "settings": {
        "host": "prod-db.example.com",
        "port": 5432,
        "database": "myapp_prod"
    },
    "updated_by": "jane.smith",
    "change_notes": "Updated to production database host"
}
```

#### Get Configuration Version
```http
GET /api/config/{config_id}/version/{version}
```
Returns a specific version of the configuration.

#### Rollback Configuration
```http
POST /api/config/{config_id}/rollback/{version}
Content-Type: application/json

{
    "updated_by": "admin.user",
    "change_notes": "Rolled back due to production issues"
}
```
Content-Type: application/json

{
    "environment": "development",
    "settings": {
        "host": "localhost",
        "port": 5432,
        "database": "myapp",
        "pool_size": 20
    }
}
```

#### Get Configuration History
```http
GET /api/config/history/{config_id}
```
Returns all versions of a configuration, sorted by version descending. Use this endpoint to access previous versions.

### Response Format

#### Success Response
```json
{
    "success": true,
    "data": {
        "config_id": "database-config-dev",
        "app_name": "database-config",
        "environment": "development",
        "version": 1,
        "settings": {...},
        "created_at": "2024-01-15T10:30:00Z",
        "updated_at": "2024-01-15T10:30:00Z"
    }
}
```

#### Error Response
```json
{
    "success": false,
    "error": "Configuration not found",
    "code": "CONFIG_NOT_FOUND"
}
```

## 🖥️ Web Interface

### Dashboard
- View all configurations organized by environment
- Quick search and filtering
- Create new configurations with one-click access
- Direct links to configuration details

### Create Configuration
- **NEW**: Intuitive form-based configuration creation
- **NEW**: Schema templates for common configuration patterns (database, API service, feature flags, cache, logging)
- JSON validation and copy-to-clipboard functionality
- Metadata tracking (updated_by, change_notes)

### Configuration Details
- View complete configuration in formatted JSON
- **NEW**: Display metadata (updated_by, change_notes, timestamps)
- Access edit, history, and comparison functions

### Edit Configuration
- Form-based configuration editing with JSON validation
- **NEW**: Change notes field for tracking modification reasons
- **NEW**: Display previous change notes for context
- Version increment handling with metadata

### History View
- Complete version history with metadata display
- **NEW**: Compare any two versions with visual diff
- **NEW**: One-click rollback to previous versions (editor/admin only)
- **NEW**: Side-by-side metadata comparison

### Version Comparison
- **NEW**: Visual diff highlighting additions, removals, and modifications
- **NEW**: Metadata comparison (updated_by, change_notes)
- **NEW**: Rollback confirmation with safety warnings

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `MONGODB_HOST` | MongoDB hostname | localhost | Yes |
| `MONGODB_PORT` | MongoDB port | 27017 | Yes |
| `MONGODB_DATABASE` | Database name | shepherd | Yes |
| `MONGODB_USERNAME` | Database username | - | No |
| `MONGODB_PASSWORD` | Database password | - | No |
| `FLASK_ENV` | Flask environment | development | No |
| `FLASK_DEBUG` | Enable debug mode | False | No |
| `PORT` | Application port | 5000 | No |

### MongoDB Configuration

The application creates the following indexes automatically:
- Compound unique index on `name` and `version`
- Index on `name` for efficient lookups
- Index on `environment` for filtering
- Index on `created_at` for sorting

## 🧪 Testing

### Run All Tests
```bash
# With pytest
pytest

# With coverage
pytest --cov=. --cov-report=html

# Verbose output
pytest -v
```

### Run Specific Tests
```bash
# Test configuration creation
pytest -k test_create

# Test API endpoints
pytest test_shepherd.py::TestShepherdAPI

# Test database layer
pytest test_shepherd.py::TestConfigurationManager
```

### Test Coverage
The test suite includes:
- ✅ Configuration CRUD operations
- ✅ Versioning logic
- ✅ API endpoint validation
- ✅ Error handling
- ✅ Database layer testing
- ✅ Web interface testing
- ✅ Query functionality

## 🏗️ Infrastructure Templates

Shepherd provides production-ready Infrastructure as Code templates with built-in observability and monitoring capabilities.

### Terraform (AWS)

Complete AWS deployment template with observability stack integration:

**Location:** `terraform/aws/`

**Features:**
- **ECS Fargate**: Containerized deployment with auto-scaling
- **Application Load Balancer**: High availability with health checks
- **CloudWatch Integration**: Structured logging and metrics collection
- **VPC Configuration**: Secure network setup with private subnets
- **RDS MongoDB**: Managed database with backup and monitoring
- **IAM Roles**: Least-privilege security configuration

**Quick Deployment:**
```bash
cd terraform/aws

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var="environment=production"

# Deploy infrastructure
terraform apply -var="environment=production"
```

**Key Configuration Variables:**
```hcl
# terraform.tfvars
project_name = "shepherd"
environment = "production"
aws_region = "us-west-2"

# Application configuration
docker_image = "your-account.dkr.ecr.us-west-2.amazonaws.com/shepherd:latest"
app_count = 2

# Security configuration
ssl_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/..."
alarms_email = "alerts@yourcompany.com"

# Database configuration
documentdb_master_password = "YourSecurePassword123!"
secret_key = "your-very-secure-flask-secret-key"
log_level = "INFO"
```

**Outputs:**
- Load balancer DNS name
- Application URL with health endpoints
- CloudWatch log group names
- Monitoring dashboard URLs

### Helm Chart

Kubernetes deployment with comprehensive observability stack:

**Location:** `helm/shepherd/`

**Features:**
- **Deployment**: Rolling updates with configurable replicas
- **Service**: ClusterIP/NodePort/LoadBalancer support
- **Ingress**: NGINX/Traefik integration with TLS
- **ConfigMap**: Environment-specific configuration
- **ServiceMonitor**: Prometheus scraping configuration
- **PodDisruptionBudget**: High availability guarantees

**Quick Deployment:**
```bash
# Add to your cluster
helm install shepherd ./helm/shepherd

# Production deployment with custom values
helm install shepherd ./helm/shepherd \
  --values production-values.yaml \
  --namespace shepherd \
  --create-namespace
```

**Observability Configuration:**
```yaml
# values.yaml
observability:
  enabled: true
  
  # Prometheus metrics
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      interval: 30s
    
  # Structured logging
  logging:
    level: INFO
    format: JSON
    
  # Health checks
  healthChecks:
    readiness:
      enabled: true
      path: /api/health
    liveness:
      enabled: true
      path: /api/health
      
  # Webhook configuration
  webhooks:
    enabled: true
    retryAttempts: 3
    timeoutSeconds: 30
```

**Production Values Example:**
```yaml
# production-values.yaml
replicaCount: 3

image:
  repository: your-registry/shepherd
  tag: "1.0.0"
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: shepherd.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: shepherd-tls
      hosts:
        - shepherd.yourdomain.com

mongodb:
  external: true
  connectionString: "mongodb://prod-cluster:27017/shepherd"
  
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

**Monitoring Stack Integration:**
```bash
# Deploy with Prometheus Operator
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Install Grafana for visualization
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana

# Deploy Shepherd with monitoring
helm install shepherd ./helm/shepherd --set observability.enabled=true
```

## � CI/CD Pipeline

The project uses GitHub Actions for automated testing, linting, security scanning, and Docker image building. The pipeline runs on every pull request and push to main branch, and all checks must pass before code can be merged.

### Pipeline Stages

#### 1. Code Quality & Linting
- Runs flake8 to check code style and quality
- Enforces PEP 8 standards
- Fails on critical errors (syntax errors, undefined names, etc.)
- Command to run locally: `flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics`

#### 2. Security Scanning
- **Bandit**: Scans Python code for security vulnerabilities
  - Checks for hardcoded passwords, SQL injection risks, insecure functions
  - Command: `bandit -r . -f json -o bandit-report.json`
- **Safety**: Checks dependencies for known security vulnerabilities
  - Scans requirements.txt against vulnerability database
  - Command: `safety check`

#### 3. Unit Tests
- Runs comprehensive test suite with pytest
- Uses MongoDB service container for integration tests
- Generates coverage reports (HTML and XML)
- Tests run on Python 3.11 (can be extended to multiple versions)
- Command: `pytest test_shepherd.py -v --cov=. --cov-report=html`

#### 4. Docker Image Build
- Builds Docker image using the Dockerfile
- Only runs on successful push to main branch
- Uses Docker layer caching for faster builds
- Tags image with: `latest`, `sha-{commit}`, `{branch}`

#### 5. Docker Image Push
- Pushes built image to Docker Hub and/or GitHub Container Registry
- Only runs after all tests pass
- Only executes on main branch
- Requires Docker Hub credentials configured as secrets

### Required GitHub Secrets

To configure the CI/CD pipeline, you need to set up the following secrets:

#### Setting Up Secrets:
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add the following secrets:

| Secret Name | Description | Required |
|-------------|-------------|----------|
| `DOCKER_USERNAME` | Docker Hub username | Yes (for Docker push) |
| `DOCKER_PASSWORD` | Docker Hub password or access token | Yes (for Docker push) |
| `CODECOV_TOKEN` | Codecov upload token | No (optional) |

**Note:** `GITHUB_TOKEN` is automatically provided by GitHub Actions for GHCR access.

### Running CI Checks Locally

You can run the same checks locally before pushing:

```bash
# Install development dependencies
pip install -r requirements.txt

# Run linting
flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
flake8 . --count --exit-zero --max-complexity=10 --max-line-length=127 --statistics

# Run security scans
bandit -r . -ll
safety check

# Run tests with coverage
pytest test_shepherd.py -v --cov=. --cov-report=html

# Format code (optional)
black .

# Build Docker image locally
docker build -t shepherd-cms:local .
```

### Workflow Triggers
- **Pull Requests**: All stages run (lint, security, test) but no Docker push
- **Push to Main**: All stages run including Docker build and push
- **Manual Dispatch**: Can be triggered manually from GitHub Actions UI

### Viewing CI Results
- Navigate to the "Actions" tab in the GitHub repository
- Click on a workflow run to see detailed logs
- Download artifacts (coverage reports, security scans) from completed runs
- Check the status badge in the README for current build status

### Troubleshooting CI Failures

#### Lint Failures:
- Review flake8 output in the workflow logs
- Run `flake8 .` locally to see all issues
- Fix code style issues or update `.flake8` configuration if needed

#### Security Scan Failures:
- Review Bandit report for code security issues
- Check Safety output for vulnerable dependencies
- Update dependencies: `pip install --upgrade <package>`
- Add exceptions to `.bandit` if false positives

#### Test Failures:
- Check pytest output in workflow logs
- Ensure MongoDB service is running (in CI, it's automatic)
- Run tests locally: `pytest test_shepherd.py -v`
- Check for environment-specific issues

#### Docker Build Failures:
- Verify Dockerfile syntax
- Check that all required files are present
- Ensure `.dockerignore` is not excluding necessary files
- Test build locally: `docker build -t test .`

### Best Practices:
- Always run tests locally before pushing
- Keep dependencies up to date
- Review security scan results regularly
- Monitor build times and optimize if needed
- Use meaningful commit messages
- Ensure all tests pass before requesting review

## �🚀 Production Deployment

### Docker Production Setup

1. **Update environment variables**:
   ```bash
   cp .env.example .env.production
   # Edit .env.production with production values
   ```

2. **Deploy with production settings**:
   ```bash
   docker-compose -f docker-compose.yml up -d
   ```

3. **Monitor the deployment**:
   ```bash
   # Check container health
   docker-compose ps

   # View application logs
   docker-compose logs -f shepherd-app

   # Monitor MongoDB
   docker-compose logs -f shepherd-mongo
   ```

### Security Considerations

1. **Change default passwords** in `docker-compose.yml`
2. **Use environment-specific secrets**
3. **Enable MongoDB authentication** (enabled by default)
4. **Configure firewall rules** for production ports
5. **Use HTTPS** with a reverse proxy (nginx/traefik)
6. **Regular backup** of MongoDB data volumes

### Backup and Recovery

```bash
# Backup MongoDB data
docker exec shepherd-mongo mongodump --db shepherd --out /tmp/backup

# Copy backup from container
docker cp shepherd-mongo:/tmp/backup ./mongodb-backup

# Restore from backup
docker exec -i shepherd-mongo mongorestore --db shepherd /tmp/backup/shepherd
```

### Monitoring

Health check endpoints:
- Application: `GET /api/health`
- MongoDB: Built-in health checks in docker-compose

Log locations:
- Application logs: Docker logs (`docker-compose logs shepherd-app`)
- MongoDB logs: Docker logs (`docker-compose logs shepherd-mongo`)

## 🔧 Architecture

### Components

1. **Flask Application** (`app.py`)
   - REST API endpoints
   - Web interface routes
   - Error handling and validation

2. **Database Layer** (`database.py`)
   - MongoDB connection management
   - Configuration CRUD operations
   - Versioning logic

3. **Web Templates** (`templates/`)
   - Responsive UI with Pico CSS
   - Dashboard, details, edit, and history views

4. **Docker Configuration**
   - Multi-service deployment
   - Health checks and monitoring
   - Volume management

### Data Model

```json
{
    "_id": "ObjectId",
    "config_id": "unique-configuration-identifier",
    "app_name": "application-name",
    "environment": "development|staging|production",
    "version": 1,
    "settings": {
        // Flexible JSON configuration data
    },
    "created_at": "ISO 8601 timestamp",
    "updated_at": "ISO 8601 timestamp"
}
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Run the test suite (`pytest`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Guidelines

- Follow PEP 8 for Python code style
- Add tests for all new features
- Update documentation for API changes
- Use meaningful commit messages

## 🔄 Migration Guide (Phase 8)

### New Features in Phase 8

Phase 8 introduces enhanced UX features with full backward compatibility:

#### Metadata Tracking
- **updated_by**: Track who made each change
- **change_notes**: Record reasons for configuration changes
- All API endpoints now support optional metadata fields

#### Create Configuration UI
- New `/create` endpoint for web-based configuration creation
- Schema templates for common patterns (database, API, cache, etc.)
- JSON validation and copy-to-clipboard functionality

#### Version Comparison
- Visual diff tool at `/compare/{config_id}/{v1}/{v2}`
- Highlight additions, removals, and modifications
- Side-by-side metadata comparison

#### Rollback Functionality
- One-click rollback to any previous version
- Safety confirmation modals
- Automatic metadata tracking for rollback operations

### Backward Compatibility

**Existing configurations work unchanged:**
- Configurations without metadata fields continue to function normally
- API endpoints remain compatible with existing clients
- No database migration required

**Optional metadata adoption:**
- Start using `updated_by` and `change_notes` in new API calls
- Existing configurations can be updated to include metadata
- Web interface gracefully handles missing metadata

### API Changes

**Enhanced endpoints (backward compatible):**
```http
# Create with metadata (optional)
POST /api/config
{
    "config_id": "my-config",
    "app_name": "my-app",
    "environment": "production",
    "settings": {...},
    "updated_by": "john.doe",           // NEW: Optional
    "change_notes": "Initial setup"     // NEW: Optional
}

# Update with metadata (optional)
PUT /api/config/my-config
{
    "settings": {...},
    "updated_by": "jane.smith",         // NEW: Optional
    "change_notes": "Performance fix"   // NEW: Optional
}
```

**New endpoints:**
- `GET /api/config/{config_id}/version/{version}` - Get specific version
- `POST /api/config/{config_id}/rollback/{version}` - Rollback configuration

### Web Interface Enhancements

**New pages:**
- `/create` - Configuration creation form
- `/compare/{config_id}/{v1}/{v2}` - Version comparison tool

**Enhanced existing pages:**
- Dashboard: Create button for editors/admins
- Details: Metadata display
- Edit: Change notes field
- History: Compare and rollback buttons


## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🐛 Troubleshooting

### Common Issues

**MongoDB Connection Failed**
```bash
# Check MongoDB status
docker-compose ps shepherd-mongo

# View MongoDB logs
docker-compose logs shepherd-mongo

# Restart MongoDB
docker-compose restart shepherd-mongo
```

**Application Won't Start**
```bash
# Check application logs
docker-compose logs shepherd-app

# Verify environment variables
docker-compose exec shepherd-app env | grep MONGODB

# Restart application
docker-compose restart shepherd-app
```

**Port Already in Use**
```bash
# Check what's using port 5000
lsof -i :5000

# Kill process if needed
kill -9 <PID>

# Or use different port in docker-compose.yml
```

### Getting Help

- Check the [Issues](https://github.com/your-repo/shepherd/issues) page
- Review application logs: `docker-compose logs`
- Verify configuration with health check: `curl http://localhost:5000/api/health -H "X-API-Key: <your-api-key>"`

---

**Shepherd Configuration Management System** - Simplifying configuration management with versioning and reliability.