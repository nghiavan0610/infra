#!/bin/bash
# =============================================================================
# Create TimescaleDB User & Schema
# =============================================================================
# Usage:
#   ./scripts/create-user.sh <username> <password> [database] [schema]
#
# Examples:
#   ./scripts/create-user.sh metrics_user secret123
#   ./scripts/create-user.sh metrics_user secret123 timeseries metrics
#
# Note: TimescaleDB extension is automatically enabled on the database.
# This script wraps the unified database CLI.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$INFRA_ROOT/lib/db-cli.sh" timescaledb create-user "$@"
