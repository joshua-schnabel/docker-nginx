#!/bin/bash
set -Eeo pipefail

L_SITESENABLED_DIR="/media/data/sites-enabled/"
L_DISABLETLS="${DISABLETLS:-true}"
L_DHFILE="/media/data/dhparams/dhparam4096.dh"
L_CERTFILE="/media/data/certs/default_cert.pem"
L_KEYFILE="/media/data/certs/default_key.pem"

### Get nginx version
# https://stackoverflow.com/questions/50729099/bash-nginx-version-check-cut
###
command="nginx -v"
nginxv=$( ${command} 2>&1 )
nginxlocal=$(echo $nginxv | grep -o '[0-9.]*$')
### Get nginx version

echo "Check if $L_SITESENABLED_DIR is empty"

if [ -z "$(ls -A $L_SITESENABLED_DIR)" ]; then
    echo "Copy default config to $L_SITESENABLED_DIR"
	cp -a /media/defaults/sites-enabled/. "$L_SITESENABLED_DIR"
	if [ "$DISABLETLS" = "false" ]; then
		echo "Copy default tls config to $L_SITESENABLED_DIR"
		cp -a /media/defaults/sites-enabled-ssl/. "$L_SITESENABLED_DIR"
	fi
else
    echo "Keep config in $L_SITESENABLED_DIR"
fi

if [ ! -f "$L_DHFILE" ] && [ "$DISABLETLS" = "false" ]; then
    echo "$L_DHFILE doesn't exist, create it, but it takes some time..."
	openssl dhparam -dsaparam -out "$L_DHFILE" 4096
fi

if [ ! -f "$L_CERTFILE" ] && [ "$DISABLETLS" = "false" ]; then
    echo "$L_CERTFILE doesn't exist, create it, but it takes some time..."
	openssl req -x509 -newkey rsa:4096 -out "$L_CERTFILE" -keyout "$L_KEYFILE" -days 365 -nodes -subj '/CN=localhost'
fi

echo "Starting container version $IMAGE_VERSION with nginx version ${nginxlocal}..."
echo "Run $@"

exec "$@" 2>&1
