#!/bin/bash
# =============================================================================
# Application Registration CLI
# =============================================================================
# Automatically set up database, monitoring, and backup for new backend apps.
#
# Usage:
#   ./scripts/app-cli.sh register <app-name> [options]
#   ./scripts/app-cli.sh generate <app-name> [options]
#   ./scripts/app-cli.sh list
#   ./scripts/app-cli.sh remove <app-name>
#
# Examples:
#   ./scripts/app-cli.sh register myapi --db postgres --domain api.example.com
#   ./scripts/app-cli.sh generate myapi --db postgres --redis --s3
#   ./scripts/app-cli.sh remove myapi --drop-db
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

source "$INFRA_ROOT/lib/common.sh"

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
            redis_pass=$(grep "^REDIS_PASSWORD=" "$INFRA_ROOT/services/redis/.env" | cut -d'=' -f2-)
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
            s3_key=$(grep "^GARAGE_ADMIN_TOKEN=" "$INFRA_ROOT/services/garage/.env" | cut -d'=' -f2-)
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

    # Ensure Prometheus can read the file (runs as nobody/65534)
    chmod 644 "$targets_file" 2>/dev/null || true
}

remove_from_monitoring() {
    local app_name=$1
    local targets_file="$INFRA_ROOT/services/observability/targets/applications.json"

    [[ -f "$targets_file" ]] || return 0

    jq "[.[] | select(.labels.app != \"$app_name\")]" "$targets_file" > "${targets_file}.tmp"
    mv "${targets_file}.tmp" "$targets_file"
}

# =============================================================================
# Reload Observability Stack
# =============================================================================
# Reloads Prometheus and Grafana to pick up new dashboards/alerts.
# =============================================================================

reload_observability() {
    local reload_prometheus=true
    local reload_grafana=true

    log_header "Reloading Observability Stack"

    # Reload Prometheus
    if [[ "$reload_prometheus" == "true" ]]; then
        log_step "Reloading Prometheus..."
        if curl -s -X POST http://localhost:9090/-/reload >/dev/null 2>&1; then
            log_info "Prometheus reloaded"
        else
            log_warn "Prometheus not running or reload failed"
        fi
    fi

    # Reload Grafana dashboards
    if [[ "$reload_grafana" == "true" ]]; then
        log_step "Reloading Grafana dashboards..."
        if curl -s -X POST http://localhost:3000/api/admin/provisioning/dashboards/reload >/dev/null 2>&1; then
            log_info "Grafana dashboards reloaded"
        else
            log_warn "Grafana not running or reload failed"
        fi
    fi

    echo ""
    log_info "Done! Changes should now be visible."
    echo ""
    echo "File locations:"
    echo "  Dashboards: services/observability/dashboards/"
    echo "  Alerts:     services/observability/config/alerting-rules/"
    echo ""
}

# =============================================================================
# Create Custom Alert Rules for Application
# =============================================================================
# Creates a template alert file for the application with common alert patterns.
# User should customize the alerts based on their specific metrics.
# =============================================================================

