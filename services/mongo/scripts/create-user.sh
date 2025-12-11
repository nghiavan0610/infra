#!/bin/bash
# =============================================================================
# Create MongoDB User
# =============================================================================
# Creates a new database user with specified roles.
#
# Usage:
#   ./scripts/create-user.sh <username> <password> <database> [role]
#
# Roles:
#   read       - Read-only access
#   readWrite  - Read and write access (default)
#   dbAdmin    - Database administration
#   dbOwner    - Full database ownership
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONGO_DIR="$(dirname "$SCRIPT_DIR")"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Load environment variables
if [[ -f "$MONGO_DIR/.env" ]]; then
    set -a
    source "$MONGO_DIR/.env"
    set +a
else
    echo "Error: .env file not found"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Arguments
USERNAME="$1"
PASSWORD="$2"
DATABASE="$3"
ROLE="${4:-readWrite}"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$DATABASE" ]]; then
    echo "Usage: $0 <username> <password> <database> [role]"
    echo ""
    echo "Roles: read, readWrite (default), dbAdmin, dbOwner"
    echo ""
    echo "Examples:"
    echo "  $0 myapp secretpass mydb              # readWrite access"
    echo "  $0 readonly secretpass mydb read      # read-only access"
    echo "  $0 admin secretpass mydb dbOwner      # full ownership"
    exit 1
fi

echo "Creating user '$USERNAME' on database '$DATABASE' with role '$ROLE'..."

docker exec mongo-primary mongosh --quiet \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "
    db = db.getSiblingDB('$DATABASE');

    // Check if user exists
    const existingUser = db.getUser('$USERNAME');
    if (existingUser) {
        print('User already exists. Updating password and roles...');
        db.updateUser('$USERNAME', {
            pwd: '$PASSWORD',
            roles: [{ role: '$ROLE', db: '$DATABASE' }]
        });
        print('User updated');
    } else {
        db.createUser({
            user: '$USERNAME',
            pwd: '$PASSWORD',
            roles: [{ role: '$ROLE', db: '$DATABASE' }]
        });
        print('User created');
    }
    "

echo -e "${GREEN}User '$USERNAME' is ready${NC}"
echo ""
echo "Connection string:"
echo "  mongodb://$USERNAME:****@mongo-primary:27017/$DATABASE?replicaSet=${MONGO_REPLICA_SET_NAME:-rs0}"
