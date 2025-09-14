#!/bin/bash
set -Eeo pipefail

# Set secure umask for created files (e.g., keys 640/600)
umask 027

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
L_ECC="${ACME_ECC:-true}"
L_KEYLENGTH="${ACME_KEYLENGTH:-ec-384}"
L_OUTPUT_FORMAT="${OUTPUT_FORMAT:-human}"

L_COMMAND=("$@")

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

if [[ ! "$L_ECC" =~ ^(true|false)$ ]]; then
    log "ERROR" "🔧" "Invalid ACME_ECC: $L_ECC. Must be: true or false" >&2
    exit 1
fi

if [[ ! "$L_KEYLENGTH" =~ ^(ec-256|ec-384|3072|4096)$ ]]; then
    log "ERROR" "🔧" "Invalid ACME_KEYLENGTH: $L_KEYLENGTH. Must be: ec-256, ec-384, 3072, or 4096" >&2
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
    mkdir -p "$L_SITESENABLED_DIR"
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
            if openssl dhparam -dsaparam -out "$L_DHFILE" 4096 2>/application/tmp/dhparam_error.log >/dev/null; then
                chmod 644 "$L_DHFILE"
                log "SUCCESS" "🧮" "DH parameters generated successfully"
            else
                log "ERROR" "🧮" "Failed to generate DH parameters"
                if [ -f /application/tmp/dhparam_error.log ] && [ -s /application/tmp/dhparam_error.log ]; then
                    log "ERROR" "🧮" "OpenSSL error: $(cat /application/tmp/dhparam_error.log)"
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
                chmod 750 /application/data/certs
                
                # Generate certificate with progress suppressed, capture errors
                if openssl req -x509 -newkey rsa:4096 -keyout "$key_file" -out "$cert_file" -days 365 -nodes -subj "/CN=$(echo $group | awk '{print $1}')" -addext "subjectAltName=$(echo $group | sed 's/\([^ ]\+\)/DNS:\1,/g;s/,$//')" 2>/application/tmp/cert_error.log >/dev/null; then
                    # Set secure permissions on private key and cert
                    chmod 600 "$key_file"
                    chmod 640 "$cert_file"
                    log "SUCCESS" "🔐" "Certificate for $group created successfully with secure permissions"
                else
                    log "ERROR" "🔐" "OpenSSL certificate generation failed for $group"
                    if [ -f /application/tmp/cert_error.log ] && [ -s /application/tmp/cert_error.log ]; then
                        log "ERROR" "🔐" "OpenSSL error: $(cat /application/tmp/cert_error.log)"
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
        ACME_SH="/application/bin/acmesh/acme.sh"
        
        # Check if acme.sh exists
        if [ ! -f "$ACME_SH" ]; then
            log "ERROR" "🔧" "acme.sh not found at $ACME_SH"
            exit 1
        fi
        
        log "INFO" "🚀" "Starting ACME certificate process"
        
        # 1. Check and add location block in all configs
        for conf in "$L_SITESENABLED_DIR"*.conf; do
            if [ -f "$conf" ]; then
                server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//' | tr -cd '[:alnum:].-')
                # Only add ACME location block if the challenge path is not already present
                if ! grep -qF '/.well-known/acme-challenge/' "$conf"; then
                    # Define location block in variable
                    LOCATION_BLOCK=$(cat <<EOF

    location ^~ /.well-known/acme-challenge/ {
        alias /application/data/webroot/$server_name/.well-known/acme-challenge/;
        try_files \$uri =404;
    }

EOF
)
                    # Insert the content after the server_name line
                    echo "$LOCATION_BLOCK" | sed -i "/server_name/r /dev/stdin" "$conf"
                    log "INFO" "🛠️" "Added ACME challenge location block to $conf"
                fi
            fi
        done
        # 2. Start nginx temporarily in the background
        log "INFO" "🌐" "Starting temporary nginx for ACME challenge"

        # Test nginx configuration first
        if ! nginx -t 2>/dev/null; then
            log "ERROR" "🌐" "nginx configuration test failed"
            nginx -t
            exit 1
        fi
        
        # Start nginx in background and capture any immediate errors
        nginx 2>/application/tmp/nginx_error.log &
        NGINX_PID=$!
        sleep 3

        # Get the actual nginx master process PID
        NGINX_MASTER_PID=$(ps | grep "nginx: master process" | grep -v grep | awk '{print $1}')
        
        # Check if nginx is still running and listening
        if [ -n "$NGINX_MASTER_PID" ]; then
            log "SUCCESS" "🌐" "nginx master process (PID: $NGINX_MASTER_PID) is running"
        else
            log "ERROR" "🌐" "nginx process died after startup"
            if [ -f /application/tmp/nginx_error.log ] && [ -s /application/tmp/nginx_error.log ]; then
                log "ERROR" "🌐" "nginx error: $(cat /application/tmp/nginx_error.log)"
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
                # Check if certificate is self-signed by comparing subject and issuer
                subject=$(openssl x509 -in "$cert_path.pem" -noout -subject 2>/dev/null | cut -d= -f2-)
                issuer=$(openssl x509 -in "$cert_path.pem" -noout -issuer 2>/dev/null | cut -d= -f2-)
                if [ "$subject" = "$issuer" ]; then
                    need_cert=true
                    log "INFO" "🛡️" "Certificate for $group is self-signed, will request ACME certificate"
                fi
            fi
            if [ "$need_cert" = true ]; then
                log "INFO" "🛡️" "Starting acme.sh for: $group (Webroot: $WEBROOT, Server: $L_ACME_SERVER, ECC: $L_ECC, KeyLength: $L_KEYLENGTH)"
                
                # Build acme.sh command with configurable parameters
                acme_cmd="$ACME_SH --issue --webroot \"$WEBROOT\" $acme_domains --server \"$L_ACME_SERVER\" --accountemail \"$L_MAIL\" --cert-file \"$cert_path.pem\" --key-file \"$cert_path.key\" --fullchain-file \"$cert_path.fullchain.pem\" --reloadcmd 'nginx -s reload' --cert-home /application/data/certs/acmesh/certs --config-home /application/data/certs/acmesh/config --ca-path /application/data/certs/acmesh/ca"
                
                # Add ECC and keylength parameters if ECC is enabled
                if [ "$L_ECC" = "true" ]; then
                    acme_cmd="$acme_cmd --ecc --keylength $L_KEYLENGTH"
                else
                    # For RSA keys, only use numeric keylengths
                    case "$L_KEYLENGTH" in
                        "3072"|"4096")
                            acme_cmd="$acme_cmd --keylength $L_KEYLENGTH"
                            ;;
                        *)
                            log "WARN" "🛡️" "RSA mode selected but ECC keylength specified, using default RSA 4096"
                            acme_cmd="$acme_cmd --keylength 4096"
                            ;;
                    esac
                fi
                
                # Execute acme.sh command
                if eval $acme_cmd; then
                    # Enforce secure permissions on issued files
                    chmod 600 "$cert_path.key" 2>/dev/null || true
                    chmod 640 "$cert_path.pem" "$cert_path.fullchain.pem" 2>/dev/null || true
                    log "SUCCESS" "🛡️" "acme.sh succeeded for $group"
                else
                    log "ERROR" "🛡️" "acme.sh failed for $group"
                fi
            else
                log "INFO" "🛡️" "acme.sh: Certificate for $group already exists and is valid"
            fi
        done
        # 4. Stop temporary nginx and wait for it to finish
        log "INFO" "🛑" "Stopping temporary nginx"

        nginx -s stop 2>/dev/null;
        
        # Wait for nginx master process to stop
        if [ -n "$(ps | grep "0:00 nginx:" | grep -v grep)" ]; then
            local count=0
            while [ -n "$(ps | grep "0:00 nginx:" | grep -v grep)" ] && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            # Force kill if still running
            if [ -n "$(ps | grep "0:00 nginx:" | grep -v grep)" ]; then
                log "WARN" "🛑" "Force killing nginx processes"
                kill -9 $NGINX_MASTER_PID 2>/dev/null || true
                ps | grep "0:00 nginx:" | grep -v grep | awk '{print $1}' | xargs -r kill -9 2>/dev/null || true
            fi
        fi
        log "SUCCESS" "🛡️" "ACME certificate process completed"
    fi
}

