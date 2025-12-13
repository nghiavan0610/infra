#!/bin/bash
# =============================================================================
# RabbitMQ Vhost/Tenant Management Script
# =============================================================================
# Production-grade script for managing RabbitMQ vhosts and users
#
# Usage:
#   ./manage.sh add-vhost <name>                      Add new vhost (tenant)
#   ./manage.sh add-user <vhost> <user> [options]    Add user to vhost
#   ./manage.sh list                                  List all vhosts/users
#   ./manage.sh show <vhost> [user]                  Show connection info
#   ./manage.sh remove-user <vhost> <user>           Remove user
#   ./manage.sh remove-vhost <vhost>                 Remove vhost
#   ./manage.sh test <vhost> [user]                  Test connection
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load shared library and require authentication
if [[ -f "$INFRA_ROOT/lib/common.sh" ]]; then
    source "$INFRA_ROOT/lib/common.sh"
    require_auth
fi
CREDENTIALS_DIR="$SCRIPT_DIR/.credentials"
ENV_FILE="$SCRIPT_DIR/.env"

# RabbitMQ API settings
RABBITMQ_API_HOST="${RABBITMQ_API_HOST:-localhost}"
RABBITMQ_API_PORT="${RABBITMQ_MANAGEMENT_PORT:-15672}"
RABBITMQ_API_URL="http://${RABBITMQ_API_HOST}:${RABBITMQ_API_PORT}/api"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"
}

load_admin_credentials() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    ADMIN_USER="${RABBITMQ_ADMIN_USER:-admin}"
    ADMIN_PASS="${RABBITMQ_ADMIN_PASS:-}"

    if [[ -z "$ADMIN_PASS" ]]; then
        log_error "RABBITMQ_ADMIN_PASS not set. Check .env file."
        exit 1
    fi
}

# URL encode a string
urlencode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))"
}

# Make API call to RabbitMQ
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(
        -s
        -X "$method"
        -u "${ADMIN_USER}:${ADMIN_PASS}"
        -H "Content-Type: application/json"
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" "${RABBITMQ_API_URL}${endpoint}"
}

# Check if RabbitMQ API is available
check_api() {
    if ! curl -sf -u "${ADMIN_USER}:${ADMIN_PASS}" "${RABBITMQ_API_URL}/overview" > /dev/null 2>&1; then
        log_error "Cannot connect to RabbitMQ API at ${RABBITMQ_API_URL}"
        log_error "Make sure RabbitMQ is running and credentials are correct"
        exit 1
    fi
}

# =============================================================================
# Vhost Management
# =============================================================================

add_vhost() {
    local vhost_name="$1"
    local description="${2:-Managed by manage.sh}"

    validate_name "$vhost_name" "Vhost"
    ensure_dirs
    load_admin_credentials
    check_api

    local vhost_lower=$(to_lower "$vhost_name")
    local cred_file="$CREDENTIALS_DIR/${vhost_lower}.env"

    # Check if vhost already exists
    local existing=$(api_call GET "/vhosts/$(urlencode "$vhost_lower")" 2>/dev/null || echo "")
    if [[ "$existing" == *"\"name\""* ]]; then
        log_error "Vhost '$vhost_lower' already exists"
        exit 1
    fi

    log_step "Creating vhost: $vhost_lower"

    # Create vhost
    api_call PUT "/vhosts/$(urlencode "$vhost_lower")" "{\"description\": \"$description\", \"tags\": \"production\"}" > /dev/null

    # Generate admin password for this vhost
    local admin_password=$(generate_password)
    local admin_user="${vhost_lower}-admin"

    # Create admin user for this vhost
    log_step "Creating admin user: $admin_user"
    api_call PUT "/users/$(urlencode "$admin_user")" "{\"password\": \"$admin_password\", \"tags\": \"administrator\"}" > /dev/null

    # Set permissions (full access to this vhost only)
    api_call PUT "/permissions/$(urlencode "$vhost_lower")/$(urlencode "$admin_user")" \
        '{"configure": ".*", "write": ".*", "read": ".*"}' > /dev/null

    # Create default exchanges for the vhost
    log_step "Creating default exchanges..."
    api_call PUT "/exchanges/$(urlencode "$vhost_lower")/events" \
        '{"type": "topic", "durable": true}' > /dev/null
    api_call PUT "/exchanges/$(urlencode "$vhost_lower")/commands" \
        '{"type": "direct", "durable": true}' > /dev/null
    api_call PUT "/exchanges/$(urlencode "$vhost_lower")/dlx" \
        '{"type": "direct", "durable": true}' > /dev/null

    # Create DLX queue
    api_call PUT "/queues/$(urlencode "$vhost_lower")/dlx.queue" \
        '{"durable": true, "arguments": {"x-queue-type": "classic"}}' > /dev/null
    api_call POST "/bindings/$(urlencode "$vhost_lower")/e/dlx/q/dlx.queue" \
        '{"routing_key": "dlx"}' > /dev/null

    # Save credentials
    local password_encoded=$(urlencode "$admin_password")
    cat > "$cred_file" << EOF
# RabbitMQ Vhost: $vhost_lower
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
RABBITMQ_VHOST=$vhost_lower
RABBITMQ_USER=$admin_user
RABBITMQ_PASSWORD=$admin_password
RABBITMQ_URL=amqp://${admin_user}:${password_encoded}@localhost:5672/${vhost_lower}
RABBITMQ_MANAGEMENT_URL=http://localhost:15672/#/vhosts/${vhost_lower}
EOF
    chmod 600 "$cred_file"

    log_info "Vhost '$vhost_lower' created successfully"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}Connection Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Vhost:    $vhost_lower"
    echo "  User:     $admin_user"
    echo "  Password: $admin_password"
    echo "  URL:      amqp://${admin_user}:****@localhost:5672/${vhost_lower}"
    echo ""
    echo "  Default exchanges created:"
    echo "    - events  (topic)   - for event publishing"
    echo "    - commands (direct) - for RPC/commands"
    echo "    - dlx (direct)      - dead letter exchange"
    echo ""
    echo "  Credentials saved to: $cred_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

