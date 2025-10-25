# 🎯 Quick Setup for Local Use

> **Want to get Shepherd running on your PC in minutes? You're in the right place!**

## For Complete Beginners

### What You Need
1. **Docker Desktop** - [Download it here](https://www.docker.com/products/docker-desktop)
   - Windows users: Get Docker Desktop for Windows
   - Mac users: Get Docker Desktop for Mac
   - Linux users: Install Docker Engine

2. That's it! Everything else is included.

### How to Start

#### Option 1: Automatic Setup (Easiest!)

**On Windows:**
1. Double-click `setup-local.bat`
2. Wait 1-2 minutes
3. Your browser will open automatically

**On Mac/Linux:**
1. Open Terminal in the Shepherd folder
2. Run: `./setup-local.sh`
3. Wait 1-2 minutes
4. Your browser will open automatically

#### Option 2: Manual Setup (If you prefer commands)

1. Open Terminal (Mac/Linux) or Command Prompt (Windows)
2. Navigate to the Shepherd folder
3. Run this command:
   ```bash
   docker-compose -f docker-compose.local.yml up -d
   ```
4. Wait 1-2 minutes for everything to start
5. Open your browser and go to: http://localhost:5000

### First Time Login

When the app opens in your browser:
- **Username:** `admin`
- **Password:** `admin123`

⚠️ **Important:** Change this password after you log in! (Go to Settings → Change Password)

### What Can You Do?

Once logged in, you can:
- ✅ Create configuration files for your apps
- ✅ Keep track of all changes (version history)
- ✅ Compare different versions
- ✅ Roll back to previous versions if needed
- ✅ Access configurations via REST API

### How to Stop Shepherd

When you're done:
```bash
docker-compose -f docker-compose.local.yml down
```

Or just close Docker Desktop (it will stop everything).

### Need Help?

- 📖 **Detailed Guide:** Read [QUICKSTART.md](QUICKSTART.md)
- 🐛 **Having Issues?** Check the [Troubleshooting](#troubleshooting) section
- 💬 **Questions?** Open an issue on GitHub

---

## For Developers

### Run with Auto-Reload (Development Mode)

```bash
# Create .env file
cp .env.example .env

# Start with hot-reload
docker-compose -f docker-compose.local.yml up --build

# Or run locally without Docker
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

### Run Tests

```bash
# With Docker
docker-compose -f docker-compose.local.yml exec app pytest

# Locally
pytest test_shepherd.py -v --cov
```

### View Logs

```bash
# All logs
docker-compose -f docker-compose.local.yml logs -f

# Just app logs
docker-compose -f docker-compose.local.yml logs -f app
```

---

## Troubleshooting

### "Cannot connect to Docker daemon"
- Make sure Docker Desktop is running
- Look for the Docker whale icon in your system tray/menu bar

### "Port 5000 already in use"
Another app is using port 5000. Either:
- Stop that app, or
- Edit `.env` and change `PORT=5000` to `PORT=5001`

### "MongoDB connection failed"
- Wait 30 seconds and try again (MongoDB takes time to start)
- Check logs: `docker-compose -f docker-compose.local.yml logs mongodb`

### App won't start
1. Stop everything: `docker-compose -f docker-compose.local.yml down`
2. Remove old data: `docker volume rm shepherd-mongodb-data`
3. Start fresh: `./setup-local.sh`

### Still stuck?
1. Check the detailed [QUICKSTART.md](QUICKSTART.md) guide
2. Look at [docs/troubleshooting-deployments.md](docs/troubleshooting-deployments.md)
3. Open an issue with your error message

---

## Next Steps

Once you have Shepherd running:

1. **Read the Full Documentation:** [README.md](README.md)
2. **Learn the API:** Check out the API examples below
3. **Configure for Your Needs:** Edit the `.env` file
4. **Set Up Production:** See [docs/deployment-guide.md](docs/deployment-guide.md)

Enjoy using Shepherd! 🐑
