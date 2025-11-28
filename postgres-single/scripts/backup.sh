#!/bin/bash
# =============================================================================
# PostgreSQL Backup Script
# Creates compressed backups with automatic rotation
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
CONTAINER_NAME="postgres"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Load environment variables
if [ -f "${PROJECT_DIR}/.env" ]; then
    export $(grep -v '^#' "${PROJECT_DIR}/.env" | xargs)
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if Docker is running
    if ! docker info &>/dev/null; then
        log_error "Docker is not running"
        exit 1
    fi

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container '${CONTAINER_NAME}' is not running"
        exit 1
    fi

    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi

    log_info "Pre-flight checks passed"
}

# -----------------------------------------------------------------------------
# Backup Functions
# -----------------------------------------------------------------------------
backup_database() {
    local DB_NAME=$1
    local BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

    log_info "Backing up database: ${DB_NAME}"

    # Create backup using pg_dump with compression
    docker exec -t ${CONTAINER_NAME} pg_dump \
        -U "${POSTGRES_USER}" \
        -d "${DB_NAME}" \
        --no-owner \
        --no-privileges \
        --clean \
        --if-exists \
        --verbose \
        2>&1 | gzip > "${BACKUP_FILE}"

    if [ $? -eq 0 ] && [ -s "${BACKUP_FILE}" ]; then
        local SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        log_info "Backup created: ${BACKUP_FILE} (${SIZE})"
        return 0
    else
        log_error "Backup failed for database: ${DB_NAME}"
        rm -f "${BACKUP_FILE}"
        return 1
    fi
}

backup_all_databases() {
    local BACKUP_FILE="${BACKUP_DIR}/all_databases_${TIMESTAMP}.sql.gz"

    log_info "Backing up ALL databases..."

    # Create backup of all databases using pg_dumpall
    docker exec -t ${CONTAINER_NAME} pg_dumpall \
        -U "${POSTGRES_USER}" \
        --clean \
        --if-exists \
        2>&1 | gzip > "${BACKUP_FILE}"

    if [ $? -eq 0 ] && [ -s "${BACKUP_FILE}" ]; then
        local SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        log_info "Full backup created: ${BACKUP_FILE} (${SIZE})"
        return 0
    else
        log_error "Full backup failed"
        rm -f "${BACKUP_FILE}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Cleanup Old Backups
# -----------------------------------------------------------------------------
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."

    local COUNT=$(find "${BACKUP_DIR}" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)

    if [ "$COUNT" -gt 0 ]; then
        find "${BACKUP_DIR}" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete
        log_info "Deleted ${COUNT} old backup(s)"
    else
        log_info "No old backups to delete"
    fi
}

# -----------------------------------------------------------------------------
# Verify Backup
# -----------------------------------------------------------------------------
verify_backup() {
    local BACKUP_FILE=$1

    log_info "Verifying backup: ${BACKUP_FILE}"

    # Check if file exists and has content
    if [ ! -f "${BACKUP_FILE}" ]; then
        log_error "Backup file not found: ${BACKUP_FILE}"
        return 1
    fi

    # Check if gzip file is valid
    if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
        log_error "Backup file is corrupted: ${BACKUP_FILE}"
        return 1
    fi

    # Check minimum file size (at least 1KB)
    local SIZE=$(stat -f%z "${BACKUP_FILE}" 2>/dev/null || stat -c%s "${BACKUP_FILE}")
    if [ "$SIZE" -lt 1024 ]; then
        log_warn "Backup file is suspiciously small: ${SIZE} bytes"
    fi

    log_info "Backup verification passed"
    return 0
}

# -----------------------------------------------------------------------------
# List Backups
# -----------------------------------------------------------------------------
list_backups() {
    log_info "Available backups:"
    echo ""
    ls -lh "${BACKUP_DIR}"/*.sql.gz 2>/dev/null || echo "No backups found"
    echo ""
    log_info "Total backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
}

# -----------------------------------------------------------------------------
# Restore Backup
# -----------------------------------------------------------------------------
restore_backup() {
    local BACKUP_FILE=$1

    if [ ! -f "${BACKUP_FILE}" ]; then
        log_error "Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi

    log_warn "This will OVERWRITE existing data!"
    read -p "Are you sure you want to restore? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi

    log_info "Restoring from: ${BACKUP_FILE}"

    # Restore database
    gunzip -c "${BACKUP_FILE}" | docker exec -i ${CONTAINER_NAME} psql \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}"

    if [ $? -eq 0 ]; then
        log_info "Restore completed successfully"
    else
        log_error "Restore failed"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    echo "PostgreSQL Backup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  backup          Backup main database (default)"
    echo "  backup-all      Backup all databases"
    echo "  list            List available backups"
    echo "  restore <file>  Restore from backup file"
    echo "  cleanup         Remove old backups"
    echo "  verify <file>   Verify backup file integrity"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore ./backups/mydb_20250101_120000.sql.gz"
    echo ""
    echo "Environment variables:"
    echo "  BACKUP_RETENTION_DAYS  Days to keep backups (default: 7)"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local COMMAND=${1:-backup}

    case "$COMMAND" in
        backup)
            preflight_checks
            backup_database "${POSTGRES_DB}"
            cleanup_old_backups
            ;;
        backup-all)
            preflight_checks
            backup_all_databases
            cleanup_old_backups
            ;;
        list)
            list_backups
            ;;
        restore)
            if [ -z "${2:-}" ]; then
                log_error "Please specify a backup file to restore"
                usage
                exit 1
            fi
            preflight_checks
            restore_backup "$2"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        verify)
            if [ -z "${2:-}" ]; then
                log_error "Please specify a backup file to verify"
                exit 1
            fi
            verify_backup "$2"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            exit 1
            ;;
    esac
}

main "$@"
