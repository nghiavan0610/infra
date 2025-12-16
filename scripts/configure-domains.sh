#!/bin/bash
# =============================================================================
# Domain Configuration Script
# =============================================================================
# Configure all service domains at once for Traefik reverse proxy.
#
# Usage:
#   ./scripts/configure-domains.sh <base-domain>
#   ./scripts/configure-domains.sh hakomputing.com
#   ./scripts/configure-domains.sh example.com --dry-run
#
# This will configure:
#   api.<domain>      → Your backend API (hirestack)
#   grafana.<domain>  → Grafana monitoring
#   traefik.<domain>  → Traefik dashboard
#   status.<domain>   → Uptime Kuma
#   ntfy.<domain>     → Push notifications
#   prometheus.<domain> → Prometheus (optional)
#   alertmanager.<domain> → Alertmanager (optional)
# =============================================================================

set -e

# Resolve script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"

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
# Helper Functions
# =============================================================================

# Set or update env variable in file
set_env_var() {
    local file="$1"
    local key="$2"
    local value="$3"

    # Create file if doesn't exist
    [[ ! -f "$file" ]] && touch "$file"

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Update existing
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        fi
    else
        # Add new
        echo "${key}=${value}" >> "$file"
    fi
}

# Check if container is running
is_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# =============================================================================
# Main Configuration
# =============================================================================

