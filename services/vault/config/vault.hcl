# =============================================================================
# Vault Server Configuration
# =============================================================================

# UI
ui = true

# Listener
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true  # Enable TLS in production with Traefik
}

# Storage backend (file-based for simplicity)
storage "file" {
  path = "/vault/data"
}

# Disable mlock (required for Docker)
disable_mlock = true

# API address
api_addr = "http://127.0.0.1:8200"

# Logging
log_level = "info"

# Telemetry (Prometheus metrics at /v1/sys/metrics)
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = true
}
