#!/bin/bash
# =============================================================================
# List PostgreSQL Users
# =============================================================================
# Usage:
#   ./scripts/list-users.sh
#
# This script wraps the unified database CLI.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$INFRA_ROOT/lib/db-cli.sh" postgres-single list-users "$@"
