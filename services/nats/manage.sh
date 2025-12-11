#!/bin/bash
# =============================================================================
# NATS Tenant Management Script
# =============================================================================
# Production-grade script for managing NATS accounts/tenants and users
#
# Usage:
#   ./manage.sh add-tenant <name>                    Add new tenant
#   ./manage.sh add-user <tenant> <user> [options]  Add user to tenant
#   ./manage.sh list                                 List all tenants/users
#   ./manage.sh show <tenant> [user]                Show connection info
#   ./manage.sh remove-user <tenant> <user>         Remove user
#   ./manage.sh remove-tenant <tenant>              Remove tenant
#   ./manage.sh test <tenant> [user]                Test connection
#   ./manage.sh reload                              Reload NATS config
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load shared library and require authentication
if [[ -f "$INFRA_ROOT/lib/common.sh" ]]; then
    source "$INFRA_ROOT/lib/common.sh"
    require_auth
fi
CONFIG_DIR="$SCRIPT_DIR/config"
TENANTS_DIR="$CONFIG_DIR/tenants"
CREDENTIALS_DIR="$SCRIPT_DIR/.credentials"
AUTH_CONF="$CONFIG_DIR/auth.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[→]${NC} $1"; }

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

validate_name() {
    local name="$1"
    local type="$2"
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,62}$ ]]; then
        log_error "$type name must start with letter, contain only alphanumeric, dash, underscore (max 63 chars)"
        exit 1
    fi
}

ensure_dirs() {
    mkdir -p "$TENANTS_DIR" "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"
}

# =============================================================================
# Tenant Management
# =============================================================================

add_tenant() {
    local tenant_name="$1"
    local memory_limit="${2:-64MB}"
    local storage_limit="${3:-5GB}"

    validate_name "$tenant_name" "Tenant"
    ensure_dirs

    local tenant_upper=$(to_upper "$tenant_name")
    local tenant_lower=$(to_lower "$tenant_name")
    local tenant_file="$TENANTS_DIR/${tenant_lower}.conf"
    local cred_file="$CREDENTIALS_DIR/${tenant_lower}.env"

    if [[ -f "$tenant_file" ]]; then
        log_error "Tenant '$tenant_name' already exists"
        exit 1
    fi

    log_step "Creating tenant: $tenant_name"

    # Generate admin password
    local admin_password=$(generate_password)

    # Create tenant config
    cat > "$tenant_file" << EOF
# =============================================================================
# Tenant: $tenant_upper
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

    $tenant_upper: {
        users: [
            {
                user: "$tenant_lower"
                password: "$admin_password"
                # Admin user - full access within this tenant
            }
        ]

        # JetStream resource limits for this tenant
        jetstream: {
            max_memory: $memory_limit
            max_store: $storage_limit
            max_streams: 50
            max_consumers: 500
        }
    }
EOF

    # Save credentials
    cat > "$cred_file" << EOF
# Tenant: $tenant_name
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
NATS_TENANT=$tenant_lower
NATS_USER=$tenant_lower
NATS_PASSWORD=$admin_password
NATS_URL=nats://${tenant_lower}:${admin_password}@localhost:4222
NATS_ACCOUNT=$tenant_upper
EOF
    chmod 600 "$cred_file"

    # Rebuild auth.conf
    rebuild_auth_conf

    # Reload NATS
    reload_nats

    log_info "Tenant '$tenant_name' created successfully"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}Connection Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  User:     $tenant_lower"
    echo "  Password: $admin_password"
    echo "  URL:      nats://${tenant_lower}:${admin_password}@localhost:4222"
    echo ""
    echo "  Credentials saved to: $cred_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

