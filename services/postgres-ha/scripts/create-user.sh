#!/bin/bash
# =============================================================================
# Create/Update PostgreSQL User, Database & Schema (Primary-Replica)
# =============================================================================
# Usage:
#   ./scripts/create-user.sh <username> <password> [database] [schema]
#
# Examples:
#   ./scripts/create-user.sh app_user secret123
#   ./scripts/create-user.sh app_user secret123 myapp
#   ./scripts/create-user.sh app_user secret123 myapp app_schema
#
# Note: All changes are made on master and replicate automatically to replica.
# This script wraps the unified database CLI.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$INFRA_ROOT/lib/db-cli.sh" postgres-replica create-user "$@"