add_user() {
    local vhost_name="$1"
    local user_name="$2"
    shift 2

    # Parse options
    local configure_pattern=".*"
    local write_pattern=".*"
    local read_pattern=".*"
    local tags=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --configure|-c)
                configure_pattern="$2"
                shift 2
                ;;
            --write|-w)
                write_pattern="$2"
                shift 2
                ;;
            --read|-r)
                read_pattern="$2"
                shift 2
                ;;
            --tags|-t)
                tags="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    validate_name "$vhost_name" "Vhost"
    validate_name "$user_name" "User"
    ensure_dirs
    load_admin_credentials
    check_api

    local vhost_lower=$(to_lower "$vhost_name")
    local user_lower=$(to_lower "$user_name")
    local cred_file="$CREDENTIALS_DIR/${vhost_lower}_${user_lower}.env"

    # Check if vhost exists
    local existing=$(api_call GET "/vhosts/$(urlencode "$vhost_lower")" 2>/dev/null || echo "")
    if [[ "$existing" != *"\"name\""* ]]; then
        log_error "Vhost '$vhost_lower' does not exist. Create it first with: ./manage.sh add-vhost $vhost_lower"
        exit 1
    fi

    # Check if user already exists
    local existing_user=$(api_call GET "/users/$(urlencode "$user_lower")" 2>/dev/null || echo "")
    if [[ "$existing_user" == *"\"name\""* ]]; then
        log_error "User '$user_lower' already exists"
        exit 1
    fi

    log_step "Creating user '$user_lower' for vhost '$vhost_lower'"

    # Generate password
    local password=$(generate_password)

    # Create user
    api_call PUT "/users/$(urlencode "$user_lower")" "{\"password\": \"$password\", \"tags\": \"$tags\"}" > /dev/null

    # Set permissions
    log_step "Setting permissions..."
    api_call PUT "/permissions/$(urlencode "$vhost_lower")/$(urlencode "$user_lower")" \
        "{\"configure\": \"$configure_pattern\", \"write\": \"$write_pattern\", \"read\": \"$read_pattern\"}" > /dev/null

    # Save credentials
    local password_encoded=$(urlencode "$password")
    cat > "$cred_file" << EOF
# RabbitMQ User: $user_lower @ $vhost_lower
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
RABBITMQ_VHOST=$vhost_lower
RABBITMQ_USER=$user_lower
RABBITMQ_PASSWORD=$password
RABBITMQ_URL=amqp://${user_lower}:${password_encoded}@localhost:5672/${vhost_lower}
RABBITMQ_CONFIGURE=$configure_pattern
RABBITMQ_WRITE=$write_pattern
RABBITMQ_READ=$read_pattern
EOF
    chmod 600 "$cred_file"

    log_info "User '$user_lower' created successfully"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}Connection Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Vhost:     $vhost_lower"
    echo "  User:      $user_lower"
    echo "  Password:  $password"
    echo "  URL:       amqp://${user_lower}:****@localhost:5672/${vhost_lower}"
    echo ""
    echo "  Permissions:"
    echo "    Configure: $configure_pattern"
    echo "    Write:     $write_pattern"
    echo "    Read:      $read_pattern"
    echo ""
    echo "  Credentials saved to: $cred_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

