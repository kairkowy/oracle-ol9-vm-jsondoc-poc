#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi
docker compose pull
docker compose build app
docker compose up -d postgres minio polaris-bootstrap minio-init polaris polaris-setup trino
echo "Base services initialized. Run scripts/start.sh to start the upload app."
