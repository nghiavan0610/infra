#!/bin/bash
# =============================================================================
# Infrastructure Master Setup Script
# =============================================================================
# One command to setup your entire infrastructure stack.
#
# Usage:
#   ./setup-all.sh              # Use services.conf
#   ./setup-all.sh --minimal    # Override: essential services only
#   ./setup-all.sh --standard   # Override: minimal + storage + security
#   ./setup-all.sh --all        # Override: everything
#
# Configuration:
#   Edit services.conf to enable/disable services
#
# Authorization:
#   1. Add allowed usernames to ALLOWED_USERS below
#   2. Create .auth_key file: openssl rand -hex 32 > .auth_key && chmod 600 .auth_key
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Authorization Check (Password Protected)
# =============================================================================
# To set/change password, run: ./setup-all.sh --set-password
#
# Password hash is stored in .password_hash file (gitignored)
# Even if someone can read the hash, they can't reverse it
# =============================================================================

check_authorization() {
    local password_file="$SCRIPT_DIR/.password_hash"

    # Check if password is set
    if [[ ! -f "$password_file" ]]; then
        echo -e "\033[0;31m[✗] Password not configured\033[0m"
        echo ""
        echo "    First time setup - run:"
        echo "    ./setup-all.sh --set-password"
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
        echo -e "\033[0;31m[✗] Access denied: Wrong password\033[0m"
        exit 1
    fi

    echo -e "\033[0;32m[✓] Authorized\033[0m"
}

