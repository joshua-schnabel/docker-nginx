#!/bin/bash
set -Eeo pipefail

echo "Starting Image Version $IMAGE_VERSION..."
echo "Run $@"

exec "$@"
