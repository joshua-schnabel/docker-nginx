#!/bin/bash
set -Eeo pipefail

L_SITESENABLED_DIR="/media/data/sites-enabled/"
L_SITESENABLED_DEFAULT="/media/data/sites-enabled/default.conf"
L_DISABLETLS="${DISABLETLS:-true}"
L_DHFILE="/media/data/dhparams/dhparam4096.dh"
L_CERTFILE="/media/data/certs/default_cert.pem"
L_KEYFILE="/media/data/certs/default_key.pem"

### Get nginx version
# https://stackoverflow.com/questions/50729099/bash-nginx-version-check-cut
###
command="nginx -v"
containerv=$(head -n 1 /CHANGELOG)
nginxv=$( ${command} 2>&1 )
nginxlocal=$(echo $nginxv | grep -o '[0-9.]*$')
### Get nginx version

echo "Check if $L_SITESENABLED_DIR is empty or if $L_SITESENABLED_DEFAULT exists"

if [ -z "$(ls -A $L_SITESENABLED_DIR)" ] || [ -f "$L_SITESENABLED_DEFAULT" ]; then
    echo "Copy default config to $L_SITESENABLED_DIR"
	/bin/cp -rf /media/defaults/sites-enabled/. "$L_SITESENABLED_DIR"
	if [ "$DISABLETLS" = "false" ]; then
		echo "Copy default tls config to $L_SITESENABLED_DIR"
		/bin/cp -rf /media/defaults/sites-enabled-ssl/. "$L_SITESENABLED_DIR"
	fi 
fi

if [ ! -f "$L_DHFILE" ] && [ "$DISABLETLS" = "false" ]; then
    echo "$L_DHFILE doesn't exist, create it, but it takes some time..."
	openssl dhparam -dsaparam -out "$L_DHFILE" 4096
fi

if [ ! -f "$L_CERTFILE" ] && [ "$DISABLETLS" = "false" ]; then
    echo "$L_CERTFILE doesn't exist, create it, but it takes some time..."
	openssl req -x509 -newkey rsa:4096 -out "$L_CERTFILE" -keyout "$L_KEYFILE" -days 365 -nodes -subj '/CN=localhost'
fi

touch /media/data/logs/access.log
touch /media/data/logs/error.log
touch /media/data/logs/access.1.log
touch /media/data/logs/error.1.log

echo "Starting container version ${containerv} with nginx version ${nginxlocal}..."
echo "Run $@"

/usr/sbin/crond -b -l 8

exec env OPENSSL_CONF=/etc/nginx/openssl.conf "$@" 2>&1
