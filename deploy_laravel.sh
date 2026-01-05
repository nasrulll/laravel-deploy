#!/bin/bash
# ==============================================
# 🚀 Laravel Multi-Domain Deploy Script
# Version       : 1.4-safe++
# Author        : Nasrul Muiz
# Description   : Deploy multi Laravel apps from /var/www/
#                 Self-sufficient (installs curl if missing)
#                 Supports silent (--silent) & visual mode
# ==============================================

set -e

# ----------------------------
# 🌟 Config & Defaults
# ----------------------------
LOG_FILE="/var/log/laravel_ultra_deploy.log"
SILENT_MODE=0
WWW_DIR="/var/www"
BACKUP_DIR="/var/backups/laravel"
SCRIPT_REPO="https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/deploy_laravel.sh"

# ----------------------------
# 🎯 Detect Silent Mode
# ----------------------------
for arg in "$@"; do
    [[ "$arg" == "--silent" ]] && SILENT_MODE=1
done

# ----------------------------
# 🖌 Helper Functions
# ----------------------------
log() { echo -e "$(date '+%F %T') | $1" | tee -a "$LOG_FILE"; }
log_error() { log "ERROR: $1"; }
log_success() { log "SUCCESS: $1"; }

prompt() {
    local msg="$1"
    local default="$2"
    if [[ $SILENT_MODE -eq 1 ]]; then
        echo "$default"
    else
        read -rp "$msg" input
        echo "${input:-$default}"
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ----------------------------
# ⚡ Ensure curl exists
# ----------------------------
if ! check_cmd curl; then
    log "🔧 curl not found. Installing curl..."
    apt update -y >> "$LOG_FILE" 2>&1
    apt install -y curl >> "$LOG_FILE" 2>&1
    log_success "curl installed"
fi

# ----------------------------
# 🔄 Auto-update Script (Safe)
# ----------------------------
log "🔄 Checking for script updates..."
TMP_SCRIPT=$(mktemp)
if curl -fsSL "$SCRIPT_REPO" -o "$TMP_SCRIPT"; then
    log_success "Latest script downloaded"
    chmod +x "$TMP_SCRIPT"
else
    log_error "Cannot download latest script. Continuing with current version."
fi

# ----------------------------
# 🌐 Ensure directories exist
# ----------------------------
mkdir -p "$WWW_DIR" "$BACKUP_DIR"

# ----------------------------
# 1️⃣ Install Dependencies
# ----------------------------
log "💻 Installing dependencies..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y nginx mariadb-server php7.4 php7.4-fpm php7.4-mysql unzip git curl >> "$LOG_FILE" 2>&1

# ----------------------------
# 2️⃣ ionCube Loader
# ----------------------------
PHP_EXT_DIR=$(php-config --extension-dir 2>/dev/null || echo "/usr/lib/php/20190902/")
IONCUBE_SO="ioncube_loader_lin_7.4.so"
IONCUBE_PATH="$PHP_EXT_DIR/$IONCUBE_SO"

if [[ ! -f "$IONCUBE_PATH" ]]; then
    log "🔧 Installing ionCube loader..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o ioncube.tar.gz
    tar -xzf ioncube.tar.gz
    cp "ioncube/$IONCUBE_SO" "$PHP_EXT_DIR/"
    chmod 644 "$IONCUBE_PATH"
    echo "zend_extension=$IONCUBE_PATH" >> /etc/php/7.4/fpm/php.ini
    systemctl restart php7.4-fpm
    cd /
    rm -rf "$TEMP_DIR"
    log_success "ionCube loader installed"
else
    log "ionCube loader already installed"
fi

# ----------------------------
# 3️⃣ Scan /var/www for Laravel apps
# ----------------------------
log "🔍 Scanning $WWW_DIR for Laravel applications..."
APPS=()
for dir in "$WWW_DIR"/*; do
    [[ -f "$dir/artisan" ]] && APPS+=("$(basename "$dir")")
done

APP_COUNT=${#APPS[@]}
log "📦 Found $APP_COUNT Laravel apps: ${APPS[*]}"

# ----------------------------
# 4️⃣ Deploy Each App
# ----------------------------
for APP in "${APPS[@]}"; do
    APP_PATH="$WWW_DIR/$APP"
    log "🚀 Deploying $APP"

    # PHP version
    PHP_VERSION="7.4"
    [[ $SILENT_MODE -eq 0 ]] && PHP_VERSION=$(prompt "Enter PHP version for $APP [7.4]: " "7.4")

    # Backup
    BACKUP_PATH="$BACKUP_DIR/$APP/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_PATH"
    cp -r "$APP_PATH" "$BACKUP_PATH/" 2>/dev/null || true
    log_success "Backup created: $BACKUP_PATH"

    # Database
    DB_NAME=$(echo "$APP" | tr '[:upper:]' '[:lower:]')_db
    DB_USER=$(echo "$APP" | tr '[:upper:]' '[:lower:]')_user
    DB_PASS=$(openssl rand -base64 12)
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "\n💾 DB INFO for $APP"
    echo "Database : $DB_NAME"
    echo "User     : $DB_USER"
    echo "Password : $DB_PASS"
    echo "---------------------------"

    # Permissions
    chown -R www-data:www-data "$APP_PATH"
    chmod -R 775 "$APP_PATH/storage" "$APP_PATH/bootstrap/cache"

    # Nginx
    VHOST_FILE="/etc/nginx/sites-available/$APP.conf"
    DOMAIN="$APP.local"
    [[ $SILENT_MODE -eq 0 ]] && DOMAIN=$(prompt "Enter domain for $APP [$APP.local]: " "$APP.local")

    cat > "$VHOST_FILE" <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    root $APP_PATH/public;

    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    client_max_body_size 100M;
}
EOL
    ln -sf "$VHOST_FILE" /etc/nginx/sites-enabled/
done

# ----------------------------
# 5️⃣ Restart Services
# ----------------------------
log "🔁 Restarting Nginx and PHP-FPM"
systemctl restart nginx
systemctl restart php7.4-fpm

# ----------------------------
# ✅ Finish
# ----------------------------
log "🎉 Laravel Multi-Domain Deploy Completed!"
[[ $SILENT_MODE -eq 0 ]] && echo "All done! Check $LOG_FILE for details."
