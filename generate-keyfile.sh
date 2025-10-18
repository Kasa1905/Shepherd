#!/bin/bash
# Generate MongoDB keyFile for replica set authentication

# Generate a random 1024-character keyFile
openssl rand -base64 756 > mongodb-keyfile/mongo-keyfile

# Set appropriate permissions (MongoDB requires 400 or 600)
chmod 600 mongodb-keyfile/mongo-keyfile

echo "MongoDB keyFile generated successfully at mongodb-keyfile/mongo-keyfile"