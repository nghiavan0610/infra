#!/bin/bash
# =============================================================================
# Application Registration CLI
# =============================================================================
# Automatically set up database, monitoring, and backup for new backend apps.
#
# Usage:
#   ./lib/app-cli.sh register <app-name> [options]
#   ./lib/app-cli.sh generate <app-name> [options]
#   ./lib/app-cli.sh list
#   ./lib/app-cli.sh remove <app-name>
#
# Examples:
#   ./lib/app-cli.sh register myapi --db postgres --domain api.example.com
#   ./lib/app-cli.sh generate myapi --db postgres --redis --s3
#   ./lib/app-cli.sh remove myapi --drop-db
# =============================================================================

set -e

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Configuration
# =============================================================================

APPS_DIR="${APPS_DIR:-/opt/apps}"
APPS_REGISTRY="$INFRA_ROOT/.apps-registry"

# =============================================================================
# Helper Functions
# =============================================================================

generate_password() {
    openssl rand -base64 24 | tr -d '\n' | head -c 24
}

load_secrets() {
    if [[ -f "$INFRA_ROOT/.secrets" ]]; then
        source "$INFRA_ROOT/.secrets"
    fi
}

save_app_config() {
    local app_name=$1
    local config_file="$APPS_REGISTRY/${app_name}.env"

    mkdir -p "$APPS_REGISTRY"
    cat > "$config_file"
    chmod 600 "$config_file"
}

# =============================================================================
# Register Command
# =============================================================================

