#!/usr/bin/env bash
# ─────────────────────────────────────────────────────
# OpenMRS 3.0 Reference Application — Setup Script
# Works on: Linux, macOS, Windows (Git Bash / WSL / Cygwin)
# ─────────────────────────────────────────────────────
set -euo pipefail

# ── Configurable defaults ───────────────────────────
REPO_URL="${REPO_URL:-https://github.com/arunkumar-reddy/openmrs-distro-referenceapplication.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/openmrs}"
ENV_FILE="${INSTALL_DIR}/.env"

# ── Colors ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[FAIL]${NC}  $*"; }

# ── Pre-flight checks ──────────────────────────────
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v git &>/dev/null; then
        log_error "git is not installed. Please install git first."
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        log_error "docker is not installed. Please install Docker Desktop or Docker Engine first."
        exit 1
    fi

    if ! docker compose version &>/dev/null; then
        log_error "docker compose plugin is not available. Please install Docker Compose V2."
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi

    log_ok "All prerequisites met."
}

# ── Step 1: Clone or update the repo ────────────────
clone_or_update_repo() {
    if [ -d "${INSTALL_DIR}/.git" ]; then
        log_info "Repository already exists at ${INSTALL_DIR}. Pulling latest changes..."
        cd "${INSTALL_DIR}"

        # Preserve .env and credentials — they are .gitignored
        if git status --porcelain .env credentials/ | grep -q '^'; then
            log_warn "Untracked local files detected (.env, credentials/). They will be preserved."
        fi

        git stash 2>/dev/null || true
        git pull --rebase
    else
        log_info "Cloning repository to ${INSTALL_DIR}..."
        mkdir -p "$(dirname "${INSTALL_DIR}")"
        git clone "${REPO_URL}" "${INSTALL_DIR}"
        log_ok "Clone complete."
    fi

    cd "${INSTALL_DIR}"
}

# ── Step 2: Verify .env exists ──────────────────────
check_env_file() {
    if [ ! -f "${ENV_FILE}" ]; then
        log_error ".env file not found at ${ENV_FILE}"
        echo ""
        echo "  The .env file in the project root contains sensitive credentials"
        echo "  (database passwords, Google Drive keys, etc.) and must be provided"
        echo "  manually — it is not generated automatically."
        echo ""
        echo "  Create it with:"
        echo "    cp .env.example .env"
        echo "  or manually create ~/.openmrs/.env (or your INSTALL_DIR/.env)"
        echo "  with the required variables."
        echo ""
        exit 1
    fi
    log_ok ".env file found."
}

# ── Step 3: Validate Google Drive credentials (if enabled) ──
check_gdrive_credentials() {
    local gdrive_enabled
    gdrive_enabled=$(grep -E '^GDRIVE_ENABLED=' "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]"')

    if [ "${gdrive_enabled}" = "true" ]; then
        # Credentials path is relative to .env / project root
        local cred_path="${INSTALL_DIR}/credentials/srinivasa-hospital.json"

        if [ ! -f "${cred_path}" ]; then
            log_error "Google Drive is enabled but credentials file not found."
            echo ""
            echo "  Expected: ${cred_path}"
            echo "  Set GDRIVE_ENABLED=false in .env to disable Google Drive backups."
            echo ""
            exit 1
        fi
        log_ok "Google Drive credentials verified: ${cred_path}"
    fi
}

# ── Step 4: Stop existing containers (update scenario) ──
stop_existing_containers() {
    cd "${INSTALL_DIR}"

    # Check if any containers from this compose project are running
    if docker compose ps --services --filter "status=running" &>/dev/null; then
        log_info "Stopping existing containers (preserving volumes)..."
        docker compose down
        log_ok "Existing containers stopped. Volumes preserved."
    else
        log_info "No running containers found. First-time setup."
    fi
}

# ── Step 5: Build custom images (optional) ──────────
build_custom_images() {
    cd "${INSTALL_DIR}"
    local build_backend="${BUILD_BACKEND:-false}"
    local build_frontend="${BUILD_FRONTEND:-false}"

    if [ "${build_backend}" = "true" ]; then
        log_info "Building custom backend image..."
        docker build -t openmrs/backend:custom .
        log_ok "Backend image built."
    fi

    if [ "${build_frontend}" = "true" ]; then
        log_info "Building custom frontend image..."
        docker build -t openmrs/frontend:custom ./frontend \
            --build-arg NPM_TOKEN="${NPM_TOKEN:-}"
        log_ok "Frontend image built."
    fi
}

# ── Step 6: Pull latest images ──────────────────────
pull_latest_images() {
    cd "${INSTALL_DIR}"
    log_info "Pulling latest container images..."
    docker compose pull --ignore-buildable 2>/dev/null || true
    log_ok "Images pulled."
}

# ── Step 7: Start all services ──────────────────────
start_services() {
    cd "${INSTALL_DIR}"
    log_info "Starting all services with docker compose up -d..."
    docker compose up -d

    log_ok "Services started!"
    echo ""
    log_info "Waiting for services to become healthy..."
    wait_for_healthy
}

# ── Helper: Wait for key services to be healthy ─────
get_container_health() {
    # Get the health status of a docker service container
    local container_name
    container_name=$(docker compose ps --format "{{.Name}}:{{.Status}}" 2>/dev/null | grep "^${1}" | head -1 | cut -d: -f2- || echo "")
    if echo "$container_name" | grep -q "healthy"; then
        echo "healthy"
    elif echo "$container_name" | grep -q "unhealthy"; then
        echo "unhealthy"
    elif echo "$container_name" | grep -q "Up"; then
        echo "running"
    else
        echo "starting"
    fi
}

wait_for_healthy() {
    local max_wait=300  # 5 minutes
    local interval=5
    local elapsed=0
    local services=(db backend frontend gateway)

    while [ $elapsed -lt $max_wait ]; do
        local all_ready=true

        for service in "${services[@]}"; do
            local status
            status=$(get_container_health "$service")

            case "${status}" in
                healthy|running) ;;  # good
                unhealthy) all_ready=false ;;
                *) all_ready=false ;;
            esac
        done

        if [ "$all_ready" = true ]; then
            break
        fi

        log_info "  Waiting for services... (${elapsed}s / ${max_wait}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    print_status
}

