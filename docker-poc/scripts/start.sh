#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test -f .env || cp .env.example .env
docker compose up -d --build
docker compose ps
