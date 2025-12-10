#!/bin/bash
# =============================================================================
# Shared Library for Infrastructure Scripts
# =============================================================================
# Source this file in your scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
#
# Or with automatic path resolution:
#   source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# =============================================================================
# Colors
# =============================================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export PURPLE='\033[0;35m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[→]${NC} $1"
}

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_section() {
    echo ""
    echo -e "${CYAN}── $1 ──${NC}"
    echo ""
}

# =============================================================================
# Environment Detection
# =============================================================================

# Detect OS type
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       echo "unknown" ;;
    esac
}

# Get sed in-place command (differs between Linux and macOS)
get_sed_inplace() {
    if [[ "$(detect_os)" == "macos" ]]; then
        echo "sed -i ''"
    else
        echo "sed -i"
    fi
}

# Check if running in Docker
is_docker() {
    [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# =============================================================================
# Validation Functions
# =============================================================================

# Check if command exists
require_command() {
    local cmd=$1
    local install_hint=${2:-"Please install $cmd"}

    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed."
        log_error "$install_hint"
        exit 1
    fi
}

# Check if Docker is running
require_docker() {
    require_command "docker" "Install Docker: https://docs.docker.com/get-docker/"

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
}

# Check if file exists
require_file() {
    local file=$1
    local message=${2:-"Required file not found: $file"}

    if [[ ! -f "$file" ]]; then
        log_error "$message"
        exit 1
    fi
}

# Check if directory exists
require_dir() {
    local dir=$1
    local message=${2:-"Required directory not found: $dir"}

    if [[ ! -d "$dir" ]]; then
        log_error "$message"
        exit 1
    fi
}

# Validate environment variable is set
require_env() {
    local var_name=$1
    local message=${2:-"Environment variable $var_name is required"}

    if [[ -z "${!var_name:-}" ]]; then
        log_error "$message"
        exit 1
    fi
}

# =============================================================================
# Docker Helpers
# =============================================================================

# Wait for container to be healthy/running
wait_for_container() {
    local container=$1
    local timeout=${2:-60}
    local count=0

    log_step "Waiting for $container to be ready..."

    while [[ $count -lt $timeout ]]; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]; then
                local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
                if [[ "$status" == "running" ]]; then
                    log_info "$container is ready"
                    return 0
                fi
            fi
        fi
        sleep 1
        ((count++))
    done

    log_warn "$container may not be fully ready (timeout after ${timeout}s)"
    return 1
}

# Check if container is running
is_container_running() {
    local container=$1
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"
}

# Get container health status
get_container_health() {
    local container=$1
    if is_container_running "$container"; then
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
        if [[ "$health" == "none" ]]; then
            echo "running"
        else
            echo "$health"
        fi
    else
        echo "stopped"
    fi
}

# Execute command in container
docker_exec() {
    local container=$1
    shift
    docker exec "$container" "$@"
}

# Execute command in container interactively
docker_exec_it() {
    local container=$1
    shift
    docker exec -it "$container" "$@"
}

# =============================================================================
# Secret Generation
# =============================================================================

# Generate random password (base64, alphanumeric-safe)
generate_password() {
    local length=${1:-24}
    openssl rand -base64 $((length * 2)) | tr -d '\n/+=' | head -c "$length"
}

# Generate random hex token
generate_token() {
    local length=${1:-32}
    openssl rand -hex "$length"
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        openssl rand -hex 16 | sed 's/\(..\)/\1-/g;s/-$//'
    fi
}

# =============================================================================
# File Operations
# =============================================================================

# Create directory if not exists
ensure_dir() {
    local dir=$1
    [[ ! -d "$dir" ]] && mkdir -p "$dir"
}

# Backup file before modifying
backup_file() {
    local file=$1
    local backup_dir=${2:-"$(dirname "$file")"}
    local timestamp=$(date +%Y%m%d_%H%M%S)

    if [[ -f "$file" ]]; then
        cp "$file" "${backup_dir}/$(basename "$file").backup.${timestamp}"
    fi
}

# Load environment file
load_env() {
    local env_file=${1:-.env}

    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
        return 0
    fi
    return 1
}

# Create .env from .env.example if not exists
setup_env_from_example() {
    local dir=${1:-.}

    if [[ ! -f "$dir/.env" ]] && [[ -f "$dir/.env.example" ]]; then
        cp "$dir/.env.example" "$dir/.env"
        log_info "Created .env from .env.example"
        return 0
    fi
    return 1
}

# =============================================================================
# Network Helpers
# =============================================================================

# Check if port is available
is_port_available() {
    local port=$1
    ! (echo >/dev/tcp/localhost/$port) 2>/dev/null
}

# Wait for port to be available
wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-30}
    local count=0

    log_step "Waiting for $host:$port..."

    while [[ $count -lt $timeout ]]; do
        if nc -z "$host" "$port" 2>/dev/null || (echo >/dev/tcp/$host/$port) 2>/dev/null; then
            log_info "$host:$port is available"
            return 0
        fi
        sleep 1
        ((count++))
    done

    log_warn "$host:$port not available after ${timeout}s"
    return 1
}