create_app_alerts() {
    local app_name="$1"
    local alerts_dir="$SCRIPT_DIR/../services/observability/config/alerting-rules"
    local alert_file="$alerts_dir/app-${app_name}.yml"

    # Create alerts directory if it doesn't exist
    mkdir -p "$alerts_dir"

    # Check if file already exists
    if [[ -f "$alert_file" ]]; then
        log_warn "Alert file already exists: app-${app_name}.yml"
        log_info "Edit: $alert_file"
        return
    fi

    # Sanitize app name for Prometheus (replace - with _)
    local prom_name="${app_name//-/_}"

    # Create template alert file
    cat > "$alert_file" << EOF
# =============================================================================
# ${app_name} - Custom Alert Rules
# =============================================================================
# Generated by: app-cli.sh connect ${app_name} --alerts
#
# Customize these alerts based on your application's metrics.
# After editing, reload Prometheus: curl -X POST http://localhost:9090/-/reload
#
# To disable: mv app-${app_name}.yml app-${app_name}.yml.disabled
# =============================================================================

groups:
  - name: ${app_name}
    rules:
      # =========================================================================
      # HTTP Alerts (requires http_requests_total, http_request_duration_seconds)
      # =========================================================================

      # High error rate (5xx errors)
      - alert: ${prom_name}_high_error_rate
        expr: |
          sum(rate(http_requests_total{service="${app_name}", status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="${app_name}"}[5m]))
          * 100 > 5
        for: 5m
        labels:
          severity: critical
          service: ${app_name}
        annotations:
          summary: "High error rate on ${app_name}"
          description: "Error rate is {{ printf \"%.1f\" \$value }}% (threshold: 5%)"

      # High latency (P95 > 1s)
      - alert: ${prom_name}_high_latency
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket{service="${app_name}"}[5m])) by (le)
          ) > 1
        for: 5m
        labels:
          severity: warning
          service: ${app_name}
        annotations:
          summary: "High latency on ${app_name}"
          description: "P95 latency is {{ printf \"%.2f\" \$value }}s (threshold: 1s)"

      # No requests (service may be down)
      - alert: ${prom_name}_no_requests
        expr: |
          sum(rate(http_requests_total{service="${app_name}"}[5m])) == 0
          and sum(http_requests_total{service="${app_name}"}) > 0
        for: 10m
        labels:
          severity: warning
          service: ${app_name}
        annotations:
          summary: "${app_name} receiving no traffic"
          description: "No requests received in the last 10 minutes"

      # =========================================================================
      # Resource Alerts (requires process_* metrics from client library)
      # Uncomment and adjust thresholds as needed
      # =========================================================================

      # High memory usage
      # - alert: ${prom_name}_high_memory
      #   expr: process_resident_memory_bytes{service="${app_name}"} > 512 * 1024 * 1024
      #   for: 5m
      #   labels:
      #     severity: warning
      #     service: ${app_name}
      #   annotations:
      #     summary: "High memory usage on ${app_name}"
      #     description: "Memory usage is {{ humanize \$value }}"

      # =========================================================================
      # Business Alerts (customize based on your app's metrics)
      # Uncomment and modify for your specific use case
      # =========================================================================

      # Example: Queue backlog
      # - alert: ${prom_name}_queue_backlog
      #   expr: ${prom_name}_queue_size > 1000
      #   for: 5m
      #   labels:
      #     severity: warning
      #     service: ${app_name}
      #   annotations:
      #     summary: "Queue backlog on ${app_name}"
      #     description: "{{ \$value }} items in queue"

      # Example: Failed jobs
      # - alert: ${prom_name}_failed_jobs
      #   expr: rate(${prom_name}_jobs_failed_total[5m]) > 0
      #   for: 5m
      #   labels:
      #     severity: warning
      #     service: ${app_name}
      #   annotations:
      #     summary: "Failed jobs on ${app_name}"
      #     description: "{{ printf \"%.2f\" \$value }} failures per second"

      # Example: External API errors
      # - alert: ${prom_name}_external_api_errors
      #   expr: rate(${prom_name}_external_api_errors_total[5m]) > 0.1
      #   for: 5m
      #   labels:
      #     severity: warning
      #     service: ${app_name}
      #   annotations:
      #     summary: "External API errors on ${app_name}"
      #     description: "{{ printf \"%.2f\" \$value }} errors per second"
EOF

    log_info "Created: app-${app_name}.yml"

    # Reload Prometheus if running
    if curl -s -X POST http://localhost:9090/-/reload >/dev/null 2>&1; then
        log_info "Prometheus configuration reloaded"
    fi
}

# =============================================================================
# Connect Command - Register existing container with observability
# =============================================================================
# Supports three monitoring features:
#   1. Metrics: App exposes /metrics endpoint (Prometheus format)
#   2. Tracing: App uses OpenTelemetry SDK for distributed tracing
#   3. Alerts: Custom alert rules for the application
#
# Logging is always automatic via Docker logs → Loki.
# =============================================================================