check_directory() {
    local dir="$1"
    local description="${2:-$dir}"
    local require_write="${3:-false}"    # boolean: true = require write permissions
    local create_if_missing="${4:-false}" # only allowed/used if require_write=true

    # create_if_missing is only permitted when write is required
    if [ "$create_if_missing" = "true" ] && [ "$require_write" != "true" ]; then
        log "WARN" "📂" "create_if_missing is only allowed when write is required; ignoring create flag for $description"
        create_if_missing=false
    fi

    # Ensure existence (create only when allowed)
    if [ ! -e "$dir" ]; then
        if [ "$create_if_missing" = "true" ]; then
            if ! mkdir -p "$dir" 2>/dev/null; then
                log "ERROR" "📂" "Failed to create $description - aborting"
                exit 1
            fi
        else
            log "ERROR" "📂" "$description does not exist (creation disabled) - aborting"
            exit 1
        fi
    fi

    # Must be a directory
    if [ ! -d "$dir" ]; then
        log "ERROR" "📂" "$description exists but is not a directory - aborting"
        exit 1
    fi

    # Recursive permission checks for directory tree
    if [ "$require_write" = "true" ]; then
        # need write + execute on all directories to allow creating files/dirs
        while IFS= read -r -d '' subdir; do
            if [ ! -w "$subdir" ] || [ ! -x "$subdir" ]; then
                log "ERROR" "📂" "No write/exec permissions for $description (problem at $subdir) - aborting"
                exit 1
            fi
        done < <(find "$dir" -type d -print0 2>/dev/null)
    else
        # need read + execute on all directories to allow listing/traversal
        while IFS= read -r -d '' subdir; do
            if [ ! -r "$subdir" ] || [ ! -x "$subdir" ]; then
                log "ERROR" "📂" "No read/exec permissions for $description (problem at $subdir) - aborting"
                exit 1
            fi
        done < <(find "$dir" -type d -print0 2>/dev/null)
    fi
}

