#!/bin/bash
# ==============================================
# 🚀 Laravel Multi-Domain Deploy Script
# Version       : 1.0
# Author        : Nasrul Muiz
# Description   : Deploy multi Laravel apps from /var/www/
#                 Supports silent (--silent) & visual mode
# ==============================================

# ----------------------------
# 🌟 Config & Defaults
# ----------------------------
LOG_FILE="/var/log/laravel_ultra_deploy.log"
SILENT_MODE=0
WWW_DIR="/var/www"

# ----------------------------
# 🎯 Detect Silent Mode
# ----------------------------
for arg in "$@"; do
    if [[ "$arg" == "--silent" ]]; then
        SILENT_MODE=1
    fi
done

# ----------------------------
# 🖌 Helper Functions
# ----------------------------
log() {
    local msg="$1"
    echo -e "$(date '+%F %T') | $msg" | tee -a "$LOG_FILE"
}

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

# ----------------------------
# ⚡ Start Deployment
# ----------------------------
log "🌟 Starting Laravel Multi-Domain Deploy Script"
[[ $SILENT_MODE -eq 1 ]] && echo "🤖 Running in Silent Ultra-Automated Mode" || echo "🎨 Running in Visual Mode"

# ----------------------------
# 1️⃣ Install Dependencies (PHP, Nginx, MariaDB, ionCube)
# ----------------------------
log "💻 Installing dependencies..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y nginx mariadb-server php7.4 php7.4-fpm php7.4-mysql unzip curl >> "$LOG_FILE" 2>&1

# Install ionCube loader for PHP 7.4
IONCUBE_DIR="/usr/local/ioncube"
if [ ! -d "$IONCUBE_DIR" ]; then
    log "🔧 Installing ionCube PHP Loader..."
    curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o /tmp/ioncube.tar.gz
    tar -xzf /tmp/ioncube.tar.gz -C /tmp
    cp /tmp/ioncube/ioncube_loader_lin_7.4.so /usr/lib/php/20210902/
    echo "zend_extension=/usr/lib/php/20210902/ioncube_loader_lin_7.4.so" >> /etc/php/7.4/fpm/php.ini
    systemctl restart php7.4-fpm
fi

# ----------------------------
# 2️⃣ Scan /var/www for Laravel apps
# ----------------------------
log "🔍 Scanning $WWW_DIR for Laravel applications..."
APPS=()
for dir in "$WWW_DIR"/*; do
    if [ -f "$dir/artisan" ]; then
        APPS+=("$(basename "$dir")")
    fi
done

APP_COUNT=${#APPS[@]}
log "📦 Found $APP_COUNT Laravel apps: ${APPS[*]}"

# ----------------------------
# 3️⃣ Deploy Each App
# ----------------------------
for APP in "${APPS[@]}"; do
    APP_PATH="$WWW_DIR/$APP"
    log "🚀 Deploying $APP"

    # Auto-detect PHP version (default 7.4)
    PHP_VERSION="7.4"
    [[ $SILENT_MODE -eq 0 ]] && PHP_VERSION=$(prompt "Enter PHP version for $APP [7.4]: " "7.4")

    # Create database automatically
    DB_NAME=$(echo "$APP" | tr '[:upper:]' '[:lower:]')_db
    DB_USER=$(echo "$APP" | tr '[:upper:]' '[:lower:]')_user
    DB_PASS=$(openssl rand -base64 12)
    log "🗄️ Creating database $DB_NAME with user $DB_USER"
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "\n💾 DB INFO for $APP"
    echo "Database : $DB_NAME"
    echo "User     : $DB_USER"
    echo "Password : $DB_PASS"
    echo "---------------------------"

    # Fix permission
    log "🔑 Fixing permissions for $APP"
    chown -R www-data:www-data "$APP_PATH"
    chmod -R 775 "$APP_PATH/storage" "$APP_PATH/bootstrap/cache"

    # Setup Nginx vhost
    VHOST_FILE="/etc/nginx/sites-available/$APP.conf"
    log "🌐 Creating Nginx config for $APP"
    cat > "$VHOST_FILE" <<EOL
server {
    listen 80;
    server_name $APP.local;
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
}
EOL

    ln -sf "$VHOST_FILE" /etc/nginx/sites-enabled/
done

# ----------------------------
# 4️⃣ Restart Services
# ----------------------------
log "🔁 Restarting Nginx and PHP-FPM"
systemctl restart nginx
systemctl restart php7.4-fpm

# ----------------------------
# ✅ Finish
# ----------------------------
log "🎉 Laravel Multi-Domain Deploy Completed!"
[[ $SILENT_MODE -eq 0 ]] && echo "All done! Check /var/log/laravel_ultra_deploy.log for details."
