#!/bin/bash
set -Eeo pipefail

# Set important directory and file variables
L_SITESENABLED_DIR="/application/data/sites-enabled/"
L_SITESENABLED_DEFAULT="/application/data/sites-enabled/default.conf"
L_SITESENABLED_SSL="/application/data/sites-enabled-ssl/default-ssl.conf"
L_SITESENABLED_REDIRECT="/application/data/sites-enabled-redirect/default-redirect.conf"
L_DHFILE="/application/data/dhparams/dhparam4096.dh"

# TLS mode: off, custom, acme
L_TLS_MODE="${TLS_MODE:-off}"
L_FORCE_TLS="${FORCE_TLS:-false}"
L_MAIL="${ACME_MAIL:-false}"
L_ACME_SERVER="${ACME_SERVER:-letsencrypt}"
L_OUTPUT_FORMAT="${OUTPUT_FORMAT:-human}"

# Logging function with timestamps (moved up for early use)
log() {
    local level="$1"
    local custom_icon="$2"
    shift 2
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$L_OUTPUT_FORMAT" = "json" ]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}"
    else
        # Human readable format with icons
        local icon=""
        case "$level" in
            "INFO") icon="ℹ️" ;;
            "WARN") icon="⚠️" ;;
            "ERROR") icon="❌" ;;
            "SUCCESS") icon="✅" ;;
            *) icon="📝" ;;
        esac
        
        # Add custom icon if provided (in addition to standard icon)
        if [ -n "$custom_icon" ]; then
            icon="$icon $custom_icon"
        fi
        
        echo "[$timestamp] $icon $message"
    fi
}

# Input validation
if [[ ! "$L_TLS_MODE" =~ ^(off|custom|acme)$ ]]; then
    log "ERROR" "🔧" "Invalid TLS_MODE: $L_TLS_MODE. Must be: off, custom, or acme" >&2
    exit 1
fi

if [[ ! "$L_FORCE_TLS" =~ ^(true|false)$ ]]; then
    log "ERROR" "🔧" "Invalid FORCE_TLS: $L_FORCE_TLS. Must be: true or false" >&2
    exit 1
fi

if [[ ! "$L_OUTPUT_FORMAT" =~ ^(human|json)$ ]]; then
    log "ERROR" "🔧" "Invalid OUTPUT_FORMAT: $L_OUTPUT_FORMAT. Must be: human or json" >&2
    exit 1
fi

# ACME specific validation
if [ "$L_TLS_MODE" = "acme" ] && { [ -z "$L_MAIL" ] || [ "$L_MAIL" = "false" ]; }; then
    log "ERROR" "🔧" "ACME_MAIL is required when TLS_MODE=acme" >&2
    exit 1
fi

### Get nginx version from system and changelog
# https://stackoverflow.com/questions/50729099/bash-nginx-version-check-cut
command="nginx -v"
containerv=$(head -n 1 /CHANGELOG 2>/dev/null)
nginxv=$( ${command} 2>&1 )
nginxlocal=$(echo $nginxv | grep -o '[0-9.]*$' || echo "unknown")
### End version check

if [ "$L_OUTPUT_FORMAT" = "human" ]; then
    cat <<'EOF'
              _            
             (_)           
  _ __   __ _ _ _ __ __  __
 | '_ \ / _` | | '_ \\ \/ /
 | | | | (_| | | | | |>  < 
 |_| |_|\__, |_|_| |_/_/\_\
         __/ |             
        |___/  in Docker            

EOF
fi

log "INFO" "📋" "Nginx version: ${nginxlocal} | Container version: ${containerv}"

log "INFO" "🔧" "TLS_MODE: $L_TLS_MODE | FORCE_TLS: $L_FORCE_TLS"

# Function: Copy configuration files
copy_nginx_configs() {
    # Only copy configs if sites-enabled directory is empty
    if [ -z "$(ls -A $L_SITESENABLED_DIR)" ]; then
        log "INFO" "📁" "$L_SITESENABLED_DIR is empty, copying default configuration..."
        case "$L_TLS_MODE" in
            off)
                log "INFO" "📝" "Copying default.conf to $L_SITESENABLED_DIR (TLS off)"
                if cp /application/defaults/sites-enabled/default.conf "$L_SITESENABLED_DIR"; then
                    log "SUCCESS" "📝" "Default configuration copied successfully"
                else
                    log "ERROR" "📝" "Failed to copy default.conf"
                    exit 1
                fi
                ;;
            custom|acme)
                log "INFO" "📝" "Copying default-ssl.conf to $L_SITESENABLED_DIR (TLS custom/acme)"
                if cp /application/defaults/sites-enabled-ssl/default-ssl.conf "$L_SITESENABLED_DIR"; then
                    log "SUCCESS" "📝" "SSL configuration copied successfully"
                else
                    log "ERROR" "📝" "Failed to copy default-ssl.conf"
                    exit 1
                fi
                ;;
        esac
        # If L_FORCE_TLS is true, copy redirect config (overrides previous config)
        if [ "$L_FORCE_TLS" = "true" ]; then
            log "INFO" "🔁" "FORCE_TLS is active, copying default-redirect.conf to $L_SITESENABLED_DIR"
            if cp /application/defaults/sites-enabled-redirect/default-redirect.conf "$L_SITESENABLED_DIR"; then
                log "SUCCESS" "🔁" "Redirect configuration copied successfully"
            else
                log "ERROR" "🔁" "Failed to copy default-redirect.conf"
                exit 1
            fi
        fi
        log "SUCCESS" "🔁" "Configuration files copied successfully"
    fi
}

