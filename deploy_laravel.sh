#!/bin/bash
# ==============================================
# 🚀 Laravel Multi-Domain Deploy Script (v1.4-safe+)
# Author        : Nasrul Muiz
# Version       : 1.4-safe+
# Description   : Safe deploy multi Laravel apps with rollback, multi-PHP, SSL, optimizations
# ==============================================

set -e
trap 'log_error "Deployment interrupted! Initiating rollback..."; rollback; exit 1' INT TERM

# ----------------------------
# Config & Defaults
# ----------------------------
SCRIPT_REPO="https://raw.githubusercontent.com/username/laravel-ultra-deploy/main/laravel_deploy.sh"
SCRIPT_PATH="$(realpath "$0")"

LOG_FILE="/var/log/laravel_ultra_deploy.log"
SILENT_MODE=0
WWW_DIR="/var/www"
BACKUP_DIR="/var/backups/laravel"
DEFAULT_PHP="7.4"
PHP_EXTENSIONS=(curl gd mbstring xml zip bcmath json)
COMPOSER_BIN="/usr/local/bin/composer"
CERTBOT_BIN="/usr/bin/certbot"
ROLLBACK_DIR="/var/backups/rollback"

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ----------------------------
# Detect silent mode
# ----------------------------
for arg in "$@"; do [[ "$arg" == "--silent" ]] && SILENT_MODE=1; done

# ----------------------------
# Helper functions
# ----------------------------
log() { echo -e "$(date '+%F %T') | $1" | tee -a "$LOG_FILE"; }
log_error() { log "${RED}ERROR: $1${NC}"; send_telegram "❌ ERROR: $1"; }
log_success() { log "${GREEN}SUCCESS: $1${NC}"; send_telegram "✅ SUCCESS: $1"; }
log_warning() { log "${YELLOW}WARNING: $1${NC}"; }

prompt() { [[ $SILENT_MODE -eq 1 ]] && echo "$2" || { read -rp "$1" input; echo "${input:-$2}"; }; }

send_telegram() { 
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$msg" -d parse_mode=Markdown >> "$LOG_FILE" 2>&1
}

