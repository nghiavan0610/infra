#!/bin/bash

echo ====================================================
echo ============= Initializing Replica Set =============
echo ====================================================

# Loop until MongoDB is ready to accept connections
until mongosh --host $MONGO_PRIMARY_IP --tls --tlsCAFile /etc/mongo/certs/ca.pem --tlsCertificateKeyFile /etc/mongo/certs/mongodb.pem --tlsAllowInvalidCertificates --eval 'quit(0)' &>/dev/null; do
    echo "Waiting for mongod to start..."
    sleep 5
done

echo "MongoDB started. Initiating Replica Set..."

# Connect to the MongoDB service and initiate the replica set
mongosh --host $MONGO_PRIMARY_IP -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --tls --tlsCAFile /etc/mongo/certs/ca.pem --tlsCertificateKeyFile /etc/mongo/certs/mongodb.pem --tlsAllowInvalidCertificates <<EOF
rs.initiate({
      _id: "rs0",
      members: [
        { _id: 0, host: "$MONGO_PRIMARY_IP:$MONGO_PRIMARY_PORT", priority: 2 },
        { _id: 1, host: "$MONGO_SECONDARY_IP:$MONGO_SECONDARY_PORT", priority: 1 },
        { _id: 2, host: "$MONGO_ARBITER_IP:$MONGO_ARBITER_PORT", arbiterOnly: true },
      ]
})
EOF

echo ====================================================
echo ============= Replica Set initialized ==============
echo ====================================================