set_password() {
    local password_file="$SCRIPT_DIR/.password_hash"

    echo "Setting admin password for infrastructure setup"
    echo ""

    # Get new password
    echo -n "Enter new password: "
    read -s password1
    echo ""

    echo -n "Confirm password: "
    read -s password2
    echo ""

    if [[ "$password1" != "$password2" ]]; then
        echo -e "\033[0;31m[✗] Passwords do not match\033[0m"
        exit 1
    fi

    if [[ ${#password1} -lt 8 ]]; then
        echo -e "\033[0;31m[✗] Password must be at least 8 characters\033[0m"
        exit 1
    fi

    # Store hash (not plain text)
    echo -n "$password1" | sha256sum | cut -d' ' -f1 > "$password_file"
    chmod 600 "$password_file"

    echo -e "\033[0;32m[✓] Password set successfully\033[0m"
    echo ""
    echo "You can now run: ./setup-all.sh"
}

# Handle --set-password
if [[ "${1:-}" == "--set-password" ]]; then
    set_password
    exit 0
fi

# Run authorization check (skip for --help)
if [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
    check_authorization
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }
log_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# Service Registry - Maps service names to directories
# =============================================================================
declare -A SERVICE_DIRS=(
    # All services now in services/ folder
    ["traefik"]="services/traefik"
    ["wireguard"]="services/wireguard"
    ["postgres"]="services/postgres"
    ["postgres-ha"]="services/postgres-ha"
    ["redis"]="services/redis"
    ["mongo"]="services/mongo"
    ["timescaledb"]="services/timescaledb"
    ["mysql"]="services/mysql"
    ["memcached"]="services/memcached"
    ["clickhouse"]="services/clickhouse"
    ["nats"]="services/nats"
    ["kafka"]="services/kafka"
    ["rabbitmq"]="services/rabbitmq"
    ["asynq"]="services/asynq"
    ["garage"]="services/garage"
    ["minio"]="services/minio"
    ["meilisearch"]="services/meilisearch"
    ["opensearch"]="services/opensearch"
    ["qdrant"]="services/qdrant"
    ["fail2ban"]="services/fail2ban"
    ["crowdsec"]="services/crowdsec"
    ["authentik"]="services/authentik"
    ["vault"]="services/vault"
    ["observability"]="services/observability"
    ["uptime-kuma"]="services/uptime-kuma"
    ["backup"]="services/backup"
    ["registry"]="services/registry"
    ["n8n"]="services/n8n"
    ["faster-whisper"]="services/faster-whisper"
    ["sentry"]="services/sentry"
    ["adminer"]="services/adminer"
    ["mailpit"]="services/mailpit"
    ["portainer"]="services/portainer"
    ["redisinsight"]="services/redisinsight"
    ["gitea"]="services/gitea"
    ["plausible"]="services/plausible"
    ["drone"]="services/drone"
    ["watchtower"]="services/watchtower"
    ["dozzle"]="services/dozzle"
    ["vaultwarden"]="services/vaultwarden"
    ["ntfy"]="services/ntfy"
    ["healthchecks"]="services/healthchecks"
    ["github-runner"]="services/github-runner"
    ["gitlab-runner"]="services/gitlab-runner"
    ["langfuse"]="services/langfuse"
)

# Container names (for health checks)
declare -A SERVICE_CONTAINERS=(
    ["traefik"]="traefik"
    ["wireguard"]="wireguard"
    ["postgres"]="postgres"
    ["postgres-ha"]="postgres-master"
    ["redis"]="redis"
    ["mongo"]="mongo"
    ["timescaledb"]="timescaledb"
    ["mysql"]="mysql"
    ["memcached"]="memcached"
    ["clickhouse"]="clickhouse"
    ["nats"]="nats"
    ["kafka"]="kafka"
    ["rabbitmq"]="rabbitmq"
    ["asynq"]="asynqmon"
    ["garage"]="garage"
    ["minio"]="minio"
    ["meilisearch"]="meilisearch"
    ["opensearch"]="opensearch"
    ["fail2ban"]="fail2ban"
    ["crowdsec"]="crowdsec"
    ["authentik"]="authentik-server"
    ["vault"]="vault"
    ["observability"]="grafana"
    ["uptime-kuma"]="uptime-kuma"
    ["registry"]="registry"
    ["n8n"]="n8n"
    ["faster-whisper"]="faster-whisper"
    ["sentry"]="sentry"
    ["adminer"]="adminer"
    ["mailpit"]="mailpit"
    ["portainer"]="portainer"
    ["redisinsight"]="redisinsight"
    ["gitea"]="gitea"
    ["plausible"]="plausible"
    ["drone"]="drone"
    ["watchtower"]="watchtower"
    ["dozzle"]="dozzle"
    ["vaultwarden"]="vaultwarden"
    ["ntfy"]="ntfy"
    ["healthchecks"]="healthchecks"
    ["backup"]="backup"
    ["github-runner"]="github-runner"
    ["gitlab-runner"]="gitlab-runner"
    ["langfuse"]="langfuse"
    ["qdrant"]="qdrant"
)

# Exporter ports for monitoring
declare -A SERVICE_EXPORTER_PORTS=(
    ["postgres"]="9187"
    ["postgres-ha"]="9187"
    ["redis"]="9121"
    ["mongo"]="9216"
    ["nats"]="7777"
    ["kafka"]="9308"
    ["rabbitmq"]="15692"
    ["traefik"]="8080"
    ["minio"]="9000"
    ["mysql"]="9104"
    ["memcached"]="9150"
    ["clickhouse"]="9363"
    ["qdrant"]="6333"
    ["langfuse"]="3000"
)

# Track installed services
declare -A INSTALLED_SERVICES
declare -A ENABLED_SERVICES

# Shared secrets
SHARED_POSTGRES_USER="postgres"
SHARED_POSTGRES_PASSWORD=""
SHARED_REDIS_PASSWORD=""
SHARED_MONGO_USER="admin"
SHARED_MONGO_PASSWORD=""
SHARED_GARAGE_ADMIN_TOKEN=""

# =============================================================================
# Configuration Loading
# =============================================================================

load_services_conf() {
    if [[ ! -f "$SCRIPT_DIR/services.conf" ]]; then
        log_error "services.conf not found. Creating default..."
        create_default_services_conf
    fi

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)

        # Remove inline comments and trim whitespace
        value=$(echo "$value" | cut -d'#' -f1 | xargs)

        if [[ "$value" == "true" ]]; then
            ENABLED_SERVICES["$key"]=true
        fi
    done < "$SCRIPT_DIR/services.conf"
}

create_default_services_conf() {
    cat > "$SCRIPT_DIR/services.conf" << 'EOF'
# Infrastructure Services Configuration
# Enable/disable services by setting to true/false

# Networking
traefik=true

# Databases
postgres=true
redis=true

# Storage
garage=true

# Security
fail2ban=true
crowdsec=true

# Monitoring
observability=true
uptime-kuma=true
backup=true
EOF
}

# =============================================================================
# Shared Secrets Management
# =============================================================================

generate_shared_secrets() {
    log_step "Generating shared secrets..."

    SHARED_POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
    SHARED_REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
    SHARED_MONGO_PASSWORD=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
    SHARED_GARAGE_ADMIN_TOKEN=$(openssl rand -hex 32)

    cat > "$SCRIPT_DIR/.secrets" << EOF
# Auto-generated shared secrets - $(date)
# DO NOT COMMIT THIS FILE

POSTGRES_USER=$SHARED_POSTGRES_USER
POSTGRES_PASSWORD=$SHARED_POSTGRES_PASSWORD
REDIS_PASSWORD=$SHARED_REDIS_PASSWORD
MONGO_USER=$SHARED_MONGO_USER
MONGO_PASSWORD=$SHARED_MONGO_PASSWORD
GARAGE_ADMIN_TOKEN=$SHARED_GARAGE_ADMIN_TOKEN
EOF
    chmod 600 "$SCRIPT_DIR/.secrets"
    log_info "Shared secrets saved to .secrets"
}

load_shared_secrets() {
    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        source "$SCRIPT_DIR/.secrets"
        SHARED_POSTGRES_PASSWORD=$POSTGRES_PASSWORD
        SHARED_REDIS_PASSWORD=$REDIS_PASSWORD
        SHARED_MONGO_PASSWORD=$MONGO_PASSWORD
        SHARED_GARAGE_ADMIN_TOKEN=$GARAGE_ADMIN_TOKEN
        log_info "Loaded existing secrets from .secrets"
        return 0
    fi
    return 1
}

# =============================================================================
# Helper Functions
# =============================================================================

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    log_info "Docker is ready"
}

check_linux_host_docker() {
    if [[ "$(uname)" == "Linux" ]]; then
        if ! grep -q "host.docker.internal" /etc/hosts 2>/dev/null; then
            log_warn "Adding host.docker.internal to /etc/hosts (requires sudo)"
            echo "172.17.0.1 host.docker.internal" | sudo tee -a /etc/hosts > /dev/null
            log_info "Added host.docker.internal"
        fi
    fi
}

wait_for_container() {
    local container=$1
    local timeout=${2:-60}
    local count=0

    while [[ $count -lt $timeout ]]; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]; then
                return 0
            fi
        fi
        sleep 1
        ((count++))
    done
    return 1
}

