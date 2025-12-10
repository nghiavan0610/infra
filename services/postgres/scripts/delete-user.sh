#!/bin/bash
# =============================================================================
# Delete PostgreSQL User
# =============================================================================
# Usage:
#   ./scripts/delete-user.sh <username> [--drop-schema]
#
# Examples:
#   ./scripts/delete-user.sh app_user
#   ./scripts/delete-user.sh app_user --drop-schema
#
# This script wraps the unified database CLI.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$INFRA_ROOT/lib/db-cli.sh" postgres-single delete-user "$@"
