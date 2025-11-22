#!/bin/sh

RPC_SECRET="./config/rpc-garage-secret.key"
ADMIN_TOKEN="./config/admin-garage-token.key"

# Create config directory if it doesn't exist
mkdir -p ./config

# Check if the key file exists and is valid
if [ ! -f "$RPC_SECRET" ]; then
  echo "Generating new Garage RPC secret key..."
  openssl rand -hex 32 | tr -d '\n' > "$RPC_SECRET"
  chmod 644 "$RPC_SECRET"
  echo "RPC Key generated at $RPC_SECRET"
else
  echo "Garage RPC secret key already exists and is valid."
fi

if [ ! -f "$ADMIN_TOKEN" ]; then
  echo "Generating new Garage Admin token key..."
  openssl rand -base64 32 | tr -d '\n' > "$ADMIN_TOKEN"
  chmod 644 "$ADMIN_TOKEN"
  echo "Admin token generated at $ADMIN_TOKEN"
else
  echo "Garage Admin token key already exists and is valid."
fi