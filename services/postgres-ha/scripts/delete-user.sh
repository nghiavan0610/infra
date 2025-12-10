#!/bin/bash
# =============================================================================
# Delete PostgreSQL User (Primary-Replica)
# =============================================================================
# Usage:
#   ./scripts/delete-user.sh <username> [--drop-schema]
#
# Examples:
#   ./scripts/delete-user.sh app_user
#   ./scripts/delete-user.sh app_user --drop-schema
#
# Note: Changes replicate automatically to replica.
# This script wraps the unified database CLI.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$INFRA_ROOT/lib/db-cli.sh" postgres-replica delete-user "$@"