cmd_connect() {
    local app_name=""
    local port="8080"
    local metrics_path="/metrics"
    local with_metrics=false
    local with_otel=false
    local with_alerts=false
    local show_env=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --port) port="$2"; shift 2 ;;
            --metrics-path) metrics_path="$2"; shift 2 ;;
            --metrics) with_metrics=true; shift ;;
            --otel|--tracing) with_otel=true; shift ;;
            --alerts) with_alerts=true; shift ;;
            --show-env) show_env=true; shift ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) app_name="$1"; shift ;;
        esac
    done

    if [[ -z "$app_name" ]]; then
        log_error "App name required"
        echo ""
        echo "Usage: $0 connect <container-name> [options]"
        echo ""
        echo "Options:"
        echo "  --port <port>          App port (default: 8080)"
        echo "  --metrics              Enable Prometheus metrics scraping"
        echo "  --metrics-path <path>  Metrics endpoint (default: /metrics)"
        echo "  --otel                 Show OTEL tracing setup"
        echo "  --alerts               Create custom alert rules template"
        echo "  --show-env             Output env vars for copy/paste"
        echo ""
        echo "Examples:"
        echo "  $0 connect myapi --port 8080 --metrics"
        echo "  $0 connect myapi --port 8080 --metrics --otel --alerts"
        echo ""
        exit 1
    fi

    # Default: enable metrics if nothing specified
    if [[ "$with_metrics" == "false" && "$with_otel" == "false" && "$with_alerts" == "false" ]]; then
        with_metrics=true
    fi

    log_header "Connecting: $app_name"

    # Check if container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${app_name}$"; then
        log_warn "Container '$app_name' not running. Will register anyway."
    fi

    local enabled_features=""

    # Always enabled: Logging
    enabled_features+="  ✓ Logging  → automatic (stdout/stderr → Loki)\n"

    # Metrics setup
    if [[ "$with_metrics" == "true" ]]; then
        log_step "Registering with Prometheus..."
        add_to_monitoring "$app_name" "$port"
        log_info "Added to targets/applications.json"
        enabled_features+="  ✓ Metrics  → Prometheus scrapes ${app_name}:${port}${metrics_path}\n"
    fi

    # OTEL setup
    if [[ "$with_otel" == "true" ]]; then
        log_step "OTEL tracing configuration..."
        enabled_features+="  ✓ Tracing  → OTEL → Alloy → Tempo\n"
    fi

    # Alert setup
    if [[ "$with_alerts" == "true" ]]; then
        log_step "Creating custom alert rules..."
        create_app_alerts "$app_name"
        enabled_features+="  ✓ Alerts   → Custom rules in alerting-rules/\n"
    fi

    echo ""
    log_header "Configuration Complete"
    echo ""
    echo "Enabled features:"
    echo -e "$enabled_features"

    # Show metrics requirements
    if [[ "$with_metrics" == "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "METRICS SETUP"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Your app must expose ${metrics_path} in Prometheus format."
        echo ""
        echo "Common libraries:"
        echo "  Node.js:  prom-client"
        echo "  Python:   prometheus-client"
        echo "  Go:       prometheus/client_golang"
        echo "  Java:     micrometer-registry-prometheus"
        echo ""
        echo "Basic metrics to expose:"
        echo "  - http_requests_total (counter)"
        echo "  - http_request_duration_seconds (histogram)"
        echo "  - process_cpu_seconds_total"
        echo "  - process_resident_memory_bytes"
        echo ""
    fi

    # Show OTEL requirements
    if [[ "$with_otel" == "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "OTEL TRACING SETUP"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Add these environment variables to your app:"
        echo ""
        if [[ "$show_env" == "true" ]]; then
            echo "OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317"
            echo "OTEL_SERVICE_NAME=${app_name}"
            echo "OTEL_TRACES_EXPORTER=otlp"
            echo "OTEL_METRICS_EXPORTER=none"
            echo "OTEL_LOGS_EXPORTER=none"
        else
            echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317"
            echo "  OTEL_SERVICE_NAME=${app_name}"
            echo "  OTEL_TRACES_EXPORTER=otlp"
            echo "  OTEL_METRICS_EXPORTER=none   # Use Prometheus metrics instead"
            echo "  OTEL_LOGS_EXPORTER=none      # Use Docker logs instead"
        fi
        echo ""
        echo "Common OTEL SDKs:"
        echo "  Node.js:  @opentelemetry/auto-instrumentations-node"
        echo "  Python:   opentelemetry-distro + opentelemetry-exporter-otlp"
        echo "  Go:       go.opentelemetry.io/otel"
        echo "  Java:     opentelemetry-javaagent"
        echo ""
        echo "Quick start (Node.js):"
        echo "  npm install @opentelemetry/auto-instrumentations-node"
        echo "  node --require @opentelemetry/auto-instrumentations-node/register app.js"
        echo ""
    fi

    # Show alerts info
    if [[ "$with_alerts" == "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "CUSTOM ALERTS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Alert file created: services/observability/config/alerting-rules/app-${app_name}.yml"
        echo ""
        echo "Included alerts (customize as needed):"
        echo "  • High error rate (>5% 5xx errors)"
        echo "  • High latency (P95 > 1s)"
        echo "  • No requests (10min)"
        echo ""
        echo "To customize:"
        echo "  1. Edit the alert file"
        echo "  2. Uncomment/add business-specific alerts"
        echo "  3. Reload: curl -X POST http://localhost:9090/-/reload"
        echo ""
        echo "To disable alerts:"
        echo "  mv app-${app_name}.yml app-${app_name}.yml.disabled"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "View in Grafana: http://localhost:3000"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
            redis_pass=$(grep "^REDIS_PASSWORD=" "$INFRA_ROOT/services/redis/.env" | cut -d'=' -f2-)
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
            s3_key=$(grep "^GARAGE_ADMIN_TOKEN=" "$INFRA_ROOT/services/garage/.env" | cut -d'=' -f2-)
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
Application CLI - Connect backends to observability stack

Usage:
  ./scripts/app-cli.sh <command> [options]

Commands:
  connect     Connect existing container to observability
  init        Create .env + docker-compose.yml with database credentials
  reload      Reload Prometheus & Grafana (after adding dashboards/alerts)
  list        List all registered apps
  remove      Remove an app registration

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONNECT - Register existing container with observability

  Use this when you already have a running container and want to connect it
  to monitoring.

  Examples:
    ./scripts/app-cli.sh connect myapi --port 8080 --metrics
    ./scripts/app-cli.sh connect myapi --port 8080 --metrics --otel

  Options:
    --port <port>          App port (default: 8080)
    --metrics              Enable Prometheus metrics scraping
    --metrics-path <path>  Metrics endpoint (default: /metrics)
    --otel                 Show OTEL tracing setup instructions
    --alerts               Create template alert rules (for customization)
    --show-env             Output env vars without indentation (copy-paste)

  What's automatic:
    ✓ Logging  - Docker stdout/stderr → Loki (no code changes)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RELOAD - Reload Prometheus & Grafana after adding custom files

  After copying your dashboard.json or alerts.yml to the correct directories,
  run reload to pick up the changes.

    ./scripts/app-cli.sh reload

  File locations:
    Dashboards: services/observability/dashboards/app-{name}.json
    Alerts:     services/observability/config/alerting-rules/app-{name}.yml

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INIT - Generate complete app setup

  Creates .env + docker-compose.yml with database credentials and
  observability pre-configured. Run this in your app directory.

  # Basic setup with PostgreSQL
  ./scripts/app-cli.sh init myapi --db postgres

  # Full setup with database, Redis, domain, and SSL
  ./scripts/app-cli.sh init myapi --db postgres --redis --domain api.example.com

  Options:
    --db <type>     Database: postgres, mysql, mongo
    --redis         Include Redis credentials
    --s3            Include S3/Garage credentials
    --domain <host> Setup Traefik routing with auto-SSL
    --port <port>   App port (default: 8080)
    --image <name>  Docker image (default: <app-name>:latest)

  Generated .env includes:
    - DATABASE_URL and DB_* variables
    - REDIS_URL (if --redis)
    - S3_ENDPOINT and AWS_* (if --s3)
    - OTEL_* variables for tracing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QUICK DECISION GUIDE

  Which approach should I use?

  Simple REST API with request metrics only:
    → Use --metrics only
    → Add prom-client/prometheus-client to your app
    → Expose /metrics endpoint

  Microservices that call each other:
    → Use --otel for distributed tracing
    → See request flow across services in Tempo

  Production API (recommended):
    → Use both --metrics --otel
    → Get request metrics + distributed traces
    → Full observability

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REQUIREMENTS

  Your docker-compose.yml MUST connect to the infra network:

    services:
      myapi:
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
        reload)
            reload_observability
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
