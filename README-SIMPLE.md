# 🐑 Shepherd Configuration Management System

> **Manage your application configurations like a pro. Version control for your configs!**

[![CI/CD Pipeline](https://github.com/Kasa1905/Shepherd/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Kasa1905/Shepherd/actions/workflows/ci-cd.yml)
[![Python 3.12](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/downloads/)
[![MongoDB 7.0](https://img.shields.io/badge/mongodb-7.0-green.svg)](https://www.mongodb.com/)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## 🚀 Get Started in 5 Minutes

### Step 1: Install Docker
Download [Docker Desktop](https://www.docker.com/products/docker-desktop) for your operating system.

### Step 2: Run Shepherd

**On Windows:**
```cmd
setup-local.bat
```

**On Mac/Linux:**
```bash
./setup-local.sh
```

### Step 3: Start Using!
Your browser will open automatically to http://localhost:5000

**Login:** admin / admin123

**That's it!** 🎉

> 📖 **New user?** Read the [Getting Started Guide](GETTING-STARTED.md) | [Quick Start Tutorial](QUICKSTART.md) | [Full Documentation](DOCUMENTATION.md)

---

## ✨ What Can Shepherd Do?

| Feature | Description |
|---------|-------------|
| 📝 **Configuration Management** | Store all your app configs in one place |
| 🔄 **Version Control** | Every change is saved, nothing is ever lost |
| ⏮️ **Easy Rollback** | Go back to any previous version with one click |
| 🌍 **Multi-Environment** | Separate configs for dev, staging, production |
| 👥 **Team Collaboration** | See who changed what and why |
| 📊 **Visual Diff** | Compare any two versions side-by-side |
| 🔌 **REST API** | Integrate with your apps and services |
| 🌐 **Web Interface** | Beautiful, modern UI for humans |
| 📡 **Webhooks** | Get notified when configs change |
| 📈 **Metrics** | Monitor everything with Prometheus |

---

## 💡 Why Use Shepherd?

### The Problem
- Configs scattered across files, repos, and servers
- No history of who changed what
- Hard to rollback when something breaks
- Different configs for different environments
- No easy way to compare versions

### The Solution: Shepherd
- ✅ Single source of truth for all configurations
- ✅ Complete version history with blame tracking
- ✅ One-click rollback to any previous state
- ✅ Environment-specific configuration management
- ✅ Visual diff tool to see exact changes

---

## 🎯 Quick Examples

### Create a Configuration
```bash
curl -X POST http://localhost:5000/api/config \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "config_id": "my-app",
    "app_name": "My Application",
    "environment": "production",
    "settings": {
      "database": "postgres://...",
      "cache": "redis://...",
      "features": {
        "new_ui": true,
        "beta_feature": false
      }
    }
  }'
```

### Get a Configuration
```bash
curl http://localhost:5000/api/config/my-app \
  -H "X-API-Key: YOUR_API_KEY"
```

### View History
```bash
curl http://localhost:5000/api/config/my-app/history \
  -H "X-API-Key: YOUR_API_KEY"
```

### Rollback
```bash
curl -X POST http://localhost:5000/api/config/my-app/rollback/2 \
  -H "X-API-Key: YOUR_API_KEY"
```

> 📚 [Full API Documentation](README.md#api-reference)

---

## 🖥️ Screenshots

### Dashboard
Clean, modern interface to manage all your configurations.

### Version History
See every change, who made it, and why.

### Visual Diff
Compare any two versions side-by-side with syntax highlighting.

### Easy Rollback
One button to restore any previous version.

---

## 🏗️ Architecture

```
┌─────────────┐
│   Web UI    │ ← Users
└─────┬───────┘
      │
┌─────▼────────┐
│ Flask App    │ ← REST API
│ (Python 3.12)│
└─────┬────────┘
      │
┌─────▼────────┐
│  MongoDB 7.0 │ ← Data Storage
│ (Versioning) │
└──────────────┘
```

**Technologies:**
- **Backend:** Python 3.12 + Flask
- **Database:** MongoDB 7.0 (with versioning)
- **Frontend:** Pico CSS + Vanilla JS
- **Deployment:** Docker + Kubernetes
- **Monitoring:** Prometheus + Grafana

---

## 📦 Deployment Options

### Local Development
```bash
./setup-local.sh
# Simple, standalone MongoDB
# Perfect for development and testing
```

### Docker Compose (Production-like)
```bash
docker-compose up -d
# 3-node MongoDB replica set
# High availability setup
```

### Kubernetes (Production)
```bash
helm install shepherd ./helm/shepherd
# Full production deployment
# Auto-scaling, monitoring, backups
```

> 📖 [Deployment Guide](docs/deployment-guide.md) | [Kubernetes Setup](helm/shepherd/README.md) | [AWS Terraform](terraform/aws/README.md)

---

## 🔐 Security

- ✅ Role-based access control (Viewer, Editor, Admin)
- ✅ API key authentication
- ✅ Session management
- ✅ Secure password hashing
- ✅ MongoDB authentication
- ✅ TLS/SSL support
- ✅ Security scanning in CI/CD

---

## 📊 Monitoring & Observability

- **Structured Logging** - JSON logs with request correlation
- **Prometheus Metrics** - HTTP requests, database ops, custom metrics
- **Health Checks** - `/api/health` endpoint
- **Webhooks** - Real-time notifications on changes
- **Audit Trail** - Complete history of all changes

> 📈 [Monitoring Guide](README.md#-observability--monitoring)

---

## 🧪 Quality Assurance

- ✅ **65 Unit Tests** - Comprehensive test coverage
- ✅ **CI/CD Pipeline** - Automated testing on every commit
- ✅ **Code Quality** - Linting with flake8 and black
- ✅ **Security Scanning** - Bandit + Safety checks
- ✅ **Coverage Reports** - Track code coverage

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [GETTING-STARTED.md](GETTING-STARTED.md) | Complete beginner's guide |
| [QUICKSTART.md](QUICKSTART.md) | Step-by-step tutorial |
| [DOCUMENTATION.md](DOCUMENTATION.md) | Full documentation index |
| [README.md](README.md) | Technical documentation |
| [API Reference](README.md#api-reference) | REST API documentation |
| [Deployment Guide](docs/deployment-guide.md) | Production deployment |
| [Troubleshooting](docs/troubleshooting-deployments.md) | Common issues & fixes |

---

## 🛠️ Common Commands

```bash
# Start services
./setup-local.sh                                    # Automated setup
docker-compose -f docker-compose.local.yml up -d    # Manual start

# View logs
docker-compose -f docker-compose.local.yml logs -f app

# Run tests
pytest test_shepherd.py -v --cov

# Stop services
docker-compose -f docker-compose.local.yml down

# Update to latest
git pull && docker-compose -f docker-compose.local.yml up -d --build
```

---

## 🤝 Contributing

We welcome contributions! Here's how:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`pytest test_shepherd.py`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

> 📖 [Full Contributing Guidelines](CONTRIBUTING.md) (coming soon)

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with [Flask](https://flask.palletsprojects.com/)
- Styled with [Pico CSS](https://picocss.com/)
- Powered by [MongoDB](https://www.mongodb.com/)
- Monitored by [Prometheus](https://prometheus.io/)

---

## 📞 Support

- 📖 [Documentation](DOCUMENTATION.md)
- 🐛 [Report a Bug](https://github.com/Kasa1905/Shepherd/issues)
- 💡 [Request a Feature](https://github.com/Kasa1905/Shepherd/issues)
- ❓ [Ask a Question](https://github.com/Kasa1905/Shepherd/discussions)

---

## ⭐ Star History

If you find Shepherd useful, please consider starring the repository!

---

<p align="center">
  <b>Made with ❤️ by the Shepherd team</b><br>
  <sub>Configuration management made simple</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/github/stars/Kasa1905/Shepherd?style=social" alt="GitHub stars">
  <img src="https://img.shields.io/github/forks/Kasa1905/Shepherd?style=social" alt="GitHub forks">
  <img src="https://img.shields.io/github/watchers/Kasa1905/Shepherd?style=social" alt="GitHub watchers">
</p>

---

**Happy Configuring! 🐑🚀**