remove_vhost() {
    local vhost_name="$1"
    local vhost_lower=$(to_lower "$vhost_name")

    load_admin_credentials
    check_api

    # Check if vhost exists
    local existing=$(api_call GET "/vhosts/$(urlencode "$vhost_lower")" 2>/dev/null || echo "")
    if [[ "$existing" != *"\"name\""* ]]; then
        log_error "Vhost '$vhost_lower' does not exist"
        exit 1
    fi

    # Don't allow removing default vhost
    if [[ "$vhost_lower" == "/" ]]; then
        log_error "Cannot remove default vhost '/'"
        exit 1
    fi

    log_warn "This will remove vhost '$vhost_lower' and ALL its queues, exchanges, and data!"
    read -p "Are you sure? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Removing vhost: $vhost_lower"

    # Get users with permissions on this vhost
    local users=$(api_call GET "/vhosts/$(urlencode "$vhost_lower")/permissions" 2>/dev/null | \
        grep -o '"user":"[^"]*"' | cut -d'"' -f4 || echo "")

    # Remove vhost (this removes all queues, exchanges, bindings)
    api_call DELETE "/vhosts/$(urlencode "$vhost_lower")" > /dev/null

    # Remove users that were specific to this vhost (contain vhost name)
    for user in $users; do
        if [[ "$user" == "${vhost_lower}-"* ]] || [[ "$user" == *"-${vhost_lower}" ]]; then
            log_step "Removing user: $user"
            api_call DELETE "/users/$(urlencode "$user")" > /dev/null 2>&1 || true
        fi
    done

    # Remove credential files
    rm -f "$CREDENTIALS_DIR/${vhost_lower}"*.env

    log_info "Vhost '$vhost_lower' removed successfully"
}

remove_user() {
    local vhost_name="$1"
    local user_name="$2"
    local vhost_lower=$(to_lower "$vhost_name")
    local user_lower=$(to_lower "$user_name")

    load_admin_credentials
    check_api

    # Check if user exists
    local existing=$(api_call GET "/users/$(urlencode "$user_lower")" 2>/dev/null || echo "")
    if [[ "$existing" != *"\"name\""* ]]; then
        log_error "User '$user_lower' does not exist"
        exit 1
    fi

    # Don't allow removing admin user
    if [[ "$user_lower" == "${vhost_lower}-admin" ]]; then
        log_error "Cannot remove admin user. Use 'remove-vhost' to remove the entire vhost."
        exit 1
    fi

    log_step "Removing user: $user_lower"

    api_call DELETE "/users/$(urlencode "$user_lower")" > /dev/null

    # Remove credential file
    rm -f "$CREDENTIALS_DIR/${vhost_lower}_${user_lower}.env"

    log_info "User '$user_lower' removed successfully"
}

# =============================================================================
# List and Show
# =============================================================================