# Function: Check file permissions and create if needed
check_file() {
    local file="$1"
    local description="${2:-$file}"
    
    if [ -f "$file" ] && [ ! -w "$file" ]; then
        log "ERROR" "📄" "No write permissions for $description - aborting"
        exit 1
    fi
}

# Copy the contents of a directory to a destination (creates destination if needed).
# On error, logs a message and exits with a non-zero status.
copy_directory() {
    local src="$1"
    local dst="$2"
    local description="${3:-$dst}"
    local no_overwrite="${4:-false}"  # when true, do not overwrite existing files (merge only)

    if [ -z "$src" ] || [ -z "$dst" ]; then
        log "ERROR" "📁" "copy_directory: Source and destination must be provided" >&2
        exit 1
    fi

    if [ ! -d "$src" ]; then
        log "ERROR" "📁" "Source directory not found: $src" >&2
        exit 1
    fi

    # Collect stderr temporarily
    mkdir -p /application/tmp 2>/dev/null || true
    local errlog="/application/tmp/copy_error.log"
    : > "$errlog"

    # Create destination directory (if not present)
    if ! mkdir -p "$dst" 2>"$errlog"; then
        log "ERROR" "📁" "Could not create target directory $description: $dst" >&2
        [ -s "$errlog" ] && log "ERROR" "📁" "Error details: $(cat "$errlog")" >&2
        exit 1
    fi

    # Choose cp options: -a (archive). Add -n to avoid overwriting existing files when requested
    local cp_opts="-a"
    if [ "$no_overwrite" = "true" ]; then
        cp_opts="-an"
    fi

    # Copy contents (only inner files/dirs, not the parent directory itself)
    if cp $cp_opts "$src/." "$dst/" 2>"$errlog"; then
        if [ "$no_overwrite" = "true" ]; then
            log "SUCCESS" "📁" "Merged defaults without overwriting: $src -> $dst"
        else
            log "SUCCESS" "📁" "Successfully copied: $src -> $dst"
        fi
    else
        log "ERROR" "📁" "Error copying from $src to $dst" >&2
        [ -s "$errlog" ] && log "ERROR" "📁" "Error details: $(cat "$errlog")" >&2
        exit 1
    fi
}