setup_env_file() {
    local service_dir=$1
    local service_name=$2

    cd "$SCRIPT_DIR/$service_dir"

    if [[ ! -f ".env" ]] && [[ -f ".env.example" ]]; then
        cp .env.example .env

        # Inject shared passwords based on service type
        if [[ "$(uname)" == "Darwin" ]]; then
            local SED_CMD="sed -i ''"
        else
            local SED_CMD="sed -i"
        fi

        case "$service_name" in
            postgres|postgres-ha)
                $SED_CMD "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${SHARED_POSTGRES_PASSWORD}|" .env
                $SED_CMD "s|^POSTGRES_USER=.*|POSTGRES_USER=${SHARED_POSTGRES_USER}|" .env
                ;;
            redis)
                $SED_CMD "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${SHARED_REDIS_PASSWORD}|" .env
                ;;
            mongo)
                $SED_CMD "s|^MONGO_ROOT_PASSWORD=.*|MONGO_ROOT_PASSWORD=${SHARED_MONGO_PASSWORD}|" .env
                $SED_CMD "s|^MONGO_ROOT_USER=.*|MONGO_ROOT_USER=${SHARED_MONGO_USER}|" .env
                ;;
            garage)
                $SED_CMD "s|^GARAGE_ADMIN_TOKEN=.*|GARAGE_ADMIN_TOKEN=${SHARED_GARAGE_ADMIN_TOKEN}|" .env
                ;;
            observability)
                local GRAFANA_PASS=$(openssl rand -base64 16 | tr -d '\n')
                $SED_CMD "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASS}|" .env
                ;;
            asynq)
                $SED_CMD "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${SHARED_REDIS_PASSWORD}|" .env
                ;;
            sentry)
                local SENTRY_KEY=$(openssl rand -hex 32)
                $SED_CMD "s|^SENTRY_SECRET_KEY=.*|SENTRY_SECRET_KEY=${SENTRY_KEY}|" .env
                $SED_CMD "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${SHARED_POSTGRES_PASSWORD}|" .env
                $SED_CMD "s|^POSTGRES_USER=.*|POSTGRES_USER=${SHARED_POSTGRES_USER}|" .env
                $SED_CMD "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${SHARED_REDIS_PASSWORD}|" .env
                ;;
            mysql)
                local MYSQL_ROOT_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                local MYSQL_USER_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                $SED_CMD "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}|" .env
                $SED_CMD "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${MYSQL_USER_PASS}|" .env
                ;;
            clickhouse)
                local CH_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                $SED_CMD "s|^CLICKHOUSE_PASSWORD=.*|CLICKHOUSE_PASSWORD=${CH_PASS}|" .env
                ;;
            gitea)
                local GITEA_SECRET=$(openssl rand -hex 32)
                local GITEA_TOKEN=$(openssl rand -hex 32)
                local GITEA_DB_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                $SED_CMD "s|^GITEA_SECRET_KEY=.*|GITEA_SECRET_KEY=${GITEA_SECRET}|" .env
                $SED_CMD "s|^GITEA_INTERNAL_TOKEN=.*|GITEA_INTERNAL_TOKEN=${GITEA_TOKEN}|" .env
                $SED_CMD "s|^GITEA_DB_PASSWORD=.*|GITEA_DB_PASSWORD=${GITEA_DB_PASS}|" .env
                ;;
            plausible)
                local PLAUSIBLE_SECRET=$(openssl rand -base64 48)
                local PLAUSIBLE_TOTP=$(openssl rand -base64 32)
                local PLAUSIBLE_DB_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                $SED_CMD "s|^PLAUSIBLE_SECRET_KEY=.*|PLAUSIBLE_SECRET_KEY=${PLAUSIBLE_SECRET}|" .env
                $SED_CMD "s|^PLAUSIBLE_TOTP_KEY=.*|PLAUSIBLE_TOTP_KEY=${PLAUSIBLE_TOTP}|" .env
                $SED_CMD "s|^PLAUSIBLE_DB_PASSWORD=.*|PLAUSIBLE_DB_PASSWORD=${PLAUSIBLE_DB_PASS}|" .env
                ;;
            drone)
                local DRONE_RPC=$(openssl rand -hex 16)
                $SED_CMD "s|^DRONE_RPC_SECRET=.*|DRONE_RPC_SECRET=${DRONE_RPC}|" .env
                ;;
            vaultwarden)
                local VW_ADMIN_TOKEN=$(openssl rand -base64 48)
                $SED_CMD "s|^VAULTWARDEN_ADMIN_TOKEN=.*|VAULTWARDEN_ADMIN_TOKEN=${VW_ADMIN_TOKEN}|" .env
                ;;
            healthchecks)
                local HC_SECRET=$(openssl rand -base64 32)
                local HC_DB_PASS=$(openssl rand -hex 16)
                $SED_CMD "s|^HEALTHCHECKS_SECRET_KEY=.*|HEALTHCHECKS_SECRET_KEY=${HC_SECRET}|" .env
                $SED_CMD "s|^HEALTHCHECKS_DB_PASSWORD=.*|HEALTHCHECKS_DB_PASSWORD=${HC_DB_PASS}|" .env
                ;;
            langfuse)
                local LF_SECRET=$(openssl rand -base64 32)
                local LF_SALT=$(openssl rand -base64 32)
                local LF_DB_PASS=$(openssl rand -base64 24 | tr -d '\n' | head -c 24)
                $SED_CMD "s|^LANGFUSE_NEXTAUTH_SECRET=.*|LANGFUSE_NEXTAUTH_SECRET=${LF_SECRET}|" .env
                $SED_CMD "s|^LANGFUSE_SALT=.*|LANGFUSE_SALT=${LF_SALT}|" .env
                $SED_CMD "s|^LANGFUSE_DB_PASS=.*|LANGFUSE_DB_PASS=${LF_DB_PASS}|" .env
                $SED_CMD "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${SHARED_POSTGRES_PASSWORD}|" .env
                ;;
            github-runner)
                # GitHub runner needs manual token configuration
                log_warn "GitHub Runner requires manual configuration:"
                log_warn "  1. Get token from GitHub repo → Settings → Actions → Runners"
                log_warn "  2. Set GITHUB_RUNNER_TOKEN in services/github-runner/.env"
                ;;
            gitlab-runner)
                # GitLab runner needs manual registration
                log_warn "GitLab Runner requires manual registration:"
                log_warn "  Run: cd services/gitlab-runner && docker compose run --rm gitlab-runner register"
                ;;
        esac
    fi

    cd "$SCRIPT_DIR"
}

