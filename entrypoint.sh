#!/bin/bash
set -Eeo pipefail

SITESENABLED_DIR="/etc/nginx/sites-enabled/"

### Get nginx version
# https://stackoverflow.com/questions/50729099/bash-nginx-version-check-cut
###
command="nginx -v"
nginxv=$( ${command} 2>&1 )
nginxlocal=$(echo $nginxv | grep -o '[0-9.]*$')
### Get nginx version

echo "Check if ${SITESENABLED_DIR} is empty"

if [ -z "$(ls -A $SITESENABLED_DIR)" ]; then
    echo "Copy default config to ${SITESENABLED_DIR}"
else
    echo "Keep config in ${SITESENABLED_DIR}"
fi

echo "Starting container version $IMAGE_VERSION with nginx version ${nginxlocal}..."
echo "Run $@"

exec "$@"