configure_domains() {
    local BASE_DOMAIN="$1"
    local DRY_RUN="${2:-false}"

    if [[ -z "$BASE_DOMAIN" ]]; then
        log_error "Base domain required"
        echo ""
        echo "Usage: $0 <base-domain> [--dry-run]"
        echo ""
        echo "Example:"
        echo "  $0 hakomputing.com"
        echo "  $0 example.com --dry-run"
        exit 1
    fi

    log_header "Configuring Domains for: $BASE_DOMAIN"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN - No changes will be made"
        echo ""
    fi

    # Define domain mappings
    declare -A DOMAINS=(
        ["api"]="api.${BASE_DOMAIN}"
        ["grafana"]="grafana.${BASE_DOMAIN}"
        ["traefik"]="traefik.${BASE_DOMAIN}"
        ["status"]="status.${BASE_DOMAIN}"
        ["ntfy"]="ntfy.${BASE_DOMAIN}"
        ["prometheus"]="prometheus.${BASE_DOMAIN}"
        ["alertmanager"]="alertmanager.${BASE_DOMAIN}"
    )

    echo "Domain mappings:"
    echo ""
    printf "  %-15s → %s\n" "Service" "Domain"
    echo "  ─────────────────────────────────────────"
    for service in api grafana traefik status ntfy; do
        printf "  %-15s → %s\n" "$service" "${DOMAINS[$service]}"
    done
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run complete. Run without --dry-run to apply."
        exit 0
    fi

    # Track services to restart
    local RESTART_SERVICES=()

    # -------------------------------------------------------------------------
    # Fix acme.json permissions
    # -------------------------------------------------------------------------
    local ACME_JSON="$INFRA_ROOT/services/traefik/certs/acme.json"
    if [[ -f "$ACME_JSON" ]]; then
        chmod 600 "$ACME_JSON"
        log_info "Fixed acme.json permissions (600)"
    fi

    # -------------------------------------------------------------------------
    # Generate default SSL certificate (for Cloudflare Full mode)
    # -------------------------------------------------------------------------
    local CERTS_DIR="$INFRA_ROOT/services/traefik/certs"
    local CERT_FILE="$CERTS_DIR/default.pem"
    local KEY_FILE="$CERTS_DIR/default.key"

    if [[ ! -f "$CERT_FILE" ]] || [[ ! -f "$KEY_FILE" ]]; then
        log_step "Generating default SSL certificate..."
        mkdir -p "$CERTS_DIR"

        # Generate self-signed cert valid for 10 years
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$KEY_FILE" \
            -out "$CERT_FILE" \
            -subj "/CN=*.${BASE_DOMAIN}/O=Infra/C=US" \
            -addext "subjectAltName=DNS:*.${BASE_DOMAIN},DNS:${BASE_DOMAIN}" \
            2>/dev/null

        chmod 600 "$KEY_FILE"
        chmod 644 "$CERT_FILE"
        log_info "Generated default SSL certificate for *.${BASE_DOMAIN}"
    fi

    # Create TLS config for Traefik to use this certificate
    local TRAEFIK_DYNAMIC="$INFRA_ROOT/services/traefik/config/dynamic"
    mkdir -p "$TRAEFIK_DYNAMIC"

    cat > "$TRAEFIK_DYNAMIC/default-cert.yml" << EOF
# Auto-generated default certificate for Cloudflare Full mode
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/certs/default.pem
        keyFile: /etc/traefik/certs/default.key
  certificates:
    - certFile: /etc/traefik/certs/default.pem
      keyFile: /etc/traefik/certs/default.key
EOF
    log_info "Created default TLS config for Traefik"

    # -------------------------------------------------------------------------
    # Check/Update ACME Email
    # -------------------------------------------------------------------------
    local TRAEFIK_ENV="$INFRA_ROOT/services/traefik/.env"
    local current_email=$(grep "^ACME_EMAIL=" "$TRAEFIK_ENV" 2>/dev/null | cut -d'=' -f2)

    if [[ -z "$current_email" || "$current_email" == "admin@example.com" || "$current_email" == *"example"* ]]; then
        log_warn "ACME_EMAIL not configured properly"
        echo ""
        read -p "Enter your email for Let's Encrypt certificates: " acme_email
        if [[ -n "$acme_email" ]]; then
            set_env_var "$TRAEFIK_ENV" "ACME_EMAIL" "$acme_email"
            log_info "ACME_EMAIL set to: $acme_email"
        fi
        echo ""
    fi

    # -------------------------------------------------------------------------
    # Traefik Dashboard
    # -------------------------------------------------------------------------
    log_step "Configuring Traefik..."
    local TRAEFIK_ENV="$INFRA_ROOT/services/traefik/.env"

    if [[ -d "$INFRA_ROOT/services/traefik" ]]; then
        set_env_var "$TRAEFIK_ENV" "TRAEFIK_DASHBOARD_HOST" "${DOMAINS[traefik]}"
        log_info "Traefik dashboard: https://${DOMAINS[traefik]}"
        RESTART_SERVICES+=("traefik")
    else
        log_warn "Traefik not found, skipping"
    fi

    # -------------------------------------------------------------------------
    # Grafana
    # -------------------------------------------------------------------------
    log_step "Configuring Grafana..."
    local OBS_ENV="$INFRA_ROOT/services/observability/.env"

    if [[ -d "$INFRA_ROOT/services/observability" ]]; then
        set_env_var "$OBS_ENV" "GRAFANA_ROOT_URL" "https://${DOMAINS[grafana]}"
        set_env_var "$OBS_ENV" "GRAFANA_DOMAIN" "${DOMAINS[grafana]}"

        # Also add Traefik labels to enable routing
        local OBS_COMPOSE="$INFRA_ROOT/services/observability/docker-compose.yml"
        if ! grep -q "traefik.http.routers.grafana" "$OBS_COMPOSE" 2>/dev/null; then
            log_warn "Grafana Traefik labels not found in docker-compose.yml"
            log_warn "Add these labels to grafana service manually or use Traefik file provider"
        fi

        log_info "Grafana: https://${DOMAINS[grafana]}"
        RESTART_SERVICES+=("grafana")
    else
        log_warn "Observability stack not found, skipping"
    fi

    # -------------------------------------------------------------------------
    # Uptime Kuma (Status Page)
    # -------------------------------------------------------------------------
    log_step "Configuring Uptime Kuma..."
    local UPTIME_ENV="$INFRA_ROOT/services/uptime-kuma/.env"

    if [[ -d "$INFRA_ROOT/services/uptime-kuma" ]]; then
        set_env_var "$UPTIME_ENV" "UPTIME_KUMA_DOMAIN" "${DOMAINS[status]}"
        log_info "Status page: https://${DOMAINS[status]}"
        RESTART_SERVICES+=("uptime-kuma")
    else
        log_warn "Uptime Kuma not found, skipping"
    fi

    # -------------------------------------------------------------------------
    # Ntfy (Push Notifications)
    # -------------------------------------------------------------------------
    log_step "Configuring Ntfy..."
    local NTFY_ENV="$INFRA_ROOT/services/ntfy/.env"

    if [[ -d "$INFRA_ROOT/services/ntfy" ]]; then
        set_env_var "$NTFY_ENV" "NTFY_BASE_URL" "https://${DOMAINS[ntfy]}"
        set_env_var "$NTFY_ENV" "NTFY_DOMAIN" "${DOMAINS[ntfy]}"
        log_info "Ntfy: https://${DOMAINS[ntfy]}"
        RESTART_SERVICES+=("ntfy")
    else
        log_warn "Ntfy not found, skipping"
    fi

    # -------------------------------------------------------------------------
    # Create Traefik Dynamic Config for Services
    # -------------------------------------------------------------------------
    log_step "Creating Traefik routing rules..."

    local TRAEFIK_DYNAMIC="$INFRA_ROOT/services/traefik/config/dynamic"
    mkdir -p "$TRAEFIK_DYNAMIC"

    # Grafana route
    cat > "$TRAEFIK_DYNAMIC/grafana.yml" << EOF
# Auto-generated by configure-domains.sh
http:
  routers:
    grafana:
      rule: "Host(\`${DOMAINS[grafana]}\`)"
      entrypoints:
        - websecure
      service: grafana
      tls:
        certResolver: letsencrypt
  services:
    grafana:
      loadBalancer:
        servers:
          - url: "http://grafana:3000"
EOF
    log_info "Created grafana.yml"

    # Uptime Kuma route
    cat > "$TRAEFIK_DYNAMIC/uptime-kuma.yml" << EOF
# Auto-generated by configure-domains.sh
http:
  routers:
    uptime-kuma:
      rule: "Host(\`${DOMAINS[status]}\`)"
      entrypoints:
        - websecure
      service: uptime-kuma
      tls:
        certResolver: letsencrypt
  services:
    uptime-kuma:
      loadBalancer:
        servers:
          - url: "http://uptime-kuma:3001"
EOF
    log_info "Created uptime-kuma.yml"

    # Ntfy route
    cat > "$TRAEFIK_DYNAMIC/ntfy.yml" << EOF
# Auto-generated by configure-domains.sh
http:
  routers:
    ntfy:
      rule: "Host(\`${DOMAINS[ntfy]}\`)"
      entrypoints:
        - websecure
      service: ntfy
      tls:
        certResolver: letsencrypt
  services:
    ntfy:
      loadBalancer:
        servers:
          - url: "http://ntfy:80"
EOF
    log_info "Created ntfy.yml"

    # -------------------------------------------------------------------------
    # Save domain config for reference
    # -------------------------------------------------------------------------
    cat > "$INFRA_ROOT/.domains" << EOF
# Domain configuration - Generated $(date)
BASE_DOMAIN=${BASE_DOMAIN}

# Service URLs
API_URL=https://${DOMAINS[api]}
GRAFANA_URL=https://${DOMAINS[grafana]}
TRAEFIK_URL=https://${DOMAINS[traefik]}
STATUS_URL=https://${DOMAINS[status]}
NTFY_URL=https://${DOMAINS[ntfy]}
EOF
    log_info "Saved domain config to .domains"

    # -------------------------------------------------------------------------
    # Restart Services
    # -------------------------------------------------------------------------
    log_header "Restarting Services"

    # Always restart Traefik to pick up new dynamic config
    if is_running "traefik"; then
        log_step "Restarting Traefik..."
        docker restart traefik >/dev/null 2>&1
        log_info "Traefik restarted"
    fi

    # Restart other services if running
    for service in grafana uptime-kuma ntfy; do
        if is_running "$service"; then
            log_step "Restarting $service..."
            docker restart "$service" >/dev/null 2>&1
            log_info "$service restarted"
        fi
    done

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    log_header "Configuration Complete!"

    echo "Your services are now available at:"
    echo ""
    echo "  Traefik Dashboard:  https://${DOMAINS[traefik]}"
    echo "  Grafana:            https://${DOMAINS[grafana]}"
    echo "  Status Page:        https://${DOMAINS[status]}"
    echo "  Ntfy:               https://${DOMAINS[ntfy]}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "For your backend API (hirestack), add to your .env:"
    echo ""
    echo "  API_DOMAIN=${DOMAINS[api]}"
    echo ""
    echo "Then redeploy: docker compose -f docker-compose.prod.yml up -d"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Cloudflare Settings (if using Cloudflare):"
    echo "  1. SSL/TLS → Overview → Set to 'Full (strict)'"
    echo "  2. Ensure all subdomains have A records pointing to your server"
    echo ""
}

# =============================================================================
# CLI Entry Point
# =============================================================================

main() {
    local domain=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 <base-domain> [--dry-run]"
                echo ""
                echo "Configure all service domains for Traefik reverse proxy."
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be configured without making changes"
                echo "  --help       Show this help"
                echo ""
                echo "Example:"
                echo "  $0 hakomputing.com"
                echo "  $0 example.com --dry-run"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                domain="$1"
                shift
                ;;
        esac
    done

    configure_domains "$domain" "$dry_run"
}

main "$@"