# =============================================================================
# Service Management
# =============================================================================

start_service() {
    local service_name=$1
    local service_dir=${SERVICE_DIRS[$service_name]}
    local container=${SERVICE_CONTAINERS[$service_name]}

    if [[ -z "$service_dir" ]] || [[ ! -d "$SCRIPT_DIR/$service_dir" ]]; then
        log_warn "Service directory not found: $service_name"
        return 1
    fi

    log_step "Starting $service_name..."

    # Setup .env file with shared secrets
    setup_env_file "$service_dir" "$service_name"

    cd "$SCRIPT_DIR/$service_dir"

    # Special handling for certain services
    case "$service_name" in
        traefik)
            mkdir -p certs
            [[ ! -f "certs/acme.json" ]] && touch certs/acme.json && chmod 600 certs/acme.json
            ;;
        garage)
            if [[ -f "setup.sh" ]]; then
                ./setup.sh 2>/dev/null || docker compose up -d
                cd "$SCRIPT_DIR"
                INSTALLED_SERVICES["$service_name"]="$service_dir"
                return 0
            fi
            ;;
        authentik|crowdsec)
            if [[ -f "scripts/setup.sh" ]]; then
                ./scripts/setup.sh 2>/dev/null || docker compose up -d
                cd "$SCRIPT_DIR"
                INSTALLED_SERVICES["$service_name"]="$service_dir"
                return 0
            fi
            ;;
    esac

    # Start with docker compose
    docker compose up -d 2>/dev/null || {
        log_warn "Failed to start $service_name"
        cd "$SCRIPT_DIR"
        return 1
    }

    # Wait for container
    if [[ -n "$container" ]]; then
        wait_for_container "$container" 30 || log_warn "$service_name may not be fully ready"
    fi

    INSTALLED_SERVICES["$service_name"]="$service_dir"
    log_info "$service_name started"

    cd "$SCRIPT_DIR"
}