# Function: Setup log files and directories
setup_environment() {
    log "INFO" "📂" "Preparing writable runtime directories..."

    check_directory "/application/data" "Data directory /application/data" true true

    # Merge defaults into /application/data but keep any existing user data intact
    copy_directory "/application/data-fs" "/application/data" "Default data files" true
    
    # Base: temporary and runtime directories under /application
    check_directory "/application/tmp" "Runtime directory /application/tmp" true true
    check_directory "/application/run" "Runtime directory /application/run" true true

    # Nginx runtime subdirectories (matching nginx.conf temp paths)
    for d in nginx client_body_temp proxy_temp fastcgi_temp uwsgi_temp scgi_temp; do
        check_directory "/application/run/$d" "Nginx runtime subdirectory /application/run/$d" true true
    done

    # Data directories
    check_directory "/application/data/certs" "Certificates directory /application/data/certs" true false
    check_directory "/application/data/dhparams" "DH parameters directory /application/data/dhparams" true true
    check_directory "/application/data/locations" "Locations directory /application/data/locations" false
    check_directory "/application/data/logs" "Logs directory /application/data/logs" true true
    check_directory "/application/data/passwords" "Passwords directory /application/data/passwords" false
    check_directory "/application/data/sites-enabled" "Sites enabled directory /application/data/sites-enabled" true true
    check_directory "/application/data/streams" "Streams directory /application/data/streams" false
    check_directory "/application/data/webdav" "WebDAV directory /application/data/webdav" true true
    check_directory "/application/data/webroot" "Webroot directory /application/data/webroot" false

    # ACME configuration directories (mounted via volume)
    check_directory "/application/data/certs/acmesh/config" "ACME config directory /application/data/certs/acmesh/config" true true
    check_directory "/application/data/certs/acmesh/certs" "ACME certs directory /application/data/certs/acmesh/certs" true true

    # PID file (new path under /application/run)
    check_file "/application/run/nginx.pid" "nginx PID file /application/run/nginx.pid"

    log "SUCCESS" "📂" "Runtime directories ready"
}

# Function: Start services
start_services() {
    # Start cron daemon in background for logrotate etc.
    log "INFO" "⏲️" "Starting cron daemon..."
    if /usr/sbin/crond -b -l 8; then
        log "SUCCESS" "⏲️" "Cron daemon started successfully"
    else
        log "ERROR" "⏲️" "Cron daemon could not be started!"
        exit 1;
    fi

    # Start nginx (or passed command) with OpenSSL config
    if [ ${#L_COMMAND[@]} -eq 0 ]; then
        log "INFO" "➡️" "No start command provided, starting nginx as default"
        env OPENSSL_CONF=/etc/nginx/openssl.conf nginx -g 'daemon off;' 2>&1
    else
        log "INFO" "➡️" "Starting with command: ${L_COMMAND[*]}"
        env OPENSSL_CONF=/etc/nginx/openssl.conf "${L_COMMAND[@]}" 2>&1
    fi
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================
# Setup environment (log files, directories)
setup_environment

# Copy nginx configuration files
copy_nginx_configs

# Generate DH parameters
generate_dh_params

# Collect domains from nginx configs
collect_domains

# Generate SSL certificates
generate_ssl_certificates

# Handle ACME certificate process
handle_acme_certificates

# Start services (nginx, cron)
start_services