cmd_register() {
    local app_name=""
    local db_type=""
    local db_name=""
    local with_redis=false
    local with_s3=false
    local domain=""
    local metrics_port=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db)
                db_type="$2"
                shift 2
                ;;
            --db-name)
                db_name="$2"
                shift 2
                ;;
            --redis)
                with_redis=true
                shift
                ;;
            --s3)
                with_s3=true
                shift
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --metrics-port)
                metrics_port="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                app_name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        echo "Usage: $0 register <app-name> [--db postgres|mysql|mongo] [--redis] [--s3] [--domain example.com]"
        exit 1
    fi

    # Sanitize app name
    app_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    db_name="${db_name:-${app_name}_db}"

    log_header "Registering Application: $app_name"

    load_secrets

    local app_config=""
    app_config+="# Auto-generated config for $app_name - $(date)\n"
    app_config+="APP_NAME=$app_name\n"

    # Create database user
    if [[ -n "$db_type" ]]; then
        local db_user="${app_name}_user"
        local db_pass=$(generate_password)

        log_step "Creating $db_type database..."

        case "$db_type" in
            postgres|pg)
                "$SCRIPT_DIR/db-cli.sh" postgres create-user "$db_user" "$db_pass" "$db_name" 2>/dev/null || true
                app_config+="DATABASE_URL=postgresql://${db_user}:${db_pass}@postgres:5432/${db_name}\n"
                app_config+="DB_HOST=postgres\n"
                app_config+="DB_PORT=5432\n"
                app_config+="DB_NAME=$db_name\n"
                app_config+="DB_USER=$db_user\n"
                app_config+="DB_PASSWORD=$db_pass\n"
                log_info "PostgreSQL: $db_name created"
                ;;
            mysql)
                "$SCRIPT_DIR/db-cli.sh" mysql create-user "$db_user" "$db_pass" "$db_name" 2>/dev/null || true
                local db_pass_encoded=$(url_encode "$db_pass")
                app_config+="DATABASE_URL=mysql://${db_user}:${db_pass_encoded}@mysql:3306/${db_name}\n"
                app_config+="DB_HOST=mysql\n"
                app_config+="DB_PORT=3306\n"
                app_config+="DB_NAME=$db_name\n"
                app_config+="DB_USER=$db_user\n"
                app_config+="DB_PASSWORD=$db_pass\n"
                log_info "MySQL: $db_name created"
                ;;
            mongo|mongodb)
                "$SCRIPT_DIR/db-cli.sh" mongo create-user "$db_user" "$db_pass" "$db_name" 2>/dev/null || true
                local db_pass_encoded=$(url_encode "$db_pass")
                app_config+="MONGO_URL=mongodb://${db_user}:${db_pass_encoded}@mongo:27017/${db_name}?authSource=${db_name}\n"
                app_config+="DB_HOST=mongo\n"
                app_config+="DB_PORT=27017\n"
                app_config+="DB_NAME=$db_name\n"
                app_config+="DB_USER=$db_user\n"
                app_config+="DB_PASSWORD=$db_pass\n"
                log_info "MongoDB: $db_name created"
                ;;
        esac
    fi

    # Redis configuration
    if [[ "$with_redis" == "true" ]]; then
        log_step "Configuring Redis..."
        local redis_pass="${REDIS_PASSWORD:-}"
        if [[ -z "$redis_pass" ]] && [[ -f "$INFRA_ROOT/services/redis/.env" ]]; then
            redis_pass=$(grep "^REDIS_PASSWORD=" "$INFRA_ROOT/services/redis/.env" | cut -d'=' -f2)
        fi
        local redis_pass_encoded=$(url_encode "$redis_pass")
        app_config+="REDIS_URL=redis://:${redis_pass_encoded}@redis-cache:6379/0\n"
        app_config+="REDIS_QUEUE_URL=redis://:${redis_pass_encoded}@redis-queue:6379/0\n"
        app_config+="REDIS_HOST=redis-cache\n"
        app_config+="REDIS_PORT=6379\n"
        app_config+="REDIS_PASSWORD=$redis_pass\n"
        log_info "Redis: configured"
    fi

    # S3 configuration
    if [[ "$with_s3" == "true" ]]; then
        log_step "Configuring S3 storage..."
        local s3_key="${GARAGE_ADMIN_TOKEN:-}"
        if [[ -z "$s3_key" ]] && [[ -f "$INFRA_ROOT/services/garage/.env" ]]; then
            s3_key=$(grep "^GARAGE_ADMIN_TOKEN=" "$INFRA_ROOT/services/garage/.env" | cut -d'=' -f2)
        fi
        app_config+="S3_ENDPOINT=http://garage:3900\n"
        app_config+="S3_BUCKET=${app_name}-bucket\n"
        app_config+="S3_ACCESS_KEY=$s3_key\n"
        app_config+="S3_SECRET_KEY=$s3_key\n"
        app_config+="AWS_ENDPOINT_URL=http://garage:3900\n"
        app_config+="AWS_ACCESS_KEY_ID=$s3_key\n"
        app_config+="AWS_SECRET_ACCESS_KEY=$s3_key\n"
        log_info "S3: configured (bucket: ${app_name}-bucket)"
    fi

    # Domain configuration
    if [[ -n "$domain" ]]; then
        app_config+="DOMAIN=$domain\n"
        app_config+="APP_URL=https://$domain\n"
    fi

    # Add to monitoring (if metrics port specified)
    if [[ -n "$metrics_port" ]]; then
        log_step "Registering with monitoring..."
        add_to_monitoring "$app_name" "$metrics_port"
        app_config+="METRICS_PORT=$metrics_port\n"
        log_info "Monitoring: registered (port $metrics_port)"
    fi

    # Save configuration
    echo -e "$app_config" | save_app_config "$app_name"

    log_header "Registration Complete"
    echo ""
    echo "App config saved to: $APPS_REGISTRY/${app_name}.env"
    echo ""
    echo "Use in your docker-compose.yml:"
    echo "  env_file:"
    echo "    - $APPS_REGISTRY/${app_name}.env"
    echo ""
    echo "Or source it:"
    echo "  source $APPS_REGISTRY/${app_name}.env"
    echo ""

    # Show the config
    echo "Generated configuration:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$APPS_REGISTRY/${app_name}.env"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# Generate docker-compose Command