add_user() {
    local tenant_name="$1"
    local user_name="$2"
    shift 2

    # Parse options
    local publish_subjects=""
    local subscribe_subjects=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --publish|-p)
                publish_subjects="$2"
                shift 2
                ;;
            --subscribe|-s)
                subscribe_subjects="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    validate_name "$tenant_name" "Tenant"
    validate_name "$user_name" "User"
    ensure_dirs

    local tenant_upper=$(to_upper "$tenant_name")
    local tenant_lower=$(to_lower "$tenant_name")
    local user_lower=$(to_lower "$user_name")
    local tenant_file="$TENANTS_DIR/${tenant_lower}.conf"
    local cred_file="$CREDENTIALS_DIR/${tenant_lower}_${user_lower}.env"

    if [[ ! -f "$tenant_file" ]]; then
        log_error "Tenant '$tenant_name' does not exist"
        exit 1
    fi

    # Check if user already exists
    if grep -q "user: \"$user_lower\"" "$tenant_file" 2>/dev/null; then
        log_error "User '$user_name' already exists in tenant '$tenant_name'"
        exit 1
    fi

    log_step "Adding user '$user_name' to tenant '$tenant_name'"

    # Generate password
    local password=$(generate_password)

    # Build user config
    local user_config=""
    if [[ -n "$publish_subjects" ]] || [[ -n "$subscribe_subjects" ]]; then
        # User with permissions
        local pub_array=""
        local sub_array=""

        if [[ -n "$publish_subjects" ]]; then
            pub_array=$(echo "$publish_subjects" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
        fi
        if [[ -n "$subscribe_subjects" ]]; then
            sub_array=$(echo "$subscribe_subjects" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
        fi

        user_config="            {
                user: \"$user_lower\"
                password: \"$password\"
                permissions: {
                    publish: [${pub_array:-}]
                    subscribe: [${sub_array:-\">\"}]
                }
            }"
    else
        # User with full access
        user_config="            {
                user: \"$user_lower\"
                password: \"$password\"
            }"
    fi

    # Insert user into tenant config (before the closing bracket of users array)
    # Find the line with just "]" after users: [ and insert before it
    local temp_file=$(mktemp)
    awk -v user="$user_config" '
        /users: \[/ { in_users=1 }
        in_users && /^        \]/ {
            print user ","
            in_users=0
        }
        { print }
    ' "$tenant_file" > "$temp_file"
    mv "$temp_file" "$tenant_file"

    # Save credentials
    cat > "$cred_file" << EOF
# Tenant: $tenant_name / User: $user_name
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
NATS_TENANT=$tenant_lower
NATS_USER=$user_lower
NATS_PASSWORD=$password
NATS_URL=nats://${user_lower}:${password}@localhost:4222
NATS_ACCOUNT=$tenant_upper
NATS_PUBLISH=${publish_subjects:-"*"}
NATS_SUBSCRIBE=${subscribe_subjects:-">"}
EOF
    chmod 600 "$cred_file"

    # Reload NATS
    reload_nats

    log_info "User '$user_name' added to tenant '$tenant_name'"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}Connection Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Tenant:   $tenant_name"
    echo "  User:     $user_lower"
    echo "  Password: $password"
    echo "  URL:      nats://${user_lower}:${password}@localhost:4222"
    if [[ -n "$publish_subjects" ]]; then
        echo "  Publish:  $publish_subjects"
    fi
    if [[ -n "$subscribe_subjects" ]]; then
        echo "  Subscribe: $subscribe_subjects"
    fi
    echo ""
    echo "  Credentials saved to: $cred_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

remove_tenant() {
    local tenant_name="$1"
    local tenant_lower=$(to_lower "$tenant_name")
    local tenant_file="$TENANTS_DIR/${tenant_lower}.conf"

    if [[ ! -f "$tenant_file" ]]; then
        log_error "Tenant '$tenant_name' does not exist"
        exit 1
    fi

    log_warn "This will remove tenant '$tenant_name' and ALL its users!"
    read -p "Are you sure? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Removing tenant: $tenant_name"

    # Remove tenant config
    rm -f "$tenant_file"

    # Remove all credential files for this tenant
    rm -f "$CREDENTIALS_DIR/${tenant_lower}"*.env

    # Rebuild auth.conf
    rebuild_auth_conf

    # Reload NATS
    reload_nats

    log_info "Tenant '$tenant_name' removed successfully"
}

remove_user() {
    local tenant_name="$1"
    local user_name="$2"
    local tenant_lower=$(to_lower "$tenant_name")
    local user_lower=$(to_lower "$user_name")
    local tenant_file="$TENANTS_DIR/${tenant_lower}.conf"
    local cred_file="$CREDENTIALS_DIR/${tenant_lower}_${user_lower}.env"

    if [[ ! -f "$tenant_file" ]]; then
        log_error "Tenant '$tenant_name' does not exist"
        exit 1
    fi

    if ! grep -q "user: \"$user_lower\"" "$tenant_file" 2>/dev/null; then
        log_error "User '$user_name' does not exist in tenant '$tenant_name'"
        exit 1
    fi

    # Don't allow removing the admin user (same name as tenant)
    if [[ "$user_lower" == "$tenant_lower" ]]; then
        log_error "Cannot remove admin user. Use 'remove-tenant' to remove the entire tenant."
        exit 1
    fi

    log_step "Removing user '$user_name' from tenant '$tenant_name'"

    # Remove user block from config (this is simplified - may need adjustment for complex configs)
    local temp_file=$(mktemp)
    awk -v user="$user_lower" '
        BEGIN { skip=0; brace_count=0 }
        /user: "'"$user_lower"'"/ { skip=1; brace_count=1; next }
        skip && /{/ { brace_count++ }
        skip && /}/ { brace_count--; if(brace_count==0) { skip=0; next } }
        !skip { print }
    ' "$tenant_file" > "$temp_file"
    mv "$temp_file" "$tenant_file"

    # Remove credential file
    rm -f "$cred_file"

    # Reload NATS
    reload_nats

    log_info "User '$user_name' removed from tenant '$tenant_name'"
}

# =============================================================================
# List and Show
# =============================================================================

list_tenants() {
    ensure_dirs

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  NATS Tenants and Users"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ ! -d "$TENANTS_DIR" ]] || [[ -z "$(ls -A "$TENANTS_DIR" 2>/dev/null)" ]]; then
        echo "  No tenants configured"
        echo ""
        echo "  Create one with: ./manage.sh add-tenant <name>"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    for tenant_file in "$TENANTS_DIR"/*.conf; do
        [[ -f "$tenant_file" ]] || continue

        local tenant_name=$(basename "$tenant_file" .conf)
        local tenant_upper=$(to_upper "$tenant_name")

        echo ""
        echo -e "  ${GREEN}$tenant_upper${NC}"

        # Extract users from config
        grep -E "user:" "$tenant_file" | while read -r line; do
            local user=$(echo "$line" | sed 's/.*user: "\([^"]*\)".*/\1/')

            # Check for permissions
            if grep -A5 "user: \"$user\"" "$tenant_file" | grep -q "permissions:"; then
                local pub=$(grep -A10 "user: \"$user\"" "$tenant_file" | grep -A1 "publish:" | tail -1 | tr -d '[]" ' | head -c 50)
                local sub=$(grep -A10 "user: \"$user\"" "$tenant_file" | grep -A1 "subscribe:" | tail -1 | tr -d '[]" ' | head -c 50)
                echo "    ├─ $user (publish: ${pub:-none}, subscribe: ${sub:-none})"
            else
                echo "    ├─ $user (full access)"
            fi
        done
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

show_tenant() {
    local tenant_name="$1"
    local user_name="${2:-}"
    local tenant_lower=$(to_lower "$tenant_name")

    local cred_file
    if [[ -n "$user_name" ]]; then
        local user_lower=$(to_lower "$user_name")
        cred_file="$CREDENTIALS_DIR/${tenant_lower}_${user_lower}.env"
    else
        cred_file="$CREDENTIALS_DIR/${tenant_lower}.env"
    fi

    if [[ ! -f "$cred_file" ]]; then
        log_error "Credentials not found for tenant '$tenant_name'${user_name:+ user '$user_name'}"
        exit 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}Connection Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$cred_file" | grep -v "^#" | while read -r line; do
        [[ -n "$line" ]] && echo "  $line"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# Config Management
# =============================================================================

rebuild_auth_conf() {
    log_step "Rebuilding auth.conf..."

    cat > "$AUTH_CONF" << 'EOF'
# =============================================================================
# NATS Authentication Configuration
# =============================================================================
# AUTO-GENERATED - Do not edit directly!
# Use manage.sh to add/remove tenants and users
# =============================================================================

accounts {
    # -------------------------------------------------------------------------
    # System Account (required for NATS internals)
    # -------------------------------------------------------------------------
    SYS: {
        users: [
            {
                user: "sys"
                password: $NATS_SYS_PASSWORD
            }
        ]
    }

EOF

    # Append all tenant configs
    if [[ -d "$TENANTS_DIR" ]]; then
        for tenant_file in "$TENANTS_DIR"/*.conf; do
            [[ -f "$tenant_file" ]] || continue
            echo "    # --- $(basename "$tenant_file") ---" >> "$AUTH_CONF"
            grep -v "^#" "$tenant_file" | grep -v "^$" >> "$AUTH_CONF"
            echo "" >> "$AUTH_CONF"
        done
    fi

    # Close accounts block
    cat >> "$AUTH_CONF" << 'EOF'
}

# System account designation
system_account: SYS
EOF

    log_info "auth.conf rebuilt"
}

reload_nats() {
    log_step "Reloading NATS..."

    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps --quiet nats >/dev/null 2>&1; then
        docker compose -f "$SCRIPT_DIR/docker-compose.yml" restart nats >/dev/null 2>&1
        sleep 2

        # Check if NATS is healthy
        if docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps nats | grep -q "healthy"; then
            log_info "NATS reloaded successfully"
        else
            log_warn "NATS may not be fully ready yet"
        fi
    else
        log_warn "NATS is not running. Start it with: docker compose up -d"
    fi
}

test_connection() {
    local tenant_name="$1"
    local user_name="${2:-}"
    local tenant_lower=$(to_lower "$tenant_name")

    local cred_file
    if [[ -n "$user_name" ]]; then
        local user_lower=$(to_lower "$user_name")
        cred_file="$CREDENTIALS_DIR/${tenant_lower}_${user_lower}.env"
    else
        cred_file="$CREDENTIALS_DIR/${tenant_lower}.env"
    fi

    if [[ ! -f "$cred_file" ]]; then
        log_error "Credentials not found"
        exit 1
    fi

    source "$cred_file"

    log_step "Testing connection for $NATS_USER..."

    # Try using nats-box if available
    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps --quiet nats-box >/dev/null 2>&1; then
        if docker compose -f "$SCRIPT_DIR/docker-compose.yml" exec -T nats-box \
            nats server ping --server="$NATS_URL" 2>/dev/null; then
            log_info "Connection successful!"
        else
            log_error "Connection failed"
            exit 1
        fi
    else
        # Fall back to curl health check
        if curl -sf "http://localhost:8222/healthz" >/dev/null 2>&1; then
            log_info "NATS server is healthy (credential test requires nats-box)"
            log_info "Enable nats-box: docker compose --profile tools up -d"
        else
            log_error "NATS server is not responding"
            exit 1
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat << EOF
NATS Tenant Management Script

Usage:
  ./manage.sh <command> [arguments]

Commands:
  add-tenant <name> [memory] [storage]
      Create a new tenant with admin user
      Example: ./manage.sh add-tenant myapp 128MB 10GB

  add-user <tenant> <user> [options]
      Add user to existing tenant
      Options:
        --publish, -p <subjects>    Comma-separated publish subjects
        --subscribe, -s <subjects>  Comma-separated subscribe subjects
      Example: ./manage.sh add-user myapp worker -p "jobs.*,results.*" -s "tasks.*"

  list
      List all tenants and users

  show <tenant> [user]
      Show connection details for tenant or specific user

  remove-user <tenant> <user>
      Remove user from tenant

  remove-tenant <tenant>
      Remove tenant and all its users

  test <tenant> [user]
      Test connection to NATS

  reload
      Rebuild config and reload NATS

Examples:
  # Create a tenant for your app
  ./manage.sh add-tenant myapp

  # Add a service with restricted permissions
  ./manage.sh add-user myapp order-service -p "orders.*" -s "payments.*,inventory.*"

  # Show connection string
  ./manage.sh show myapp order-service

  # List everything
  ./manage.sh list
EOF
}

main() {
    local command="${1:-}"

    case "$command" in
        add-tenant)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            add_tenant "$2" "${3:-64MB}" "${4:-5GB}"
            ;;
        add-user)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            [[ -z "${3:-}" ]] && { log_error "User name required"; usage; exit 1; }
            add_user "${@:2}"
            ;;
        remove-tenant)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            remove_tenant "$2"
            ;;
        remove-user)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            [[ -z "${3:-}" ]] && { log_error "User name required"; usage; exit 1; }
            remove_user "$2" "$3"
            ;;
        list)
            list_tenants
            ;;
        show)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            show_tenant "$2" "${3:-}"
            ;;
        test)
            [[ -z "${2:-}" ]] && { log_error "Tenant name required"; usage; exit 1; }
            test_connection "$2" "${3:-}"
            ;;
        reload)
            rebuild_auth_conf
            reload_nats
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            [[ -n "$command" ]] && log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
