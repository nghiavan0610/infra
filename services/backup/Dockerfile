# =============================================================================
# Production Backup Container
# =============================================================================
# Includes all database clients and backup tools
# =============================================================================

FROM alpine:3.19

# Install all required tools
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    openssl \
    # Restic backup tool
    restic \
    # PostgreSQL client
    postgresql16-client \
    # MySQL client
    mysql-client \
    # Redis client
    redis \
    # MongoDB tools
    mongodb-tools \
    # For Docker socket access (volume backups)
    docker-cli \
    # Timezone support
    tzdata

# Create directories
RUN mkdir -p /app/scripts /app/config /app/logs /tmp/backups

WORKDIR /app

# Copy scripts
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Healthcheck - verify restic is working
HEALTHCHECK --interval=60s --timeout=10s --start-period=5s --retries=3 \
    CMD restic version > /dev/null 2>&1 || exit 1

# Default command - run cron daemon
CMD ["/app/scripts/entrypoint.sh"]