# =============================================================================
# Post-Setup Integration
# =============================================================================

setup_networks() {
    log_header "Setting Up Networks"

    docker network create traefik-public 2>/dev/null && log_info "Created traefik-public" || true
    docker network create infra 2>/dev/null && log_info "Created infra" || true
}

connect_traefik_services() {
    if [[ -z "${INSTALLED_SERVICES[traefik]}" ]]; then
        return
    fi

    log_step "Connecting services to Traefik network..."

    local web_services=(
        "grafana" "uptime-kuma" "authentik-server" "n8n" "asynqmon"
        "meilisearch" "registry" "portainer" "redisinsight" "gitea"
        "plausible" "drone" "dozzle" "vaultwarden" "ntfy" "healthchecks"
        "adminer" "sentry"
    )

    for container in "${web_services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            docker network connect traefik-public "$container" 2>/dev/null || true
            log_info "  → $container connected"
        fi
    done
}

integrate_crowdsec() {
    if [[ -n "${INSTALLED_SERVICES[traefik]}" ]] && [[ -n "${INSTALLED_SERVICES[crowdsec]}" ]]; then
        docker network connect crowdsec-net traefik 2>/dev/null || true
        log_info "Traefik connected to Crowdsec"
    fi
}

register_monitoring_targets() {
    if [[ -z "${INSTALLED_SERVICES[observability]}" ]]; then
        return
    fi

    log_step "Registering monitoring targets..."

    cd "$SCRIPT_DIR/services/observability"
    mkdir -p targets

    for service in "${!INSTALLED_SERVICES[@]}"; do
        local port=${SERVICE_EXPORTER_PORTS[$service]}
        if [[ -n "$port" ]]; then
            local target_type="application"
            case "$service" in
                postgres|postgres-ha) target_type="postgres" ;;
                redis) target_type="redis" ;;
                mongo) target_type="mongodb" ;;
                mysql) target_type="mysql" ;;
                memcached) target_type="memcached" ;;
                clickhouse) target_type="clickhouse" ;;
                kafka) target_type="kafka" ;;
                minio) target_type="minio" ;;
                nats) target_type="nats" ;;
                rabbitmq) target_type="rabbitmq" ;;
                traefik) target_type="traefik" ;;
            esac

            # Create target file directly
            local target_file="targets/${target_type}.json"
            cat > "$target_file" << EOF
[
  {
    "targets": ["host.docker.internal:${port}"],
    "labels": {
      "service": "${service}",
      "instance": "${service}"
    }
  }
]
EOF
            log_info "  → $service registered (${target_type}:${port})"
        fi
    done

    cd "$SCRIPT_DIR"
}