# Function: Generate DH parameters
generate_dh_params() {
    if [ "$L_TLS_MODE" = "custom" ] || [ "$L_TLS_MODE" = "acme" ]; then
        if [ ! -f "$L_DHFILE" ]; then
            log "INFO" "🧮" "DH parameters missing, generating 4096-bit parameters (this may take a while)..."
            # Create directory with secure permissions
            mkdir -p "$(dirname "$L_DHFILE")"
            chmod 700 "$(dirname "$L_DHFILE")"
            
            # Generate DH params with progress suppressed, capture errors
            if openssl dhparam -dsaparam -out "$L_DHFILE" 4096 2>/tmp/dhparam_error.log >/dev/null; then
                chmod 644 "$L_DHFILE"
                log "SUCCESS" "🧮" "DH parameters generated successfully"
            else
                log "ERROR" "🧮" "Failed to generate DH parameters"
                if [ -f /tmp/dhparam_error.log ] && [ -s /tmp/dhparam_error.log ]; then
                    log "ERROR" "🧮" "OpenSSL error: $(cat /tmp/dhparam_error.log)"
                fi
                exit 1
            fi
        else
            log "INFO" "🧮" "DH parameters already exist"
        fi
    fi
}

# Function: Collect domains from nginx configs
collect_domains() {
    DOMAIN_GROUPS=()
    declare -A seen_domains
    
    for conf in "$L_SITESENABLED_DIR"*.conf; do
        if [ -f "$conf" ]; then
            # Check if SSL is enabled in this config
            ssl_enabled=false
            if grep -q "listen.*443.*ssl" "$conf" || grep -q "ssl_certificate" "$conf"; then
                ssl_enabled=true
            fi
            
            # Only collect domains if SSL is enabled
            if [ "$ssl_enabled" = true ]; then
                while read -r line; do
                    # Extract everything after 'server_name' up to the semicolon
                    domains=$(echo "$line" | sed -n 's/^\s*server_name\s\+\([^;]*\);.*/\1/p')
                    if [ -n "$domains" ]; then
                        # Deduplicate by creating a normalized key
                        normalized_key=$(echo "$domains" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')
                        if [ -z "${seen_domains[$normalized_key]}" ]; then
                            seen_domains[$normalized_key]=1
                            DOMAIN_GROUPS+=("$domains")
                        fi
                    fi
                done < "$conf"
            fi
        fi
    done
    
    # Log found domains for debugging
    if [ ${#DOMAIN_GROUPS[@]} -eq 0 ]; then
        log "WARN" "🔍" "No SSL-enabled domains found in nginx configurations"
    else
        log "INFO" "🔍" "Found ${#DOMAIN_GROUPS[@]} unique SSL-enabled domain group(s): ${DOMAIN_GROUPS[*]}"
    fi
}

# Function: Generate SSL certificates
generate_ssl_certificates() {
    if [ "$L_TLS_MODE" = "custom" ] || [ "$L_TLS_MODE" = "acme" ]; then
        for group in "${DOMAIN_GROUPS[@]}"; do
            cert_name=$(echo "$group" | tr ' ' '_' | tr '*' 'wildcard')
            cert_file="/application/data/certs/${cert_name}.pem"
            key_file="/application/data/certs/${cert_name}.key"
            need_cert=false
            if [ ! -f "$cert_file" ]; then
                need_cert=true
            else
                # Check certificate expiration date
                end_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$end_date" ]; then
                    # Convert OpenSSL date format "Aug  3 11:32:45 2026 GMT" to epoch
                    # Use AWK to parse and convert to standard date format
                    formatted_date=$(echo "$end_date" | awk '{
                        months["Jan"]=1; months["Feb"]=2; months["Mar"]=3; months["Apr"]=4;
                        months["May"]=5; months["Jun"]=6; months["Jul"]=7; months["Aug"]=8;
                        months["Sep"]=9; months["Oct"]=10; months["Nov"]=11; months["Dec"]=12;
                        # Handle potential double spaces in day field
                        day = $2; gsub(/^[ ]*/, "", day); gsub(/[ ]*$/, "", day);
                        printf "%04d-%02d-%02d %s\n", $4, months[$1], day, $3
                    }')
                    
                    # Try to convert to epoch, with fallback
                    if [ -n "$formatted_date" ]; then
                        end_epoch=$(date -d "$formatted_date" +%s 2>/dev/null || echo "0")
                    else
                        end_epoch=0
                    fi
                    
                    if [ "$end_epoch" -gt 0 ]; then
                        now_epoch=$(date +%s)
                        days_left=$(( (end_epoch - now_epoch) / 86400 ))
                        if [ "$days_left" -lt 30 ]; then
                            need_cert=true
                            log "INFO" "🔐" "Certificate for $group expires in $days_left days, renewal needed"
                        else
                            log "INFO" "🔐" "Certificate for $group valid for $days_left more days"
                        fi
                    else
                        log "WARN" "🔐" "Could not parse certificate expiration date for $group, will regenerate"
                        need_cert=true
                    fi
                else
                    need_cert=true
                fi
            fi
            if [ "$need_cert" = true ]; then
                log "INFO" "🔐" "Generating new certificate for: $group"
                # Create secure directory for private keys
                mkdir -p /application/data/certs
                chmod 700 /application/data/certs
                
                # Generate certificate with progress suppressed, capture errors
                if openssl req -x509 -newkey rsa:4096 -keyout "$key_file" -out "$cert_file" -days 365 -nodes -subj "/CN=$(echo $group | awk '{print $1}')" -addext "subjectAltName=$(echo $group | sed 's/\([^ ]\+\)/DNS:\1,/g;s/,$//')" 2>/tmp/cert_error.log >/dev/null; then
                    # Set secure permissions on private key
                    chmod 600 "$key_file"
                    chmod 644 "$cert_file"
                    log "SUCCESS" "🔐" "Certificate for $group created successfully with secure permissions"
                else
                    log "ERROR" "🔐" "OpenSSL certificate generation failed for $group"
                    if [ -f /tmp/cert_error.log ] && [ -s /tmp/cert_error.log ]; then
                        log "ERROR" "🔐" "OpenSSL error: $(cat /tmp/cert_error.log)"
                    fi
                    exit 1
                fi
            else
                log "INFO" "🔐" "Certificate for $group is valid"
            fi
        done
        log "SUCCESS" "🔐" "Certificate check completed"
    fi
}

# Function: Handle ACME certificate process
handle_acme_certificates() {
    if [ "$L_TLS_MODE" = "acme" ]; then
        ACME_SH="/root/.acme.sh/acme.sh"
        
        # Check if acme.sh exists
        if [ ! -f "$ACME_SH" ]; then
            log "ERROR" "🔧" "acme.sh not found at $ACME_SH"
            exit 1
        fi
        
        log "INFO" "🚀" "Starting ACME certificate process"
        
        # 1. Check and add location block in all configs
        for conf in "$L_SITESENABLED_DIR"*.conf; do
            if [ -f "$conf" ]; then
                server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
                if ! grep -q 'location[[:space:]]\^~[[:space:]]/\\.well-known/acme-challenge/' "$conf"; then
                    sed -i "/server_name/a \\n    location ^~ /.well-known/acme-challenge/ {\n        alias /application/data/webroot/$server_name/.well-known/acme-challenge/;\n        try_files \\\$uri =404;\n    }\n" "$conf"
                    log "INFO" "🛠️" "Added ACME challenge location block to $conf"
                fi
            fi
        done
        # 2. Start nginx temporarily in the background
        log "INFO" "🌐" "Starting temporary nginx for ACME challenge"
        
        # Test nginx configuration first
        if ! nginx -t 2>/dev/null; then
            log "ERROR" "🌐" "nginx configuration test failed"
            exit 1
        fi
        
        # Start nginx in background and capture any immediate errors
        nginx 2>/tmp/nginx_error.log &
        NGINX_PID=$!
        sleep 3
        
        # Check if nginx is still running and listening
        if ! ps -p $NGINX_PID > /dev/null 2>&1; then
            log "ERROR" "🌐" "nginx process died after startup"
            if [ -f /tmp/nginx_error.log ] && [ -s /tmp/nginx_error.log ]; then
                log "ERROR" "🌐" "nginx error: $(cat /tmp/nginx_error.log)"
            fi
            exit 1
        fi

        # 3. acme.sh for each domain group
        for group in "${DOMAIN_GROUPS[@]}"; do
            acme_domains=""
            for d in $group; do
                acme_domains="$acme_domains -d $d"
            done
            main_domain=$(echo $group | awk '{print $1}')
            WEBROOT="/application/data/webroot/$main_domain"
            mkdir -p "$WEBROOT/.well-known/acme-challenge/"
            cert_path="/application/data/certs/$(echo "$group" | tr ' ' '_' | tr '*' 'wildcard')"
            need_cert=false
            if [ ! -f "$cert_path.pem" ]; then
                need_cert=true
            else
                if openssl x509 -in "$cert_path.pem" -noout -issuer 2>/dev/null | grep -qi "self signed"; then
                    need_cert=true
                fi
            fi
            if [ "$need_cert" = true ]; then
                log "INFO" "🛡️" "Starting acme.sh for: $group (Webroot: $WEBROOT, Server: $L_ACME_SERVER)"
                if ! $ACME_SH --issue --ecc --keylength ec-384 --webroot "$WEBROOT" $acme_domains --server "$L_ACME_SERVER" --accountemail "$L_MAIL" --cert-file "$cert_path.pem" --key-file "$cert_path.key" --fullchain-file "$cert_path.fullchain.pem" --reloadcmd 'nginx -s reload'; then
                    log "ERROR" "🛡️" "acme.sh failed for $group"
                else
                    log "SUCCESS" "🛡️" "acme.sh succeeded for $group"
                fi
            else
                log "INFO" "🛡️" "acme.sh: Certificate for $group already exists and is valid"
            fi
        done
        # 4. Stop temporary nginx and wait for it to finish
        log "INFO" "🛑" "Stopping temporary nginx"
        if ! nginx -s stop; then
            log "WARN" "🛑" "nginx could not be stopped gracefully, trying kill"
            if ps -p $NGINX_PID > /dev/null 2>&1; then
                kill $NGINX_PID 2>/dev/null || true
            fi
        fi
        if ps -p $NGINX_PID > /dev/null 2>&1; then
            wait $NGINX_PID
        fi
        log "SUCCESS" "🛡️" "ACME certificate process completed"
    fi
}

# Function: Setup log files and directories
setup_environment() {
    # Ensure log files exist
    # (Nginx will not start if log files are missing)
    log "INFO" "🗂️" "Checking log files..."
    mkdir -p /application/data/logs
    for logfile in access.log error.log access.1.log error.1.log; do
        if ! touch "/application/data/logs/$logfile"; then
            log "ERROR" "🗂️" "Could not create log file: $logfile"
            exit 1
        fi
    done
    
    log "INFO" "📂" "Setting permissions for WebDAV directory..."
    mkdir -p /application/data/webdav
    if ! chown -R www-data:www-data /application/data/webdav 2>/dev/null; then
        log "WARN" "🗂️" "Could not set WebDAV permissions (user www-data may not exist)"
    fi
}

# Function: Start services
start_services() {
    log "INFO" "➡️" "Starting container..."

    # Start cron daemon in background for logrotate etc.
    log "INFO" "⏲️" "Starting cron daemon..."
    if /usr/sbin/crond -b -l 8; then
        log "SUCCESS" "⏲️" "Cron daemon started successfully"
    else
        log "WARN" "⏲️" "Cron daemon could not be started!"
    fi

    # Start nginx (or passed command) with OpenSSL config
    if [ $# -eq 0 ]; then
        log "INFO" "➡️" "No start command provided, starting nginx as default"
        env OPENSSL_CONF=/etc/nginx/openssl.conf nginx -g 'daemon off;' 2>&1
    else
        env OPENSSL_CONF=/etc/nginx/openssl.conf "$@" 2>&1
    fi
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================

# Copy nginx configuration files
copy_nginx_configs

# Generate DH parameters
generate_dh_params

# Setup environment (log files, directories)
setup_environment

# Collect domains from nginx configs
collect_domains

# Generate SSL certificates
generate_ssl_certificates

# Handle ACME certificate process
handle_acme_certificates

# Start services (nginx, cron)
start_services

