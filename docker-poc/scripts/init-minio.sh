#!/bin/sh
set -eu
mc alias set lab http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "lab/$MINIO_BUCKET"
mc anonymous set download "lab/$MINIO_BUCKET"
mc cp --recursive /samples/ "lab/$MINIO_BUCKET/samples/"