# =============================================================================

cmd_generate() {
    local app_name=""
    local db_type=""
    local with_redis=false
    local with_s3=false
    local domain=""
    local image=""
    local port="8080"
    local output_dir="."

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db)
                db_type="$2"
                shift 2
                ;;
            --redis)
                with_redis=true
                shift
                ;;
            --s3)
                with_s3=true
                shift
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --image)
                image="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --output|-o)
                output_dir="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                app_name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        echo "Usage: $0 generate <app-name> [--db postgres] [--redis] [--domain api.example.com] [--image myapp:latest]"
        exit 1
    fi

    # First register the app to create credentials
    local register_args=("$app_name")
    [[ -n "$db_type" ]] && register_args+=(--db "$db_type")
    [[ "$with_redis" == "true" ]] && register_args+=(--redis)
    [[ "$with_s3" == "true" ]] && register_args+=(--s3)
    [[ -n "$domain" ]] && register_args+=(--domain "$domain")
    [[ -n "$port" ]] && register_args+=(--metrics-port "$port")

    cmd_register "${register_args[@]}"

    # Generate docker-compose.yml
    local compose_file="$output_dir/docker-compose.yml"

    log_step "Generating docker-compose.yml..."

    cat > "$compose_file" << EOF
# =============================================================================
# ${app_name} - Auto-generated docker-compose
# =============================================================================
# Generated by: ./lib/app-cli.sh generate
# Date: $(date)
#
# Usage:
#   docker compose up -d
#   docker compose logs -f
# =============================================================================

services:
  ${app_name}:
    image: ${image:-${app_name}:latest}
    container_name: ${app_name}
    restart: unless-stopped
    env_file:
      - ${APPS_REGISTRY}/${app_name}.env
    environment:
      - NODE_ENV=production