# Auto-enable ntfy for alerts
auto_enable_ntfy() {
    if [[ -n "${INSTALLED_SERVICES[observability]}" ]] && [[ -z "${INSTALLED_SERVICES[ntfy]}" ]]; then
        log_step "Auto-enabling Ntfy for alert notifications..."
        ENABLED_SERVICES["ntfy"]=true
        start_service "ntfy"
    fi
}

configure_backup() {
    if [[ -z "${INSTALLED_SERVICES[backup]}" ]]; then
        return
    fi

    log_step "Configuring automatic backup..."

    cd "$SCRIPT_DIR/services/backup"

    if [[ "$(uname)" == "Darwin" ]]; then
        local SED_CMD="sed -i ''"
    else
        local SED_CMD="sed -i"
    fi

    # Generate restic password
    local RESTIC_PASS=$(openssl rand -base64 32 | tr -d '\n')
    $SED_CMD "s|^RESTIC_PASSWORD=.*|RESTIC_PASSWORD=${RESTIC_PASS}|" .env

    # Configure S3 storage (Garage or MinIO)
    if [[ -n "${INSTALLED_SERVICES[garage]}" ]]; then
        $SED_CMD "s|^RESTIC_REPOSITORY=.*|RESTIC_REPOSITORY=s3:http://garage:3900/backups|" .env
        $SED_CMD "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=${SHARED_GARAGE_ADMIN_TOKEN}|" .env
        $SED_CMD "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=${SHARED_GARAGE_ADMIN_TOKEN}|" .env
        log_info "  → Storage: Garage S3"
    elif [[ -n "${INSTALLED_SERVICES[minio]}" ]]; then
        $SED_CMD "s|^RESTIC_REPOSITORY=.*|RESTIC_REPOSITORY=s3:http://minio:9000/backups|" .env
        $SED_CMD "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=minioadmin|" .env
        $SED_CMD "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=minioadmin|" .env
        log_info "  → Storage: MinIO S3"
    fi

    # Configure .env credentials
    $SED_CMD "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${SHARED_POSTGRES_PASSWORD}|" .env
    $SED_CMD "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${SHARED_REDIS_PASSWORD}|" .env
    $SED_CMD "s|^MONGO_PASSWORD=.*|MONGO_PASSWORD=${SHARED_MONGO_PASSWORD}|" .env

    if [[ -n "${INSTALLED_SERVICES[mysql]}" ]]; then
        local MYSQL_PASS=$(grep "^MYSQL_ROOT_PASSWORD=" "$SCRIPT_DIR/services/mysql/.env" 2>/dev/null | cut -d'=' -f2)
        $SED_CMD "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_PASS}|" .env
    fi

    # Configure Ntfy notifications
    if [[ -n "${INSTALLED_SERVICES[ntfy]}" ]]; then
        $SED_CMD "s|^NTFY_URL=.*|NTFY_URL=http://ntfy:80/backups|" .env
        log_info "  → Ntfy notifications enabled"
    fi

    # Auto-populate config/*.json backup targets
    mkdir -p config

    # PostgreSQL targets
    if [[ -n "${INSTALLED_SERVICES[postgres]}" ]] || [[ -n "${INSTALLED_SERVICES[postgres-ha]}" ]]; then
        cat > config/postgres.json << 'EOF'
{
  "targets": [
    {
      "name": "postgres",
      "enabled": true,
      "mode": "docker",
      "container": "postgres",
      "user": "postgres",
      "password_env": "POSTGRES_PASSWORD",
      "databases": ["postgres"]
    }
  ]
}
EOF
        log_info "  → PostgreSQL backup target added"
    fi

    # MySQL targets
    if [[ -n "${INSTALLED_SERVICES[mysql]}" ]]; then
        cat > config/mysql.json << 'EOF'
{
  "targets": [
    {
      "name": "mysql",
      "enabled": true,
      "mode": "docker",
      "container": "mysql",
      "user": "root",
      "password_env": "MYSQL_ROOT_PASSWORD"
    }
  ]
}
EOF
        log_info "  → MySQL backup target added"
    fi

    # Redis targets
    if [[ -n "${INSTALLED_SERVICES[redis]}" ]]; then
        cat > config/redis.json << 'EOF'
{
  "targets": [
    {
      "name": "redis",
      "enabled": true,
      "mode": "docker",
      "container": "redis",
      "password_env": "REDIS_PASSWORD"
    }
  ]
}
EOF
        log_info "  → Redis backup target added"
    fi

    # MongoDB targets
    if [[ -n "${INSTALLED_SERVICES[mongo]}" ]]; then
        cat > config/mongo.json << 'EOF'
{
  "targets": [
    {
      "name": "mongo",
      "enabled": true,
      "mode": "docker",
      "container": "mongo",
      "user": "admin",
      "password_env": "MONGO_PASSWORD",
      "auth_db": "admin"
    }
  ]
}
EOF
        log_info "  → MongoDB backup target added"
    fi

    # NATS targets
    if [[ -n "${INSTALLED_SERVICES[nats]}" ]]; then
        cat > config/nats.json << 'EOF'
{
  "targets": [
    {
      "name": "nats",
      "enabled": true,
      "mode": "docker",
      "container": "nats",
      "data_dir": "/data/jetstream"
    }
  ]
}
EOF
        log_info "  → NATS backup target added"
    fi

    log_info "  → Schedule: Daily at 2 AM"

    cd "$SCRIPT_DIR"
}