list_vhosts() {
    ensure_dirs
    load_admin_credentials
    check_api

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RabbitMQ Vhosts and Users"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get all vhosts
    local vhosts=$(api_call GET "/vhosts" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$vhosts" ]]; then
        echo "  No vhosts found"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    for vhost in $vhosts; do
        # Skip default vhost in display (it's system)
        [[ "$vhost" == "/" ]] && continue

        echo ""
        echo -e "  ${GREEN}$vhost${NC}"

        # Get users with permissions on this vhost
        local perms=$(api_call GET "/vhosts/$(urlencode "$vhost")/permissions" 2>/dev/null || echo "[]")

        echo "$perms" | grep -o '"user":"[^"]*"[^}]*"configure":"[^"]*"[^}]*"write":"[^"]*"[^}]*"read":"[^"]*"' | \
        while read -r perm; do
            local user=$(echo "$perm" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
            local conf=$(echo "$perm" | grep -o '"configure":"[^"]*"' | cut -d'"' -f4)
            local write=$(echo "$perm" | grep -o '"write":"[^"]*"' | cut -d'"' -f4)
            local read=$(echo "$perm" | grep -o '"read":"[^"]*"' | cut -d'"' -f4)

            if [[ "$conf" == ".*" && "$write" == ".*" && "$read" == ".*" ]]; then
                echo "    ├─ $user (full access)"
            else
                echo "    ├─ $user (c:${conf:-none} w:${write:-none} r:${read:-none})"
            fi
        done
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

show_vhost() {
    local vhost_name="$1"
    local user_name="${2:-}"
    local vhost_lower=$(to_lower "$vhost_name")

    local cred_file
    if [[ -n "$user_name" ]]; then
        local user_lower=$(to_lower "$user_name")
        cred_file="$CREDENTIALS_DIR/${vhost_lower}_${user_lower}.env"
    else
        cred_file="$CREDENTIALS_DIR/${vhost_lower}.env"
    fi

    if [[ ! -f "$cred_file" ]]; then
        log_error "Credentials not found for vhost '$vhost_name'${user_name:+ user '$user_name'}"
        log_error "File: $cred_file"
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

test_connection() {
    local vhost_name="$1"
    local user_name="${2:-}"
    local vhost_lower=$(to_lower "$vhost_name")

    local cred_file
    if [[ -n "$user_name" ]]; then
        local user_lower=$(to_lower "$user_name")
        cred_file="$CREDENTIALS_DIR/${vhost_lower}_${user_lower}.env"
    else
        cred_file="$CREDENTIALS_DIR/${vhost_lower}.env"
    fi

    if [[ ! -f "$cred_file" ]]; then
        log_error "Credentials not found"
        exit 1
    fi

    source "$cred_file"

    log_step "Testing connection for $RABBITMQ_USER to vhost $RABBITMQ_VHOST..."

    # Test via management API
    local response=$(curl -sf -u "${RABBITMQ_USER}:${RABBITMQ_PASSWORD}" \
        "http://localhost:15672/api/vhosts/$(urlencode "$RABBITMQ_VHOST")" 2>/dev/null || echo "")

    if [[ "$response" == *"\"name\""* ]]; then
        log_info "Connection successful!"
        echo ""
        echo "  Vhost: $RABBITMQ_VHOST"
        echo "  User:  $RABBITMQ_USER"
        echo "  URL:   $RABBITMQ_URL"
    else
        log_error "Connection failed"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat << EOF
RabbitMQ Vhost Management Script

Usage:
  ./manage.sh <command> [arguments]

Commands:
  add-vhost <name>
      Create a new vhost with admin user and default exchanges
      Example: ./manage.sh add-vhost myapp

  add-user <vhost> <user> [options]
      Add user to existing vhost with permissions
      Options:
        --configure, -c <pattern>   Configure permission regex (default: .*)
        --write, -w <pattern>       Write permission regex (default: .*)
        --read, -r <pattern>        Read permission regex (default: .*)
        --tags, -t <tags>           User tags (e.g., "monitoring")
      Example: ./manage.sh add-user myapp worker -w "^jobs\\." -r "^results\\."

  list
      List all vhosts and users

  show <vhost> [user]
      Show connection details for vhost or specific user

  remove-user <vhost> <user>
      Remove user from system

  remove-vhost <vhost>
      Remove vhost and all its data (queues, exchanges, bindings)

  test <vhost> [user]
      Test connection to RabbitMQ

Permission Patterns (regex):
  .*              All resources
  ^myqueue$       Exact match "myqueue"
  ^jobs\\..*      Starts with "jobs." (note: escape dots)
  ^(q1|q2)$       Either "q1" or "q2"

Examples:
  # Create a vhost for your app
  ./manage.sh add-vhost orders

  # Add a worker with limited permissions
  ./manage.sh add-user orders worker \\
    --configure "^worker\\." \\
    --write "^jobs\\." \\
    --read "^results\\."

  # Add a monitoring user (read-only)
  ./manage.sh add-user orders monitor -c "" -w "" -r ".*" -t "monitoring"

  # Show connection string
  ./manage.sh show orders worker

  # List everything
  ./manage.sh list
EOF
}

main() {
    local command="${1:-}"

    case "$command" in
        add-vhost)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            add_vhost "$2" "${3:-}"
            ;;
        add-user)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            [[ -z "${3:-}" ]] && { log_error "User name required"; usage; exit 1; }
            add_user "${@:2}"
            ;;
        remove-vhost)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            remove_vhost "$2"
            ;;
        remove-user)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            [[ -z "${3:-}" ]] && { log_error "User name required"; usage; exit 1; }
            remove_user "$2" "$3"
            ;;
        list)
            list_vhosts
            ;;
        show)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            show_vhost "$2" "${3:-}"
            ;;
        test)
            [[ -z "${2:-}" ]] && { log_error "Vhost name required"; usage; exit 1; }
            test_connection "$2" "${3:-}"
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
