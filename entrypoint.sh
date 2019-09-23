#!/bin/bash
set -Eeo pipefail

### Get nginx version
# https://stackoverflow.com/questions/50729099/bash-nginx-version-check-cut
###
command="nginx -v"
nginxv=$( ${command} 2>&1 )
nginxlocal=$(echo $nginxv | grep -o '[0-9.]*$')
### Get nginx version

echo "Starting container version $IMAGE_VERSION with nginx version ${nginxlocal}..."
echo "Run $@"

exec "$@"