# Create Docker network if not exists
ensure_network() {
    local network=$1
    if ! docker network inspect "$network" &>/dev/null; then
        docker network create "$network"
        log_info "Created network: $network"
    fi
}

# =============================================================================
# User Interaction
# =============================================================================

# Confirm action with user
confirm() {
    local message=${1:-"Continue?"}
    local default=${2:-"n"}

    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n] " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -p "$message [y/N] " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}

# Prompt for input with default
prompt() {
    local message=$1
    local default=$2
    local result

    if [[ -n "$default" ]]; then
        read -p "$message [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$message: " result
        echo "$result"
    fi
}

# Prompt for password (hidden input)
prompt_password() {
    local message=${1:-"Password"}
    local password

    read -sp "$message: " password
    echo ""
    echo "$password"
}

# =============================================================================
# Service Status Display
# =============================================================================

# Print service status line
print_service_status() {
    local name=$1
    local container=$2

    if is_container_running "$container"; then
        local health=$(get_container_health "$container")
        case "$health" in
            healthy)
                echo -e "  ${GREEN}●${NC} $name (healthy)"
                ;;
            unhealthy)
                echo -e "  ${RED}●${NC} $name (unhealthy)"
                ;;
            *)
                echo -e "  ${GREEN}●${NC} $name (running)"
                ;;
        esac
    else
        echo -e "  ${RED}○${NC} $name (stopped)"
    fi
}

# =============================================================================
# Authentication
# =============================================================================

# Get infra root for password file location
_get_auth_root() {
    local dir="$SCRIPT_DIR"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/setup.sh" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "$SCRIPT_DIR"
}

# Check if password is set
is_auth_configured() {
    local auth_root=$(_get_auth_root)
    [[ -f "$auth_root/.password_hash" ]]
}

# Require authentication (call at start of protected scripts)
require_auth() {
    local auth_root=$(_get_auth_root)
    local password_file="$auth_root/.password_hash"

    # Check if password is set
    if [[ ! -f "$password_file" ]]; then
        log_error "Password not configured"
        echo ""
        echo "    First time setup - run:"
        echo "    ./setup.sh --set-password"
        echo ""
        exit 1
    fi

    # Prompt for password (hidden input)
    echo -n "Enter admin password: "
    read -s input_password
    echo ""

    # Hash the input and compare
    local stored_hash=$(cat "$password_file")
    local input_hash=$(echo -n "$input_password" | sha256sum | cut -d' ' -f1)

    if [[ "$input_hash" != "$stored_hash" ]]; then
        log_error "Access denied: Wrong password"
        exit 1
    fi

    log_info "Authorized"
}

# Set or change password
set_auth_password() {
    local auth_root=$(_get_auth_root)
    local password_file="$auth_root/.password_hash"

    echo "Setting admin password for infrastructure management"
    echo ""

    # Get new password
    echo -n "Enter new password: "
    read -s password1
    echo ""

    echo -n "Confirm password: "
    read -s password2
    echo ""

    if [[ "$password1" != "$password2" ]]; then
        log_error "Passwords do not match"
        exit 1
    fi

    if [[ ${#password1} -lt 8 ]]; then
        log_error "Password must be at least 8 characters"
        exit 1
    fi

    # Store hash (not plain text)
    echo -n "$password1" | sha256sum | cut -d' ' -f1 > "$password_file"
    chmod 600 "$password_file"

    log_info "Password set successfully"
    echo ""
}

# =============================================================================
# Cleanup and Error Handling
# =============================================================================

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    # Override in your script if needed
    exit $exit_code
}

# Set up error handling
setup_error_handling() {
    set -euo pipefail
    trap cleanup EXIT
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if array contains element
array_contains() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Join array with delimiter
array_join() {
    local delimiter=$1
    shift
    local first=$1
    shift
    printf '%s' "$first" "${@/#/$delimiter}"
}

# Get script directory (call from your script)
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Get infra root directory
get_infra_root() {
    local script_dir=$(get_script_dir)
    # Navigate up until we find setup.sh
    local dir="$script_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/setup.sh" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}
