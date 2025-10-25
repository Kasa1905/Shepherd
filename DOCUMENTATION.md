# 📚 Shepherd CMS - Documentation Index

Welcome to Shepherd Configuration Management System! This index will help you find exactly what you need.

## 🎯 I Want To...

### Get Started Quickly
- **[5-Minute Setup](GETTING-STARTED.md)** - For complete beginners, zero Docker knowledge required
- **[Quick Start Guide](QUICKSTART.md)** - Step-by-step tutorial with examples
- **[System Verification](verify-system.sh)** - Check if your system is ready (`./verify-system.sh`)

### Learn What Shepherd Does
- **[Main README](README.md)** - Complete feature list and technical overview
- **[API Documentation](README.md#api-reference)** - REST API endpoints and examples
- **[Web Interface Guide](README.md#web-interface)** - Using the web UI

### Deploy and Configure
- **[Local Development](GETTING-STARTED.md#for-developers)** - Run locally for development
- **[Docker Deployment](README.md#docker-deployment)** - Production Docker setup
- **[Deployment Guide](docs/deployment-guide.md)** - Kubernetes, Helm, production best practices
- **[Environment Configuration](.env.example)** - All configuration options explained

### Operate in Production
- **[Zero-Downtime Deployments](README.md#-zero-downtime-deployments)** - Rolling, Blue/Green, Canary strategies
- **[High Availability](README.md#️-high-availability--disaster-recovery)** - Multi-region, backup, DR
- **[Monitoring & Observability](README.md#-observability--monitoring)** - Logs, metrics, health checks
- **[Backup Procedures](docs/backup-procedures.md)** - Database backup and restore
- **[Disaster Recovery](docs/disaster-recovery.md)** - DR planning and execution

### Troubleshoot Issues
- **[Troubleshooting Guide](docs/troubleshooting-deployments.md)** - Common issues and solutions
- **[Quick Fixes](QUICKSTART.md#-troubleshooting)** - Fix common local setup problems
- **[System Health](README.md#health-monitoring)** - Check application health

### Develop and Contribute
- **[Running Tests](README.md#testing)** - How to run the test suite
- **[CI/CD Pipeline](README.md#cicd-pipeline)** - GitHub Actions workflows
- **[Infrastructure as Code](#infrastructure-templates)** - Terraform and Helm charts
- **[Contributing Guidelines](README.md#contributing)** - How to contribute

---

## 📂 Documentation Structure

```
Shepherd/
├── README.md                          # Main documentation
├── GETTING-STARTED.md                 # Beginner-friendly setup guide
├── QUICKSTART.md                      # Detailed quick start with examples
├── .env.example                       # Configuration template
│
├── docs/
│   ├── deployment-guide.md            # Production deployment
│   ├── backup-procedures.md           # Backup and restore
│   ├── disaster-recovery.md           # DR procedures
│   └── troubleshooting-deployments.md # Troubleshooting
│
├── scripts/
│   ├── setup-local.sh                 # Automated local setup (Mac/Linux)
│   ├── setup-local.bat                # Automated local setup (Windows)
│   ├── verify-system.sh               # System requirements checker
│   ├── deploy.sh                      # Deployment script
│   ├── deploy-blue-green.sh           # Blue/Green deployment
│   ├── canary-deploy.sh               # Canary deployment
│   └── rollback.sh                    # Rollback script
│
├── helm/shepherd/                     # Kubernetes Helm chart
│   ├── README.md                      # Helm chart documentation
│   ├── values.yaml                    # Default values
│   ├── values-staging.yaml            # Staging configuration
│   └── values-prod.yaml               # Production configuration
│
└── terraform/aws/                     # Terraform templates for AWS
    ├── README.md                      # Terraform documentation
    ├── main.tf                        # Main infrastructure
    └── variables.tf                   # Variable definitions
```

---

## 🚀 Quick Links by Role

### For End Users
1. [Install & Run](GETTING-STARTED.md)
2. [Use the Web UI](README.md#web-interface)
3. [Access the API](README.md#api-reference)

### For Developers
1. [Local Development Setup](GETTING-STARTED.md#for-developers)
2. [Run Tests](README.md#testing)
3. [CI/CD Pipeline](README.md#cicd-pipeline)

### For DevOps/SRE
1. [Production Deployment](docs/deployment-guide.md)
2. [Monitoring Setup](README.md#-observability--monitoring)
3. [Backup & DR](docs/backup-procedures.md)

### For System Administrators
1. [Docker Deployment](README.md#docker-deployment)
2. [Configuration Options](.env.example)
3. [Troubleshooting](docs/troubleshooting-deployments.md)

---

## 💡 Common Tasks

| Task | Documentation |
|------|---------------|
| Install for first time | [GETTING-STARTED.md](GETTING-STARTED.md) |
| Create a configuration | [Web Interface Guide](README.md#web-interface) |
| Use the REST API | [API Reference](README.md#api-reference) |
| Deploy to Kubernetes | [Deployment Guide](docs/deployment-guide.md) |
| Set up monitoring | [Observability](README.md#-observability--monitoring) |
| Configure backups | [Backup Procedures](docs/backup-procedures.md) |
| Rollback deployment | [Rollback Script](scripts/rollback.sh) |
| View logs | [Structured Logging](README.md#structured-logging) |
| Configure webhooks | [Webhook System](README.md#webhook-system) |
| Disaster recovery | [DR Guide](docs/disaster-recovery.md) |

---

## 🆘 Need Help?

1. **Check the documentation** - Use this index to find what you need
2. **Run system verification** - `./verify-system.sh` to check your setup
3. **Read troubleshooting guides**:
   - [Quick Fixes](QUICKSTART.md#-troubleshooting)
   - [Deployment Troubleshooting](docs/troubleshooting-deployments.md)
4. **Check logs**: `docker-compose -f docker-compose.local.yml logs -f`
5. **Open an issue** - [GitHub Issues](https://github.com/Kasa1905/Shepherd/issues)

---

## 🔖 Quick Command Reference

```bash
# Setup and Start
./setup-local.sh                                    # Automated setup (Mac/Linux)
setup-local.bat                                     # Automated setup (Windows)
./verify-system.sh                                  # Verify system requirements

# Docker Commands
docker-compose -f docker-compose.local.yml up -d    # Start services
docker-compose -f docker-compose.local.yml down     # Stop services
docker-compose -f docker-compose.local.yml logs -f  # View logs
docker-compose -f docker-compose.local.yml ps       # Check status

# Access
http://localhost:5000                               # Web UI
http://localhost:5000/api                           # API
http://localhost:5000/metrics                       # Prometheus metrics

# Testing
pytest test_shepherd.py -v                          # Run tests
pytest --cov                                        # Run with coverage
```

---

**Made with ❤️ by the Shepherd team**

Happy configuring! 🐑
