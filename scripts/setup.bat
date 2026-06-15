@echo off
REM ────────────────────────────────────────────────────────────
REM OpenMRS 3.0 Reference Application — Setup Script (Windows)
REM Run from: Git Bash, WSL, or any bash-compatible shell,
REM OR directly in cmd.exe / PowerShell (this .bat version)
REM ────────────────────────────────────────────────────────────
setlocal EnableDelayedExpansion

set "REPO_URL=%REPO_URL%"
if not defined REPO_URL set "REPO_URL=https://github.com/arunkumar-reddy/openmrs-distro-referenceapplication.git"
set "INSTALL_DIR=%INSTALL_DIR%"
if not defined INSTALL_DIR set "INSTALL_DIR=%USERPROFILE%\openmrs"

echo.
echo ================================================
echo  OpenMRS 3.0 Reference Application Setup
echo ================================================
echo.

REM --- Pre-flight checks ---
echo [INFO] Checking prerequisites...

where git >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] git is not installed. Please install Git for Windows first.
    exit /b 1
)

where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] docker is not installed. Please install Docker Desktop first.
    exit /b 1
)

docker compose version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] docker compose plugin is not available. Please install Docker Compose V2.
    exit /b 1
)

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Docker daemon is not running. Please start Docker Desktop.
    exit /b 1
)

echo [ OK ] All prerequisites met.
echo.

REM --- Clone or update repo ---
if exist "%INSTALL_DIR%\.git" (
    echo [INFO] Repository already exists. Pulling latest changes...
    cd /d "%INSTALL_DIR%"
    git pull --rebase
) else (
    echo [INFO] Cloning repository to %INSTALL_DIR%...
    git clone "%REPO_URL%" "%INSTALL_DIR%"
    echo [ OK ] Clone complete.
    cd /d "%INSTALL_DIR%"
)

REM --- Verify .env exists ---
if not exist "%INSTALL_DIR%\.env" (
    echo [FAIL] .env file not found at %INSTALL_DIR%\.env
    echo.
    echo   The .env file in the project root contains sensitive credentials
    echo   ^(database passwords, Google Drive keys, etc.^) and must be provided
    echo   manually — it is not generated automatically.
    echo.
    echo   Create it with:
    echo     copy .env.example .env
    echo   or manually create %INSTALL_DIR%\.env
    echo   with the required variables.
    echo.
    exit /b 1
)
echo [ OK ] .env file found.
echo.

REM --- Stop existing containers ^(preserves volumes^) ---
echo [INFO] Checking for running containers...
docker compose ps --services --filter "status=running" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [INFO] Stopping existing containers ^(preserving volumes^)...
    docker compose down
    echo [ OK ] Existing containers stopped. Volumes preserved.
) else (
    echo [INFO] No running containers found. First-time setup.
)
echo.

REM --- Pull latest images ---
echo [INFO] Pulling latest container images...
docker compose pull --ignore-buildable 2>nul || (
    docker compose pull 2>nul || echo [WARN] Some images could not be pulled.
)
echo [ OK ] Images pulled.
echo.

REM --- Start services ---
echo [INFO] Starting all services...
docker compose up -d
echo.
echo [ OK ] Services started!
echo.
echo   Gateway URL : http://localhost
echo   OpenMRS URL : http://localhost/openmrs
echo.
echo   Default login:
echo     Username: admin
echo     Password: Admin123
echo.
echo   Useful commands ^(run from %INSTALL_DIR%^):
echo     docker compose logs -f          ^> View logs
echo     docker compose ps               ^> Service status
echo     docker compose down             ^> Stop ^(keeps data^)
echo     docker compose down --volumes   ^> Stop and DELETE data
echo.
echo   Data Preservation:
echo     - Database data  -^> Docker named volume 'db-data'
echo     - OpenMRS files  -^> Docker named volume 'openmrs-data'
echo     - Backups        -^> Local directory '.\backups'
echo     These persist across updates and restarts.
echo.
echo ================================================
echo  Setup complete!
echo ================================================
echo.
