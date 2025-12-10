#!/bin/bash
# =============================================================================
# Backup Container Entrypoint
# =============================================================================
# Sets up cron schedule and runs backup daemon
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Backup Service Starting${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify required environment variables
if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    echo -e "${YELLOW}[WARN]${NC} RESTIC_PASSWORD not set - backups will fail"
fi

if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    echo -e "${YELLOW}[WARN]${NC} RESTIC_REPOSITORY not set - using default"
    export RESTIC_REPOSITORY="s3:http://garage:3900/backups"
fi

# Initialize restic repository if needed
echo -e "${GREEN}[INFO]${NC} Checking Restic repository..."
if ! restic snapshots &>/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Initializing Restic repository..."
    restic init 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Could not initialize repository (may already exist or S3 not ready)"
fi

# Show configuration
echo ""
echo "Configuration:"
echo "  Repository:  ${RESTIC_REPOSITORY}"
echo "  Schedule:    ${BACKUP_SCHEDULE:-0 2 * * *}"
echo "  Timezone:    ${TZ:-UTC}"
echo ""

# List enabled backup targets
echo "Backup Targets:"
for config_file in /app/config/*.json; do
    if [[ -f "$config_file" ]]; then
        service=$(basename "$config_file" .json)
        count=$(jq '[.targets[]? | select(.enabled == true)] | length' "$config_file" 2>/dev/null || echo 0)
        if [[ "$count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} $service ($count targets)"
        fi
    fi
done
echo ""

# Setup cron schedule
SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
echo "$SCHEDULE /app/scripts/backup.sh >> /app/logs/backup.log 2>&1" > /etc/crontabs/root

# Run initial backup if requested
if [[ "${RUN_ON_START:-false}" == "true" ]]; then
    echo -e "${GREEN}[INFO]${NC} Running initial backup..."
    /app/scripts/backup.sh
fi

echo -e "${GREEN}[INFO]${NC} Backup scheduler started"
echo -e "${GREEN}[INFO]${NC} Next backup: $(echo "$SCHEDULE" | awk '{print "minute="$1" hour="$2" day="$3" month="$4" weekday="$5}')"
echo ""

# Keep container running with cron
exec crond -f -l 2
