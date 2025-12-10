#!/bin/bash
# =============================================================================
# Initialize MongoDB Replica Set
# =============================================================================
# This script initializes the replica set and creates application/exporter users.
# It's idempotent - safe to run multiple times.
#
# Usage:
#   ./scripts/init-replica.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONGO_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [[ -f "$MONGO_DIR/.env" ]]; then
    set -a
    source "$MONGO_DIR/.env"
    set +a
else
    echo "Error: .env file not found. Copy .env.example to .env first."
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
REPLICA_SET_NAME="${MONGO_REPLICA_SET_NAME:-rs0}"
PRIMARY_HOST="${MONGO_PRIMARY_HOST:-mongo-primary}"
SECONDARY_HOST="${MONGO_SECONDARY_HOST:-mongo-secondary}"
ARBITER_HOST="${MONGO_ARBITER_HOST:-mongo-arbiter}"
PRIMARY_PORT="${MONGO_PRIMARY_PORT:-27017}"
SECONDARY_PORT="${MONGO_SECONDARY_PORT:-27018}"
ARBITER_PORT="${MONGO_ARBITER_PORT:-27019}"

echo "=============================================="
echo "MongoDB Replica Set Initialization"
echo "=============================================="
echo ""

# Wait for primary to be ready
echo -e "${YELLOW}Waiting for MongoDB primary to be ready...${NC}"
until docker exec mongo-primary mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q "1"; do
    echo "  Waiting for mongod to start..."
    sleep 2
done
echo -e "${GREEN}MongoDB primary is ready${NC}"
echo ""

# Check if replica set is already initialized
echo "Checking replica set status..."
RS_STATUS=$(docker exec mongo-primary mongosh --quiet \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "try { rs.status().ok } catch(e) { 0 }" 2>/dev/null || echo "0")

if [[ "$RS_STATUS" == "1" ]]; then
    echo -e "${GREEN}Replica set is already initialized${NC}"
else
    echo -e "${YELLOW}Initializing replica set...${NC}"

    # Initialize replica set
    docker exec mongo-primary mongosh --quiet \
        -u "$MONGO_INITDB_ROOT_USERNAME" \
        -p "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval "
        rs.initiate({
            _id: '$REPLICA_SET_NAME',
            members: [
                { _id: 0, host: '$PRIMARY_HOST:27017', priority: 2 },
                { _id: 1, host: '$SECONDARY_HOST:27017', priority: 1 },
                { _id: 2, host: '$ARBITER_HOST:27017', arbiterOnly: true }
            ]
        })
        "

    echo "Waiting for replica set to stabilize..."
    sleep 10

    # Wait for primary election
    until docker exec mongo-primary mongosh --quiet \
        -u "$MONGO_INITDB_ROOT_USERNAME" \
        -p "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; do
        echo "  Waiting for primary election..."
        sleep 2
    done

    echo -e "${GREEN}Replica set initialized successfully${NC}"
fi
echo ""

# Create application user if specified
if [[ -n "$MONGO_APP_USERNAME" && -n "$MONGO_APP_PASSWORD" && -n "$MONGO_APP_DATABASE" ]]; then
    echo "Creating application user..."

    docker exec mongo-primary mongosh --quiet \
        -u "$MONGO_INITDB_ROOT_USERNAME" \
        -p "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval "
        // Switch to app database
        db = db.getSiblingDB('$MONGO_APP_DATABASE');

        // Check if user exists
        const existingUser = db.getUser('$MONGO_APP_USERNAME');
        if (existingUser) {
            print('Application user already exists');
        } else {
            db.createUser({
                user: '$MONGO_APP_USERNAME',
                pwd: '$MONGO_APP_PASSWORD',
                roles: [
                    { role: 'readWrite', db: '$MONGO_APP_DATABASE' }
                ]
            });
            print('Application user created');
        }
        " 2>/dev/null && echo -e "${GREEN}Application user ready${NC}" || echo -e "${YELLOW}Application user setup skipped${NC}"
fi
echo ""

# Create exporter user for monitoring
if [[ -n "$MONGO_EXPORTER_USERNAME" && -n "$MONGO_EXPORTER_PASSWORD" ]]; then
    echo "Creating exporter user for monitoring..."

    docker exec mongo-primary mongosh --quiet \
        -u "$MONGO_INITDB_ROOT_USERNAME" \
        -p "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval "
        db = db.getSiblingDB('admin');

        // Check if user exists
        const existingUser = db.getUser('$MONGO_EXPORTER_USERNAME');
        if (existingUser) {
            print('Exporter user already exists');
        } else {
            db.createUser({
                user: '$MONGO_EXPORTER_USERNAME',
                pwd: '$MONGO_EXPORTER_PASSWORD',
                roles: [
                    { role: 'clusterMonitor', db: 'admin' },
                    { role: 'read', db: 'local' }
                ]
            });
            print('Exporter user created');
        }
        " 2>/dev/null && echo -e "${GREEN}Exporter user ready${NC}" || echo -e "${YELLOW}Exporter user setup skipped${NC}"
fi
echo ""

# Show replica set status
echo "=============================================="
echo "Replica Set Status"
echo "=============================================="
docker exec mongo-primary mongosh --quiet \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "
    const status = rs.status();
    print('Replica Set: ' + status.set);
    print('');
    status.members.forEach(m => {
        const state = m.stateStr;
        const health = m.health === 1 ? 'healthy' : 'unhealthy';
        print('  ' + m.name + ' - ' + state + ' (' + health + ')');
    });
    "
echo ""
echo -e "${GREEN}MongoDB replica set is ready!${NC}"
echo ""
echo "Connection strings:"
echo "  Internal: mongodb://$MONGO_APP_USERNAME:****@mongo-primary:27017,$SECONDARY_HOST:27017/$MONGO_APP_DATABASE?replicaSet=$REPLICA_SET_NAME"
echo "  External: mongodb://$MONGO_APP_USERNAME:****@\$HOST:$PRIMARY_PORT,\$HOST:$SECONDARY_PORT/$MONGO_APP_DATABASE?replicaSet=$REPLICA_SET_NAME"
