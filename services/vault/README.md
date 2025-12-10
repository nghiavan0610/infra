# HashiCorp Vault - Secrets Management

Secure storage for secrets, API keys, passwords, and certificates.

## Features

- Centralized secrets management
- Dynamic secrets (generate on-demand)
- Encryption as a service
- Access control policies
- Audit logging
- Secret rotation

## Quick Start

```bash
# 1. Start Vault
cp .env.example .env
docker compose up -d

# 2. Initialize (first time only)
./scripts/init.sh

# 3. Save the unseal keys and root token!
```

## Access

- **UI**: http://localhost:8200
- **API**: http://localhost:8200/v1/

## Important Concepts

### Sealed vs Unsealed

Vault starts **sealed**. You must unseal it with 3 of 5 keys before use.

```bash
# After restart
./scripts/unseal.sh
```

### Root Token

The root token has full access. Use it only for initial setup, then create limited tokens.

## Basic Usage

### Store a Secret

```bash
# Login
export VAULT_ADDR=http://127.0.0.1:8200
vault login <root-token>

# Store secret
vault kv put secret/myapp/database \
  username=myapp \
  password=supersecret \
  host=localhost

# Read secret
vault kv get secret/myapp/database

# Get specific field
vault kv get -field=password secret/myapp/database
```

### From Your App

```bash
# Using curl
curl -H "X-Vault-Token: <token>" \
  http://localhost:8200/v1/secret/data/myapp/database
```

### NestJS Integration

```typescript
// Using node-vault
import Vault from 'node-vault';

const vault = Vault({
  apiVersion: 'v1',
  endpoint: 'http://localhost:8200',
  token: process.env.VAULT_TOKEN,
});

// Read secret
const { data } = await vault.read('secret/data/myapp/database');
const password = data.data.password;
```

## Create App Token

Instead of using root token in apps:

```bash
# Create policy for app
vault policy write myapp - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF

# Create token with policy
vault token create -policy=myapp -ttl=720h
```

## Organize Secrets

Recommended structure:

```
secret/
├── infra/
│   ├── postgres/
│   │   └── credentials
│   ├── redis/
│   │   └── password
│   └── garage/
│       └── keys
├── apps/
│   ├── myapp/
│   │   ├── database
│   │   ├── api-keys
│   │   └── jwt-secret
│   └── another-app/
│       └── ...
└── shared/
    └── smtp-credentials
```

## Commands

```bash
# Login
vault login

# List secrets
vault kv list secret/

# Put secret
vault kv put secret/path key=value

# Get secret
vault kv get secret/path

# Delete secret
vault kv delete secret/path

# Check status
vault status

# Seal vault (emergency)
vault operator seal
```

## Backup

```bash
# Backup data directory
cp -r data/ backup/vault-data-$(date +%Y%m%d)/

# Also backup keys.json (store separately!)
```

## Auto-Unseal (Production)

For production, consider auto-unseal with:
- AWS KMS
- GCP Cloud KMS
- Azure Key Vault

This avoids manual unsealing after restarts.

## vs .env Files

| Aspect | .env Files | Vault |
|--------|------------|-------|
| Security | Plain text | Encrypted |
| Access control | File permissions | Policies |
| Audit | None | Full audit log |
| Rotation | Manual | Automated |
| Complexity | Simple | More setup |

**Recommendation:** Start with .env files, migrate to Vault when you need more security or have multiple apps.

## Ports

| Port | Service |
|------|---------|
| 8200 | API + UI |
