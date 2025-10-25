# 🚀 Quick Start Guide - Shepherd CMS

Get Shepherd Configuration Management System running on your local machine in **5 minutes**!

## 📋 Prerequisites

Before you begin, make sure you have:

- **Docker Desktop** installed ([Download here](https://www.docker.com/products/docker-desktop))
  - Windows: Docker Desktop for Windows
  - Mac: Docker Desktop for Mac  
  - Linux: Docker Engine + Docker Compose
- At least **2GB of free RAM**
- At least **1GB of free disk space**

> **Note:** Docker Desktop includes both Docker and Docker Compose, so you only need one installation!

---

## ⚡ Super Quick Start (One Command!)

### For Mac/Linux:
```bash
./setup-local.sh
```

### For Windows:
```cmd
setup-local.bat
```

**That's it!** The script will automatically:
1. Check if Docker is installed and running
2. Set up the environment
3. Build and start the application
4. Open it in your browser

Skip to the [Access the Application](#-access-the-application) section below!

---

## 🔧 Manual Setup (If you want more control)

### Step 1: Clone or Download

If you haven't already, get the code:
```bash
git clone https://github.com/Kasa1905/Shepherd.git
cd Shepherd
```

Or download and extract the ZIP file, then navigate to the folder.

### Step 2: Start Docker Desktop

Make sure Docker Desktop is running:
- **Windows/Mac**: Check your system tray/menu bar for the Docker icon
- **Linux**: Run `sudo systemctl start docker`

### Step 3: Start Shepherd

Choose one option:

#### Option A: Simple Development Mode (Recommended for beginners)
```bash
docker-compose -f docker-compose.local.yml up -d
```

#### Option B: Production-like Mode (Advanced)
```bash
docker-compose up -d
```

### Step 4: Wait for Startup

The application takes 30-60 seconds to start. You can watch the logs:
```bash
docker-compose -f docker-compose.local.yml logs -f app
```

Press `Ctrl+C` to stop viewing logs (containers keep running).

---

## 🌐 Access the Application

Once started, open your browser and go to:

**http://localhost:5000**

### Default Login Credentials
- **Username:** `admin`
- **Password:** `admin123`

> ⚠️ **Important:** Change these credentials after first login! (Go to User Settings)

---

## 📖 What Can You Do?

### 1. Create Your First Configuration

1. Click **"Create New Configuration"**
2. Fill in the form:
   - **Config ID**: `my-app-config`
   - **App Name**: `My Application`
   - **Environment**: `development`
   - **Settings**: Add your JSON configuration
3. Click **"Create"**

### 2. View All Configurations

- Click **"Dashboard"** to see all your configurations
- Filter by environment, app name, or search

### 3. Update a Configuration

1. Find your configuration in the dashboard
2. Click **"Edit"**
3. Modify the settings
4. Add a change note (optional but recommended)
5. Click **"Update"**

### 4. View Version History

- Click on any configuration
- Click **"History"** tab to see all versions
- Click **"Compare"** to see differences between versions

### 5. Rollback to a Previous Version

1. Open a configuration's history
2. Find the version you want to restore
3. Click **"Rollback"** next to that version
4. Confirm the rollback

---

## 🔌 API Access

Shepherd also provides a REST API for programmatic access:

### Get API Key
1. Log in to the web UI
2. Go to **User Settings** → **API Keys**
3. Click **"Generate New API Key"**
4. Copy the key (you'll need it for API calls)

### Example API Calls

```bash
# Get all configurations
curl -H "X-API-Key: YOUR_API_KEY" http://localhost:5000/api/config

# Get specific configuration
curl -H "X-API-Key: YOUR_API_KEY" http://localhost:5000/api/config/my-app-config

# Create new configuration
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "config_id": "api-test",
    "app_name": "API Test App",
    "environment": "development",
    "settings": {"key": "value"}
  }' \
  http://localhost:5000/api/config
```

Full API documentation: http://localhost:5000/api/docs

---

## 🛠️ Common Commands

### View Logs
```bash
# All services
docker-compose -f docker-compose.local.yml logs -f

# Just the app
docker-compose -f docker-compose.local.yml logs -f app

# Just MongoDB
docker-compose -f docker-compose.local.yml logs -f mongodb
```

### Stop Shepherd
```bash
docker-compose -f docker-compose.local.yml down
```

### Stop and Remove All Data
```bash
docker-compose -f docker-compose.local.yml down -v
```
> ⚠️ **Warning:** This deletes all configurations! Use with caution.

### Restart Services
```bash
docker-compose -f docker-compose.local.yml restart
```

### Check Service Status
```bash
docker-compose -f docker-compose.local.yml ps
```

---

## 🐛 Troubleshooting

### "Cannot connect to Docker daemon"
- Make sure Docker Desktop is running
- On Linux, run: `sudo systemctl start docker`
- Try restarting Docker Desktop

### "Port 5000 already in use"
Option 1: Stop whatever is using port 5000
```bash
# Find what's using the port
lsof -i :5000        # Mac/Linux
netstat -ano | findstr :5000   # Windows

# Kill that process or change Shepherd's port in .env:
PORT=5001
```

### "Port 27017 already in use"
You have another MongoDB running. Either:
- Stop your existing MongoDB
- Change the MongoDB port in `docker-compose.local.yml`

### Application won't start / Health check fails
1. Check logs: `docker-compose -f docker-compose.local.yml logs app`
2. Make sure MongoDB is healthy: `docker-compose -f docker-compose.local.yml ps`
3. Try restarting: `docker-compose -f docker-compose.local.yml restart`

### "Permission denied" on Linux
Run with sudo or add your user to the docker group:
```bash
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

### Still having issues?
1. Stop everything: `docker-compose -f docker-compose.local.yml down`
2. Remove volumes: `docker volume rm shepherd-mongodb-data`
3. Start fresh: `./setup-local.sh`

---

## 🎯 Next Steps

### Learn More
- Read the [full README](README.md) for detailed information
- Check out the [deployment guide](docs/deployment-guide.md)
- Explore [backup procedures](docs/backup-procedures.md)

### Configure for Production
- Change default passwords in `.env`
- Set up proper authentication
- Configure webhooks for notifications
- Enable SSL/TLS
- Set up automated backups

### Integrate with Your Apps
- Use the REST API to fetch configurations
- Set up webhooks to get notified of changes
- Export configurations in different formats

---

## 💡 Tips & Tricks

### Use Environment Variables
Create a `.env` file to customize settings:
```bash
# Copy the example file
cp .env.example .env

# Edit it with your preferred settings
nano .env  # or use any text editor
```

### Keyboard Shortcuts (Web UI)
- `Ctrl/Cmd + K`: Quick search
- `Ctrl/Cmd + N`: New configuration
- `Esc`: Close modals

### Backup Your Data
```bash
# Backup MongoDB data
docker exec shepherd-mongodb mongodump --out=/tmp/backup
docker cp shepherd-mongodb:/tmp/backup ./backup-$(date +%Y%m%d)
```

### View Metrics
Shepherd exposes Prometheus metrics at:
**http://localhost:5000/metrics**

Great for monitoring and alerting!

---

## 📞 Get Help

- **Issues**: [GitHub Issues](https://github.com/Kasa1905/Shepherd/issues)
- **Documentation**: [Full Docs](README.md)
- **Email**: support@shepherd-cms.com (if available)

---

## 🎉 You're All Set!

Enjoy using Shepherd CMS! 🐑

If you find it useful, consider:
- ⭐ Starring the repository
- 🐛 Reporting bugs
- 💡 Suggesting features
- 📖 Improving documentation

Happy configuring! 🚀
