#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
echo "This removes this project's containers, volumes, and locally built images."
docker compose down --volumes --remove-orphans --rmi all