# =============================================================================
# Main Setup Flow
# =============================================================================

run_setup() {
    log_header "Starting Infrastructure Setup"

    check_docker
    check_linux_host_docker

    # Load or generate secrets
    if ! load_shared_secrets; then
        generate_shared_secrets
    fi

    # Setup networks first
    setup_networks

    # Start services in order
    local service_order=(
        # 1. Networking (must be first)
        "traefik" "wireguard"
        # 2. Databases
        "postgres" "postgres-ha" "redis" "mongo" "timescaledb"
        "mysql" "memcached" "clickhouse"
        # 3. Queues
        "nats" "kafka" "rabbitmq" "asynq"
        # 4. Storage
        "garage" "minio"
        # 5. Search & Vector
        "meilisearch" "opensearch" "qdrant"
        # 6. AI / LLM
        "langfuse"
        # 7. Security
        "fail2ban" "crowdsec" "authentik" "vault"
        # 8. Monitoring & Tools
        "observability" "uptime-kuma" "registry" "n8n" "faster-whisper"
        "sentry" "adminer" "mailpit" "portainer" "redisinsight"
        "plausible" "dozzle" "vaultwarden" "ntfy" "healthchecks"
        # 9. CI/CD
        "github-runner" "gitlab-runner" "gitea" "drone"
        # 10. Maintenance (auto-updates)
        "watchtower"
        # 11. Backup (last - needs other services configured)
        "backup"
    )

    for service in "${service_order[@]}"; do
        if [[ "${ENABLED_SERVICES[$service]}" == "true" ]]; then
            start_service "$service"
        fi
    done

    # Post-setup integrations
    log_header "Configuring Integrations"
    connect_traefik_services
    integrate_crowdsec
    auto_enable_ntfy
    register_monitoring_targets
    configure_backup

    log_info "All integrations configured"
}

# =============================================================================
# Summary Display
# =============================================================================