rollback() {
    [[ -d "$ROLLBACK_DIR" ]] || return
    log_warning "Restoring apps from rollback..."
    for dir in "$ROLLBACK_DIR"/*/; do
        app=$(basename "$dir")
        rm -rf "$WWW_DIR/$app"
        cp -r "$dir" "$WWW_DIR/$app"
        log "Rolled back $app"
    done
    systemctl restart nginx
    for php_service in $(systemctl list-units --type=service | grep -Po 'php[0-9\.]+-fpm(?=\.service)'); do
        systemctl restart "$php_service"
    done
    log_warning "Rollback completed."
}

backup_app() {
    local app="$1"; local app_path="$WWW_DIR/$app"; local backup_path="$BACKUP_DIR/$app/$(date +%Y%m%d_%H%M%S)"
    [[ -d "$app_path" ]] || return
    mkdir -p "$backup_path"
    cp -r "$app_path" "$backup_path/"
    find "$app_path" -type f -exec sha256sum {} \; > "$backup_path/checksum.sha256"
    log_success "Backup created for $app: $backup_path"
}

install_php() {
    local version="$1"; log "Installing PHP $version..."
    packages=(php"$version" php"$version"-fpm)
    for ext in "${PHP_EXTENSIONS[@]}"; do packages+=("php$version-$ext"); done
    apt install -y "${packages[@]}" >> "$LOG_FILE" 2>&1
}

install_ioncube() {
    local php_version="$1"
    local php_ini="/etc/php/$php_version/fpm/php.ini"
    local ext_dir=$(php"$php_version" -i | grep extension_dir | awk '{print $3}')
    local ioncube_so="$ext_dir/ioncube_loader_lin_${php_version}.so"
    [[ -f "$ioncube_so" ]] && { log "ionCube already installed for PHP $php_version"; return; }
    log "Installing ionCube loader for PHP $php_version..."
    tmp=$(mktemp -d); cd "$tmp"
    curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o ioncube.tar.gz
    tar -xzf ioncube.tar.gz
    cp "ioncube/ioncube_loader_lin_${php_version}.so" "$ext_dir/"; chmod 644 "$ioncube_so"
    echo "zend_extension=$ioncube_so" >> "$php_ini"; systemctl restart "php$php_version-fpm"; rm -rf "$tmp"
    log_success "ionCube installed for PHP $php_version"
}

install_composer() { [[ -x "$COMPOSER_BIN" ]] && return; log "Installing Composer..."; curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; }

install_certbot() { [[ -x "$CERTBOT_BIN" ]] && return; log "Installing Certbot..."; apt install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1; }

auto_update_script() {
    log "Checking for script updates..."
    tmp=$(mktemp); curl -fsSL "$SCRIPT_REPO" -o "$tmp"
    if ! cmp -s "$tmp" "$SCRIPT_PATH"; then
        cp "$SCRIPT_PATH" "$SCRIPT_PATH.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$tmp" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        log_success "Script updated to latest version from GitHub."
        echo "Re-run the script to apply updates."
        exit 0
    fi
    rm -f "$tmp"
}

# ----------------------------
# Auto-update
# ----------------------------
auto_update_script

# ----------------------------
# Base deployment
# ----------------------------
log "🌟 Laravel Multi-Domain Deploy v1.4-safe+"
[[ $SILENT_MODE -eq 1 ]] && log "🤖 Silent mode" || log "🎨 Visual mode"
mkdir -p "$BACKUP_DIR" "$ROLLBACK_DIR"
apt update -y >> "$LOG_FILE" 2>&1
apt install -y nginx mariadb-server unzip curl git php-cli >> "$LOG_FILE" 2>&1

install_php "$DEFAULT_PHP"; install_ioncube "$DEFAULT_PHP"; install_composer; install_certbot

# Scan apps
APPS=(); mkdir -p "$WWW_DIR"
for dir in "$WWW_DIR"/*/; do [[ -f "${dir}artisan" ]] && APPS+=("$(basename "$dir")"); done
if [[ ${#APPS[@]} -eq 0 && $SILENT_MODE -eq 0 ]]; then
    read -rp "No Laravel apps found. Create new? (y/N): " create_app
    [[ "$create_app" =~ ^[Yy]$ ]] && { read -rp "App name: " new_app; mkdir -p "$WWW_DIR/$new_app"; APPS+=("$new_app"); }
fi
log "📦 Found ${#APPS[@]} apps: ${APPS[*]:-None}"

# Deploy apps
for APP in "${APPS[@]}"; do
    APP_PATH="$WWW_DIR/$APP"; mkdir -p "$APP_PATH"; log "🚀 Deploying $APP"; backup_app "$APP"
    cp -r "$APP_PATH" "$ROLLBACK_DIR/$APP" 2>/dev/null || true

    [[ ! -f "$APP_PATH/artisan" ]] && { log "Installing Laravel for $APP..."; composer create-project laravel/laravel "$APP_PATH" >> "$LOG_FILE" 2>&1; }

    PHP_VERSION=$(prompt "PHP version for $APP [$DEFAULT_PHP]: " "$DEFAULT_PHP")
    systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm" || install_php "$PHP_VERSION"; install_ioncube "$PHP_VERSION"

    # Database safe creation
    DB_NAME="${APP,,}_db"; DB_USER="${APP,,}_user"
    EXIST_DB=$(mysql -e "SHOW DATABASES LIKE '$DB_NAME';" | grep "$DB_NAME" || true)
    if [[ -z "$EXIST_DB" ]]; then
        DB_PASS=$(openssl rand -base64 16)
        mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
        mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
        log_success "Database $DB_NAME created with user $DB_USER"
    else
        DB_PASS="******** (existing)"
        log "Database $DB_NAME exists. Using existing user/password."
    fi
    DB_CRED_FILE="/root/.db_${APP}.cred"
    echo -e "DB_NAME=$DB_NAME\nDB_USER=$DB_USER\nDB_PASS=$DB_PASS" > "$DB_CRED_FILE"; chmod 600 "$DB_CRED_FILE"

    # Permissions
    chown -R www-data:www-data "$APP_PATH"
    find "$APP_PATH" -type d -exec chmod 755 {} \;
    find "$APP_PATH" -type f -exec chmod 644 {} \;
    [[ -d "$APP_PATH/storage" ]] && chmod -R 775 "$APP_PATH/storage"
    [[ -d "$APP_PATH/bootstrap/cache" ]] && chmod -R 775 "$APP_PATH/bootstrap/cache"

    # .env only if missing
    DOMAIN=$(prompt "Domain for $APP (use * for wildcard) [$APP.local]: " "$APP.local")
    ENV_FILE="$APP_PATH/.env"
    if [[ ! -f "$ENV_FILE" ]]; then
        cat > "$ENV_FILE" <<EOF
APP_NAME="$APP"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://$DOMAIN
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS
EOF
        chown www-data:www-data "$ENV_FILE"; chmod 640 "$ENV_FILE"
        php "$APP_PATH/artisan" key:generate >> "$LOG_FILE" 2>&1
    fi

    # Laravel optimizations
    php "$APP_PATH/artisan" config:cache >> "$LOG_FILE" 2>&1 || true
    php "$APP_PATH/artisan" route:cache >> "$LOG_FILE" 2>&1 || true
    php "$APP_PATH/artisan" view:cache >> "$LOG_FILE" 2>&1 || true

    # Nginx config only if missing
    VHOST_FILE="/etc/nginx/sites-available/$APP.conf"
    if [[ ! -f "$VHOST_FILE" ]]; then
        cat > "$VHOST_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $APP_PATH/public;
    index index.php index.html index.htm;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock; }
    location ~ /\.ht { deny all; }
    client_max_body_size 100M;
}
EOF
        ln -sf "$VHOST_FILE" "/etc/nginx/sites-enabled/$APP.conf"
    fi

    # SSL provisioning
    if [[ "$DOMAIN" != "*" && "$DOMAIN" != "$APP.local" ]]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN >> "$LOG_FILE" 2>&1 || log_warning "SSL issue for $DOMAIN"
    fi

    # Telegram notification
    msg="✅ Laravel App Deployed: *$APP*\nDomain: $DOMAIN\nPath: $APP_PATH\nDB: $DB_NAME\nUser: $DB_USER"
    send_telegram "$msg"
done

# Validate & restart
nginx -t >> "$LOG_FILE" 2>&1 && log_success "Nginx config OK" || { log_error "Nginx config error"; rollback; exit 1; }
systemctl restart nginx
for php_service in $(systemctl list-units --type=service | grep -Po 'php[0-9\.]+-fpm(?=\.service)'); do systemctl restart "$php_service"; done

# Cron SSL renewal
(crontab -l 2>/dev/null; echo "30 2 * * * $CERTBOT_BIN renew --quiet >> $LOG_FILE 2>&1") | crontab -

log_success "🎉 All deployments completed!"
[[ $SILENT_MODE -eq 0 ]] && echo -e "\n${GREEN}✅ Deployment Summary:${NC}"
for APP in "${APPS[@]}"; do
    DOMAIN=$(grep -E '^APP_URL=' "$WWW_DIR/$APP/.env" | cut -d '=' -f2-)
    echo "App: $APP | Domain: $DOMAIN | Path: $WWW_DIR/$APP | DB: $DB_NAME | User: $DB_USER"
done
log "📄 Log file: $LOG_FILE"
log "📦 Backups: $BACKUP_DIR"
log "🔑 DB credentials: /root/.db_*.cred"
