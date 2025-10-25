@echo off
REM ==============================================================================
REM Shepherd CMS - Local Development Setup Script (Windows)
REM ==============================================================================
REM This script helps you get Shepherd running on your Windows machine quickly.
REM ==============================================================================

setlocal enabledelayedexpansion

echo.
echo ========================================================================
echo.
echo           Shepherd Configuration Management System
echo                   Local Development Setup
echo.
echo ========================================================================
echo.

REM Check for Docker
echo Checking prerequisites...
where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker is not installed!
    echo Please install Docker Desktop from: https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)
echo [OK] Docker found

REM Check for Docker Compose
where docker-compose >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    docker compose version >nul 2>nul
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Docker Compose is not installed!
        pause
        exit /b 1
    )
)
echo [OK] Docker Compose found

REM Check if Docker is running
docker info >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker daemon is not running!
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo [OK] Docker daemon is running
echo.

REM Setup environment file
if not exist .env (
    echo Creating .env file from template...
    if exist .env.example (
        copy .env.example .env >nul
        echo [OK] Created .env file
    ) else (
        echo [WARNING] .env.example not found, using defaults
    )
) else (
    echo [INFO] .env file already exists
)

REM Create logs directory
if not exist logs mkdir logs
echo [OK] Created logs directory

echo.
echo Choose deployment mode:
echo   1^) Simple Local Development ^(recommended for beginners^)
echo   2^) Production-like ^(with replica set^)
echo.
set /p mode="Enter choice [1-2] (default: 1): "
if "%mode%"=="" set mode=1

set COMPOSE_FILE=docker-compose.local.yml
if "%mode%"=="2" (
    set COMPOSE_FILE=docker-compose.yml
    echo [WARNING] Production mode requires additional setup steps
)

REM Stop existing containers
echo.
echo Stopping any existing Shepherd containers...
docker-compose -f %COMPOSE_FILE% down >nul 2>nul
docker-compose down >nul 2>nul
echo [OK] Cleanup complete

echo.
echo Building and starting Shepherd CMS...
echo.

REM Build and start containers
docker-compose -f %COMPOSE_FILE% up -d --build
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to start containers
    pause
    exit /b 1
)
echo [OK] Containers started successfully!

echo.
echo Waiting for services to be healthy...
timeout /t 5 /nobreak >nul

REM Wait for application
echo Waiting for application to start...
set COUNTER=0
:wait_loop
timeout /t 1 /nobreak >nul
curl -sf http://localhost:5000/api/health >nul 2>nul
if %ERRORLEVEL% EQU 0 goto :app_ready
set /a COUNTER+=1
if %COUNTER% LSS 30 goto :wait_loop

echo [WARNING] Application health check timed out
echo Check logs with: docker-compose -f %COMPOSE_FILE% logs app
goto :show_info

:app_ready
echo [OK] Application is ready!

:show_info
echo.
echo ========================================================================
echo                    Setup Complete!
echo ========================================================================
echo.
echo [SUCCESS] Shepherd CMS is now running!
echo.
echo Access Points:
echo   - Web UI:        http://localhost:5000
echo   - API:           http://localhost:5000/api
echo   - Health Check:  http://localhost:5000/api/health
echo   - Metrics:       http://localhost:5000/metrics
echo.
echo Default Login:
echo   - Username: admin
echo   - Password: admin123
echo   - WARNING: Change these in production!
echo.
echo Useful Commands:
echo   - View logs:         docker-compose -f %COMPOSE_FILE% logs -f
echo   - Stop services:     docker-compose -f %COMPOSE_FILE% down
echo   - Restart services:  docker-compose -f %COMPOSE_FILE% restart
echo   - View containers:   docker-compose -f %COMPOSE_FILE% ps
echo.

REM Open browser
echo Opening Shepherd in your browser...
timeout /t 2 /nobreak >nul
start http://localhost:5000

echo.
echo Setup script completed successfully!
echo.
pause