show_summary() {
    log_header "Setup Complete!"

    echo "Installed Services:"
    echo ""
    for service in "${!INSTALLED_SERVICES[@]}"; do
        echo -e "  ${GREEN}✓${NC} $service"
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Access Points:"
    echo ""

    [[ -n "${INSTALLED_SERVICES[observability]}" ]] && {
        local GRAFANA_PASS=$(grep "GRAFANA_ADMIN_PASSWORD" tools/observability/.env 2>/dev/null | cut -d'=' -f2)
        echo "  Grafana:      http://localhost:3000  (admin / $GRAFANA_PASS)"
        echo "  Prometheus:   http://localhost:9090"
    }
    [[ -n "${INSTALLED_SERVICES[traefik]}" ]] && echo "  Traefik:      http://localhost:8080"
    [[ -n "${INSTALLED_SERVICES[uptime-kuma]}" ]] && echo "  Uptime Kuma:  http://localhost:3001"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Credentials: .secrets"
    echo ""
    echo "  PostgreSQL: $SHARED_POSTGRES_USER / $SHARED_POSTGRES_PASSWORD"
    [[ -n "$SHARED_REDIS_PASSWORD" ]] && echo "  Redis:      $SHARED_REDIS_PASSWORD"
    [[ -n "${INSTALLED_SERVICES[mongo]}" ]] && echo "  MongoDB:    $SHARED_MONGO_USER / $SHARED_MONGO_PASSWORD"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show monitoring info
    if [[ -n "${INSTALLED_SERVICES[observability]}" ]]; then
        echo "Monitoring & Alerts:"
        echo "  ✓ All services auto-registered with Prometheus"
        echo "  ✓ Alert rules enabled for all databases & queues"
        if [[ -n "${INSTALLED_SERVICES[ntfy]}" ]]; then
            echo "  ✓ Alerts → Ntfy push notifications"
            echo ""
            echo "  Subscribe to alerts:"
            echo "    - Open http://localhost:8090"
            echo "    - Subscribe to topics: alerts, alerts-critical, alerts-warning"
        fi
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    # Show backup info
    if [[ -n "${INSTALLED_SERVICES[backup]}" ]]; then
        echo "Automatic Backup:"
        echo "  ✓ Schedule: Daily at 2 AM"
        [[ -n "${INSTALLED_SERVICES[postgres]}" || -n "${INSTALLED_SERVICES[postgres-ha]}" ]] && echo "  ✓ PostgreSQL → auto-backup"
        [[ -n "${INSTALLED_SERVICES[mysql]}" ]] && echo "  ✓ MySQL → auto-backup"
        [[ -n "${INSTALLED_SERVICES[redis]}" ]] && echo "  ✓ Redis → auto-backup"
        [[ -n "${INSTALLED_SERVICES[mongo]}" ]] && echo "  ✓ MongoDB → auto-backup"
        [[ -n "${INSTALLED_SERVICES[garage]}" ]] && echo "  ✓ Storage: Garage S3"
        [[ -n "${INSTALLED_SERVICES[minio]}" ]] && echo "  ✓ Storage: MinIO S3"
        [[ -n "${INSTALLED_SERVICES[ntfy]}" ]] && echo "  ✓ Notifications: Ntfy (topic: backups)"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    echo "Commands:"
    echo "  ./status.sh       Check service status"
    echo "  ./stop.sh         Stop all services"
    echo ""
    echo "To add a service:"
    echo "  1. Edit services.conf"
    echo "  2. Set service=true"
    echo "  3. Run ./setup.sh"
    echo ""
}

# =============================================================================
# Preset Configurations
# =============================================================================

apply_preset() {
    local preset=$1

    # Reset all services
    for service in "${!SERVICE_DIRS[@]}"; do
        ENABLED_SERVICES["$service"]=false
    done

    case "$preset" in
        minimal)
            ENABLED_SERVICES["traefik"]=true
            ENABLED_SERVICES["postgres"]=true
            ENABLED_SERVICES["redis"]=true
            ENABLED_SERVICES["observability"]=true
            ENABLED_SERVICES["backup"]=true
            ;;
        standard)
            ENABLED_SERVICES["traefik"]=true
            ENABLED_SERVICES["postgres"]=true
            ENABLED_SERVICES["redis"]=true
            ENABLED_SERVICES["garage"]=true
            ENABLED_SERVICES["fail2ban"]=true
            ENABLED_SERVICES["crowdsec"]=true
            ENABLED_SERVICES["observability"]=true
            ENABLED_SERVICES["uptime-kuma"]=true
            ENABLED_SERVICES["backup"]=true
            ;;
        all)
            for service in "${!SERVICE_DIRS[@]}"; do
                # Skip alternatives
                [[ "$service" == "postgres-ha" ]] && continue
                [[ "$service" == "minio" ]] && continue
                ENABLED_SERVICES["$service"]=true
            done
            ;;
    esac
}

# =============================================================================
# CLI Entry Point
# =============================================================================

case "${1:-}" in
    --all)
        apply_preset "all"
        run_setup
        show_summary
        ;;
    --minimal)
        apply_preset "minimal"
        run_setup
        show_summary
        ;;
    --standard)
        apply_preset "standard"
        run_setup
        show_summary
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (none)       Use services.conf configuration"
        echo "  --minimal    Traefik, PostgreSQL, Redis, Monitoring, Backup"
        echo "  --standard   Minimal + Garage, Security, Uptime Kuma"
        echo "  --all        Everything (except alternatives)"
        echo "  --help       Show this help"
        echo ""
        echo "Configuration:"
        echo "  Edit services.conf to customize which services to run"
        echo ""
        ;;
    *)
        # Use services.conf
        load_services_conf
        run_setup
        show_summary
        ;;
esac