# ── Print final status ──────────────────────────────
print_status() {
    log_ok "All services started successfully!"
    echo ""
    echo "  Gateway URL : http://localhost"
    echo "  OpenMRS URL : http://localhost/openmrs"
    echo ""
    echo "  Default login:"
    echo "    Username: admin"
    echo "    Password: Admin123"
    echo ""
    echo "  Useful commands (run from ${INSTALL_DIR}):"
    echo "    docker compose logs -f         # View logs"
    echo "    docker compose ps              # Service status"
    echo "    docker compose down            # Stop (keeps data)"
    echo "    docker compose down --volumes   # Stop and DELETE data"
    echo ""
}

# ── Print data preservation note ─────────────────────
print_data_note() {
    echo ""
    log_info "Data Preservation:"
    echo "  - Database data  → Docker named volume 'db-data'"
    echo "  - OpenMRS files  → Docker named volume 'openmrs-data'"
    echo "  - Backups        → Local directory './backups'"
    echo "  These persist across updates and container restarts."
    echo ""
}

# ── Usage ────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install or update the OpenMRS 3.0 Reference Application.

Options:
  --install-dir DIR     Installation directory (default: ~/openmrs)
  --repo URL            Git repository URL (default: official repo)
  --build-backend       Build custom backend image from Dockerfile
  --build-frontend      Build custom frontend image from ./frontend/Dockerfile
  --skip-build          Skip building (use pre-built images only)
  --help                Show this help message

Environment Variables:
  REPO_URL              Git repository URL
  INSTALL_DIR           Installation directory
  BUILD_BACKEND=true    Build custom backend image
  BUILD_FRONTEND=true   Build custom frontend image
  NPM_TOKEN             NPM token for frontend build (private packages)

Examples:
  # Fresh install (fresh clone + start)
  ./setup.sh

  # Update existing installation (preserves data)
  cd ~/openmrs && ./scripts/setup.sh --install-dir .

  # Build custom backend too
  ./setup.sh --build-backend

  # Custom directory
  ./setup.sh --install-dir /opt/openmrs
EOF
}

# ── Parse arguments ──────────────────────────────────
main() {
    local do_build_backend=false
    local do_build_frontend=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-dir)
                INSTALL_DIR="$2"; shift 2 ;;
            --repo)
                REPO_URL="$2"; shift 2 ;;
            --build-backend)
                do_build_backend=true; shift ;;
            --build-frontend)
                do_build_frontend=true; shift ;;
            --skip-build)
                shift ;;  # no-op (default is skip)
            --help)
                usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    export BUILD_BACKEND="${do_build_backend}"
    export BUILD_FRONTEND="${do_build_frontend}"

    echo "╔═══════════════════════════════════════════════════╗"
    echo "║   OpenMRS 3.0 Reference Application Setup        ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    clone_or_update_repo
    check_env_file
    check_gdrive_credentials
    stop_existing_containers

    if [ "${do_build_backend}" = "true" ] || [ "${do_build_frontend}" = "true" ]; then
        build_custom_images
    else
        pull_latest_images
    fi

    start_services
    print_data_note
}

main "$@"
