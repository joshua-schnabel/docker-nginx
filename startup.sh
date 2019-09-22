#!/bin/bash
set -e

NGINXVERSION="$(nginx -v)"
echo "Starting Image Version $IMAGE_VERSION with ${NGINXVERSION} ..."

exec "$@"