EOF

    # Add Traefik labels if domain specified
    if [[ -n "$domain" ]]; then
        cat >> "$compose_file" << EOF
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${app_name}.rule=Host(\`${domain}\`)"
      - "traefik.http.routers.${app_name}.entrypoints=websecure"
      - "traefik.http.routers.${app_name}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${app_name}.loadbalancer.server.port=${port}"
      # Prometheus metrics discovery
      - "prometheus.scrape=true"
      - "prometheus.port=${port}"
      - "prometheus.path=/metrics"
EOF
    else
        cat >> "$compose_file" << EOF
    ports:
      - "${port}:${port}"
    labels:
      # Prometheus metrics discovery
      - "prometheus.scrape=true"
      - "prometheus.port=${port}"
      - "prometheus.path=/metrics"
EOF
    fi

    cat >> "$compose_file" << EOF
    networks:
      - infra
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:${port}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  infra:
    external: true
EOF

    log_info "Generated: $compose_file"
    echo ""
    echo "Next steps:"
    echo "  1. cd $output_dir"
    echo "  2. docker compose up -d"
    echo ""
}

# =============================================================================
# List Command
# =============================================================================

cmd_list() {
    log_header "Registered Applications"

    if [[ ! -d "$APPS_REGISTRY" ]] || [[ -z "$(ls -A "$APPS_REGISTRY" 2>/dev/null)" ]]; then
        echo "No applications registered yet."
        echo ""
        echo "Register an app with:"
        echo "  ./lib/app-cli.sh register myapp --db postgres --redis"
        return
    fi

    printf "%-20s %-15s %-10s %-10s %s\n" "APP" "DATABASE" "REDIS" "S3" "DOMAIN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for config_file in "$APPS_REGISTRY"/*.env; do
        [[ -f "$config_file" ]] || continue

        local app_name=$(basename "$config_file" .env)
        local db_type="-"
        local has_redis="-"
        local has_s3="-"
        local domain="-"

        grep -q "DATABASE_URL=postgresql" "$config_file" && db_type="postgres"
        grep -q "DATABASE_URL=mysql" "$config_file" && db_type="mysql"
        grep -q "MONGO_URL" "$config_file" && db_type="mongo"
        grep -q "REDIS_URL" "$config_file" && has_redis="yes"
        grep -q "S3_ENDPOINT" "$config_file" && has_s3="yes"
        domain=$(grep "^DOMAIN=" "$config_file" 2>/dev/null | cut -d'=' -f2 || echo "-")

        printf "%-20s %-15s %-10s %-10s %s\n" "$app_name" "$db_type" "$has_redis" "$has_s3" "$domain"
    done
    echo ""
}

# =============================================================================
# Remove Command
# =============================================================================

cmd_remove() {
    local app_name=$1
    local drop_db=${2:-}

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        exit 1
    fi

    log_header "Removing Application: $app_name"

    local config_file="$APPS_REGISTRY/${app_name}.env"

    if [[ ! -f "$config_file" ]]; then
        log_error "App not found: $app_name"
        exit 1
    fi

    # Optionally drop database
    if [[ "$drop_db" == "--drop-db" ]]; then
        log_step "Dropping database..."
        local db_user="${app_name}_user"

        if grep -q "DATABASE_URL=postgresql" "$config_file"; then
            "$SCRIPT_DIR/db-cli.sh" postgres delete-user "$db_user" --drop-schema 2>/dev/null || true
        elif grep -q "DATABASE_URL=mysql" "$config_file"; then
            "$SCRIPT_DIR/db-cli.sh" mysql delete-user "$db_user" 2>/dev/null || true
        elif grep -q "MONGO_URL" "$config_file"; then
            "$SCRIPT_DIR/db-cli.sh" mongo delete-user "$db_user" "${app_name}_db" 2>/dev/null || true
        fi
        log_info "Database dropped"
    fi

    # Remove from monitoring
    remove_from_monitoring "$app_name"

    # Remove config file
    rm -f "$config_file"

    log_info "App $app_name removed"
    echo ""
    echo "Note: Docker containers not stopped. Run manually:"
    echo "  docker compose -f /path/to/${app_name}/docker-compose.yml down"
}

# =============================================================================
# Monitoring Helpers
# =============================================================================

add_to_monitoring() {
    local app_name=$1
    local port=$2
    local targets_file="$INFRA_ROOT/services/observability/targets/applications.json"

    mkdir -p "$(dirname "$targets_file")"

    # Read existing or create new
    local existing="[]"
    [[ -f "$targets_file" ]] && existing=$(cat "$targets_file")

    # Check if already exists
    if echo "$existing" | jq -e ".[] | select(.labels.app == \"$app_name\")" > /dev/null 2>&1; then
        return 0
    fi

    # Add new target
    local new_target=$(cat << EOF
{
  "targets": ["${app_name}:${port}"],
  "labels": {
    "app": "${app_name}",
    "service": "${app_name}",
    "job": "applications"
  }
}
EOF
)

    echo "$existing" | jq ". + [$new_target]" > "$targets_file"
}

remove_from_monitoring() {
    local app_name=$1
    local targets_file="$INFRA_ROOT/services/observability/targets/applications.json"

    [[ -f "$targets_file" ]] || return 0

    jq "[.[] | select(.labels.app != \"$app_name\")]" "$targets_file" > "${targets_file}.tmp"
    mv "${targets_file}.tmp" "$targets_file"
}

# =============================================================================
# Connect Command - Register existing container with observability
# =============================================================================

cmd_connect() {
    local app_name=""
    local port="8080"
    local metrics_path="/metrics"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --port) port="$2"; shift 2 ;;
            --metrics-path) metrics_path="$2"; shift 2 ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) app_name="$1"; shift ;;
        esac
    done

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        echo "Usage: $0 connect <container-name> --port 8080"
        exit 1
    fi

    log_header "Connecting: $app_name"

    # Check if container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${app_name}$"; then
        log_warn "Container '$app_name' not running. Will register anyway."
    fi

    # Add to Prometheus targets
    log_step "Registering with Prometheus..."
    add_to_monitoring "$app_name" "$port"
    log_info "Added to monitoring targets"

    # Show OTEL env vars
    echo ""
    log_header "Done!"
    echo ""
    echo "Your container is now connected to:"
    echo "  ✓ Logging  → automatic (stdout/stderr → Loki)"
    echo "  ✓ Metrics  → Prometheus will scrape ${app_name}:${port}${metrics_path}"
    echo "  ✓ Alerting → automatic (based on metrics)"
    echo ""
    echo "For tracing, add these to your .env:"
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317"
    echo "  OTEL_SERVICE_NAME=${app_name}"
    echo ""
    echo "View in Grafana: http://localhost:3000"
    echo ""
}

# =============================================================================
# Init Command - Simple setup in current directory
# =============================================================================

cmd_init() {
    local app_name=""
    local db_type=""
    local with_redis=false
    local with_s3=false
    local domain=""
    local port="8080"
    local image=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db) db_type="$2"; shift 2 ;;
            --redis) with_redis=true; shift ;;
            --s3) with_s3=true; shift ;;
            --domain) domain="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --image) image="$2"; shift 2 ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) app_name="$1"; shift ;;
        esac
    done

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        echo "Usage: $0 init <app-name> --db postgres [--redis] [--domain api.example.com]"
        exit 1
    fi

    # Sanitize
    app_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    image="${image:-${app_name}:latest}"

    log_header "Initializing: $app_name"

    load_secrets

    # Build .env content
    local env_content=""
    env_content+="# =============================================================================\n"
    env_content+="# ${app_name} - Auto-generated by infra/app-cli.sh\n"
    env_content+="# =============================================================================\n\n"
    env_content+="# App Config\n"
    env_content+="APP_NAME=${app_name}\n"
    env_content+="PORT=${port}\n"
    env_content+="NODE_ENV=production\n\n"

    # Database
    if [[ -n "$db_type" ]]; then
        local db_user="${app_name}_user"
        local db_pass=$(generate_password)
        local db_name="${app_name}_db"

        log_step "Creating $db_type database..."

        case "$db_type" in
            postgres|pg)
                "$SCRIPT_DIR/db-cli.sh" postgres create-user "$db_user" "$db_pass" "$db_name" >/dev/null 2>&1 || true
                env_content+="# Database\n"
                env_content+="DATABASE_URL=postgresql://${db_user}:${db_pass}@postgres:5432/${db_name}\n"
                env_content+="DB_HOST=postgres\n"
                env_content+="DB_PORT=5432\n"
                env_content+="DB_NAME=${db_name}\n"
                env_content+="DB_USER=${db_user}\n"
                env_content+="DB_PASSWORD=${db_pass}\n\n"
                log_info "PostgreSQL database created: $db_name"
                ;;
            mysql)
                "$SCRIPT_DIR/db-cli.sh" mysql create-user "$db_user" "$db_pass" "$db_name" >/dev/null 2>&1 || true
                local db_pass_encoded=$(url_encode "$db_pass")
                env_content+="# Database\n"
                env_content+="DATABASE_URL=mysql://${db_user}:${db_pass_encoded}@mysql:3306/${db_name}\n"
                env_content+="DB_HOST=mysql\n"
                env_content+="DB_PORT=3306\n"
                env_content+="DB_NAME=${db_name}\n"
                env_content+="DB_USER=${db_user}\n"
                env_content+="DB_PASSWORD=${db_pass}\n\n"
                log_info "MySQL database created: $db_name"
                ;;
            mongo|mongodb)
                "$SCRIPT_DIR/db-cli.sh" mongo create-user "$db_user" "$db_pass" "$db_name" >/dev/null 2>&1 || true
                local db_pass_encoded=$(url_encode "$db_pass")
                env_content+="# Database\n"
                env_content+="MONGO_URL=mongodb://${db_user}:${db_pass_encoded}@mongo:27017/${db_name}?authSource=${db_name}\n"
                env_content+="DB_HOST=mongo\n"
                env_content+="DB_PORT=27017\n"
                env_content+="DB_NAME=${db_name}\n"
                env_content+="DB_USER=${db_user}\n"
                env_content+="DB_PASSWORD=${db_pass}\n\n"
                log_info "MongoDB database created: $db_name"
                ;;
        esac
    fi

    # Redis
    if [[ "$with_redis" == "true" ]]; then
        log_step "Adding Redis config..."
        local redis_pass="${REDIS_PASSWORD:-}"
        if [[ -z "$redis_pass" ]] && [[ -f "$INFRA_ROOT/services/redis/.env" ]]; then
            redis_pass=$(grep "^REDIS_PASSWORD=" "$INFRA_ROOT/services/redis/.env" | cut -d'=' -f2)
        fi
        local redis_pass_encoded=$(url_encode "$redis_pass")
        env_content+="# Redis\n"
        env_content+="REDIS_URL=redis://:${redis_pass_encoded}@redis-cache:6379/0\n"
        env_content+="REDIS_QUEUE_URL=redis://:${redis_pass_encoded}@redis-queue:6379/0\n\n"
        log_info "Redis configured"
    fi

    # S3
    if [[ "$with_s3" == "true" ]]; then
        log_step "Adding S3 config..."
        local s3_key="${GARAGE_ADMIN_TOKEN:-}"
        if [[ -z "$s3_key" ]] && [[ -f "$INFRA_ROOT/services/garage/.env" ]]; then
            s3_key=$(grep "^GARAGE_ADMIN_TOKEN=" "$INFRA_ROOT/services/garage/.env" | cut -d'=' -f2)
        fi
        env_content+="# S3 Storage\n"
        env_content+="S3_ENDPOINT=http://garage:3900\n"
        env_content+="S3_BUCKET=${app_name}-bucket\n"
        env_content+="AWS_ACCESS_KEY_ID=${s3_key}\n"
        env_content+="AWS_SECRET_ACCESS_KEY=${s3_key}\n\n"
        log_info "S3 configured"
    fi

    # Observability
    env_content+="# Observability (tracing)\n"
    env_content+="OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317\n"
    env_content+="OTEL_SERVICE_NAME=${app_name}\n"

    # Write .env
    echo -e "$env_content" > .env
    chmod 600 .env
    log_info "Created .env"

    # Build docker-compose.yml
    log_step "Creating docker-compose.yml..."

    local compose_content=""
    compose_content+="# =============================================================================\n"
    compose_content+="# ${app_name} - Auto-generated by infra/app-cli.sh\n"
    compose_content+="# =============================================================================\n"
    compose_content+="# Start:  docker compose up -d\n"
    compose_content+="# Logs:   docker compose logs -f\n"
    compose_content+="# Stop:   docker compose down\n"
    compose_content+="# =============================================================================\n\n"
    compose_content+="services:\n"
    compose_content+="  ${app_name}:\n"
    compose_content+="    image: ${image}\n"
    compose_content+="    container_name: ${app_name}\n"
    compose_content+="    restart: unless-stopped\n"
    compose_content+="    env_file:\n"
    compose_content+="      - .env\n"

    # Labels
    compose_content+="    labels:\n"
    compose_content+="      # Auto-discovery: Prometheus will scrape /metrics\n"
    compose_content+="      - \"prometheus.scrape=true\"\n"
    compose_content+="      - \"prometheus.port=${port}\"\n"
    compose_content+="      - \"prometheus.path=/metrics\"\n"

    if [[ -n "$domain" ]]; then
        compose_content+="      # Traefik: auto SSL + routing\n"
        compose_content+="      - \"traefik.enable=true\"\n"
        compose_content+="      - \"traefik.http.routers.${app_name}.rule=Host(\\\`${domain}\\\`)\"\n"
        compose_content+="      - \"traefik.http.routers.${app_name}.entrypoints=websecure\"\n"
        compose_content+="      - \"traefik.http.routers.${app_name}.tls.certresolver=letsencrypt\"\n"
        compose_content+="      - \"traefik.http.services.${app_name}.loadbalancer.server.port=${port}\"\n"
    else
        compose_content+="    ports:\n"
        compose_content+="      - \"${port}:${port}\"\n"
    fi

    compose_content+="    networks:\n"
    compose_content+="      - infra\n"
    compose_content+="    healthcheck:\n"
    compose_content+="      test: [\"CMD\", \"wget\", \"-q\", \"--spider\", \"http://localhost:${port}/health\"]\n"
    compose_content+="      interval: 30s\n"
    compose_content+="      timeout: 10s\n"
    compose_content+="      retries: 3\n"
    compose_content+="\n"
    compose_content+="networks:\n"
    compose_content+="  infra:\n"
    compose_content+="    external: true\n"

    echo -e "$compose_content" > docker-compose.yml
    log_info "Created docker-compose.yml"

    # Register app
    mkdir -p "$APPS_REGISTRY"
    echo -e "$env_content" > "$APPS_REGISTRY/${app_name}.env"

    # Add to monitoring
    if [[ -n "$port" ]]; then
        add_to_monitoring "$app_name" "$port"
    fi

    echo ""
    log_header "Done!"
    echo ""
    echo "Files created:"
    echo "  .env              - All credentials"
    echo "  docker-compose.yml - Ready to run"
    echo ""
    echo "Next steps:"
    echo "  1. Build your image: docker build -t ${image} ."
    echo "  2. Start: docker compose up -d"
    echo ""
    echo "Auto-enabled:"
    echo "  ✓ Logging    → Grafana/Loki"
    echo "  ✓ Metrics    → Prometheus/Grafana (expose /metrics)"
    echo "  ✓ Tracing    → Tempo/Grafana (use OTEL_* env vars)"
    echo "  ✓ Alerting   → Alertmanager"
    [[ -n "$domain" ]] && echo "  ✓ SSL        → Traefik (https://${domain})"
    echo ""
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Application CLI - Connect backends to infrastructure

Usage:
  ./lib/app-cli.sh <command> [options]

Commands:
  connect     Connect existing container to observability (logging/metrics/tracing)
  init        Create .env and docker-compose.yml with database credentials
  list        List all registered apps
  remove      Remove an app registration

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONNECT (for existing containers):

  You create your own .env and docker-compose.yml, then connect to observability:

  # After your container is running:
  /opt/infra/lib/app-cli.sh connect myapi --port 8080

  This enables:
    ✓ Logging  - automatic (stdout → Loki)
    ✓ Metrics  - Prometheus scrapes /metrics
    ✓ Alerting - automatic

  For tracing, add to your .env:
    OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
    OTEL_SERVICE_NAME=myapi

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INIT (generates everything):

  # Creates .env + docker-compose.yml with database:
  /opt/infra/lib/app-cli.sh init myapi --db postgres
  /opt/infra/lib/app-cli.sh init myapi --db postgres --redis --domain api.example.com

  Options:
    --db <type>     postgres, mysql, mongo
    --redis         Include Redis credentials
    --s3            Include S3/Garage credentials
    --domain <host> Setup Traefik with SSL
    --port <port>   App port (default: 8080)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REQUIREMENTS:

  Your docker-compose.yml MUST have:

    networks:
      - infra

    networks:
      infra:
        external: true

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command=${1:-}
    shift || true

    case "$command" in
        connect)
            cmd_connect "$@"
            ;;
        init)
            cmd_init "$@"
            ;;
        register)
            cmd_register "$@"
            ;;
        generate|gen)
            cmd_generate "$@"
            ;;
        list|ls)
            cmd_list
            ;;
        remove|rm)
            cmd_remove "$@"
            ;;
        --help|-h|"")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
