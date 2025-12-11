#!/bin/bash
# =============================================================================
# Garage Management Script
# =============================================================================
# Manage buckets, keys, and common operations
#
# Usage:
#   ./manage.sh status                          # Show cluster status
#   ./manage.sh bucket list                     # List all buckets
#   ./manage.sh bucket create <name>            # Create bucket
#   ./manage.sh bucket delete <name>            # Delete bucket
#   ./manage.sh bucket info <name>              # Show bucket info
#   ./manage.sh bucket website <name>           # Enable website hosting
#   ./manage.sh key list                        # List all keys
#   ./manage.sh key create <name>               # Create access key
#   ./manage.sh key delete <id>                 # Delete access key
#   ./manage.sh key info <id>                   # Show key info
#   ./manage.sh allow <bucket> <key>            # Grant full access
#   ./manage.sh deny <bucket> <key>             # Revoke access
# =============================================================================

set -e

# Require authentication
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

GARAGE="docker exec garage /garage"

# Check if garage is running
check_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^garage$"; then
        log_error "Garage container is not running"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Status
# -----------------------------------------------------------------------------
cmd_status() {
    check_running
    $GARAGE status
}

# -----------------------------------------------------------------------------
# Bucket commands
# -----------------------------------------------------------------------------
cmd_bucket_list() {
    check_running
    $GARAGE bucket list
}

cmd_bucket_create() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 bucket create <name>"
        exit 1
    fi

    check_running
    $GARAGE bucket create "$name"
    log_info "Bucket '$name' created"
}

cmd_bucket_delete() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 bucket delete <name>"
        exit 1
    fi

    check_running

    echo -e "${YELLOW}WARNING: This will permanently delete bucket '$name' and all its contents${NC}"
    read -p "Are you sure? (yes/no): " confirm

    if [[ "$confirm" == "yes" ]]; then
        $GARAGE bucket delete "$name" --yes
        log_info "Bucket '$name' deleted"
    else
        log_info "Cancelled"
    fi
}

cmd_bucket_info() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 bucket info <name>"
        exit 1
    fi

    check_running
    $GARAGE bucket info "$name"
}

cmd_bucket_website() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 bucket website <name>"
        exit 1
    fi

    check_running
    $GARAGE bucket website --allow "$name"
    log_info "Website hosting enabled for '$name'"
}

# -----------------------------------------------------------------------------
# Key commands
# -----------------------------------------------------------------------------
cmd_key_list() {
    check_running
    $GARAGE key list
}

cmd_key_create() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 key create <name>"
        exit 1
    fi

    check_running
    $GARAGE key create "$name"
    log_info "Key '$name' created"
    log_warn "Save the Access Key ID and Secret Key shown above!"
}

cmd_key_delete() {
    local id="$1"
    if [[ -z "$id" ]]; then
        log_error "Usage: $0 key delete <key-id>"
        exit 1
    fi

    check_running
    $GARAGE key delete "$id" --yes
    log_info "Key deleted"
}

cmd_key_info() {
    local id="$1"
    if [[ -z "$id" ]]; then
        log_error "Usage: $0 key info <key-id>"
        exit 1
    fi

    check_running
    $GARAGE key info "$id"
}

# -----------------------------------------------------------------------------
# Permission commands
# -----------------------------------------------------------------------------
cmd_allow() {
    local bucket="$1"
    local key="$2"

    if [[ -z "$bucket" || -z "$key" ]]; then
        log_error "Usage: $0 allow <bucket> <key-name-or-id>"
        exit 1
    fi

    check_running
    $GARAGE bucket allow --read --write --owner "$bucket" --key "$key"
    log_info "Granted full access to '$bucket' for key '$key'"
}

cmd_deny() {
    local bucket="$1"
    local key="$2"

    if [[ -z "$bucket" || -z "$key" ]]; then
        log_error "Usage: $0 deny <bucket> <key-name-or-id>"
        exit 1
    fi

    check_running
    $GARAGE bucket deny --read --write --owner "$bucket" --key "$key"
    log_info "Revoked access to '$bucket' for key '$key'"
}

# -----------------------------------------------------------------------------
# Quick setup: Create bucket with key
# -----------------------------------------------------------------------------
cmd_quick_setup() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 quick-setup <name>"
        echo "Creates a bucket and access key with the same name"
        exit 1
    fi

    check_running

    log_info "Creating bucket '$name'..."
    $GARAGE bucket create "$name"

    log_info "Creating access key '${name}-key'..."
    $GARAGE key create "${name}-key"

    log_info "Granting access..."
    $GARAGE bucket allow --read --write --owner "$name" --key "${name}-key"

    echo ""
    log_info "Setup complete!"
    echo ""
    echo "Bucket: $name"
    echo "Key:    ${name}-key"
    echo ""
    log_warn "Save the Access Key ID and Secret Key shown above!"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
show_help() {
    echo ""
    echo "Garage Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status                    Show cluster status"
    echo ""
    echo "  bucket list               List all buckets"
    echo "  bucket create <name>      Create a bucket"
    echo "  bucket delete <name>      Delete a bucket"
    echo "  bucket info <name>        Show bucket info"
    echo "  bucket website <name>     Enable website hosting"
    echo ""
    echo "  key list                  List all access keys"
    echo "  key create <name>         Create an access key"
    echo "  key delete <id>           Delete an access key"
    echo "  key info <id>             Show key info"
    echo ""
    echo "  allow <bucket> <key>      Grant full access"
    echo "  deny <bucket> <key>       Revoke access"
    echo ""
    echo "  quick-setup <name>        Create bucket + key in one command"
    echo ""
    echo "Examples:"
    echo "  $0 quick-setup myapp"
    echo "  $0 bucket create backups"
    echo "  $0 key create backup-key"
    echo "  $0 allow backups backup-key"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        status)
            cmd_status
            ;;
        bucket)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) cmd_bucket_list ;;
                create) cmd_bucket_create "$@" ;;
                delete) cmd_bucket_delete "$@" ;;
                info) cmd_bucket_info "$@" ;;
                website) cmd_bucket_website "$@" ;;
                *) log_error "Unknown bucket command: $sub" ;;
            esac
            ;;
        key)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) cmd_key_list ;;
                create) cmd_key_create "$@" ;;
                delete) cmd_key_delete "$@" ;;
                info) cmd_key_info "$@" ;;
                *) log_error "Unknown key command: $sub" ;;
            esac
            ;;
        allow)
            cmd_allow "$@"
            ;;
        deny)
            cmd_deny "$@"
            ;;
        quick-setup)
            cmd_quick_setup "$@"
            ;;
        help|--help|-h)
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
