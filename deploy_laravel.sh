#!/bin/bash
# ==============================================
# 🚀 Laravel Multi-Domain Deploy Script
# Version       : 2.0-enhanced
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
ERROR_LOG_FILE="/var/log/laravel_ultra_deploy_errors.log"
SILENT_MODE=0
WWW_DIR="/var/www"
BACKUP_DIR="/var/backups/laravel"
SCRIPT_REPO="https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/deploy_laravel.sh"
MAX_BACKUPS=5  # Jumlah maksimum backup yang disimpan
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")

# ----------------------------
# 🎯 Detect Arguments
# ----------------------------
for arg in "$@"; do
    case "$arg" in
        "--silent") SILENT_MODE=1 ;;
        "--help"|"-h") show_help; exit 0 ;;
        "--version"|"-v") echo "Version 2.0-enhanced"; exit 0 ;;
    esac
done

# ----------------------------
# 🖌 Helper Functions
# ----------------------------
log() { echo -e "$(date '+%F %T') | $1" | tee -a "$LOG_FILE"; }
log_error() { 
    echo -e "$(date '+%F %T') | ERROR: $1" | tee -a "$LOG_FILE" >> "$ERROR_LOG_FILE"
    [[ $SILENT_MODE -eq 0 ]] && echo -e "❌ $1"
}
log_warning() { 
    echo -e "$(date '+%F %T') | WARNING: $1" | tee -a "$LOG_FILE"
    [[ $SILENT_MODE -eq 0 ]] && echo -e "⚠️  $1"
}
log_success() { 
    echo -e "$(date '+%F %T') | SUCCESS: $1" | tee -a "$LOG_FILE"
    [[ $SILENT_MODE -eq 0 ]] && echo -e "✅ $1"
}
log_info() { 
    echo -e "$(date '+%F %T') | INFO: $1" | tee -a "$LOG_FILE"
    [[ $SILENT_MODE -eq 0 ]] && echo -e "ℹ️  $1"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --silent, -s    Run in silent mode (no prompts)
  --help, -h      Show this help message
  --version, -v   Show script version

Description:
  Deploy multiple Laravel applications from /var/www/
  Automatically installs dependencies and configures each app
EOF
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

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

validate_domain() {
    local domain="$1"
    # Validasi format domain sederhana
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_php_version() {
    local version="$1"
    for valid_version in "${PHP_VERSIONS[@]}"; do
        if [[ "$version" == "$valid_version" ]]; then
            return 0
        fi
    done
    return 1
}

cleanup_old_backups() {
    local app_name="$1"
    local backup_dir="$BACKUP_DIR/$app_name"
    
    if [[ -d "$backup_dir" ]]; then
        # Hitung jumlah backup
        local backup_count=$(ls -1 "$backup_dir" | wc -l)
        
        if [[ $backup_count -gt $MAX_BACKUPS ]]; then
            log_info "Cleaning up old backups for $app_name (keeping last $MAX_BACKUPS)"
            # Hapus backup terlama
            ls -1t "$backup_dir" | tail -n +$((MAX_BACKUPS + 1)) | while read -r old_backup; do
                rm -rf "$backup_dir/$old_backup"
                log_info "Removed old backup: $old_backup"
            done
        fi
    fi
}

check_laravel_app() {
    local app_path="$1"
    
    # Cek apakah ini benar-benar aplikasi Laravel
    if [[ ! -f "$app_path/artisan" ]]; then
        return 1
    fi
    
    if [[ ! -f "$app_path/composer.json" ]]; then
        log_warning "No composer.json found in $app_path"
        return 2
    fi
    
    # Cek versi Laravel dari composer.json
    if [[ -f "$app_path/composer.json" ]]; then
        local laravel_version=$(grep -o '"laravel/framework":[[:space:]]*"[^"]*' "$app_path/composer.json" | cut -d'"' -f4)
        if [[ -n "$laravel_version" ]]; then
            log_info "Detected Laravel $laravel_version"
        fi
    fi
    
    return 0
}

setup_ssl() {
    local domain="$1"
    local app_path="$2"
    
    log_info "Setting up SSL for $domain"
    
    # Cek apakah certbot sudah terinstall
    if ! check_cmd certbot; then
        log_info "Installing certbot..."
        apt install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
    fi
    
    # Coba dapatkan sertifikat SSL
    if certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@$domain >> "$LOG_FILE" 2>&1; then
        log_success "SSL certificate obtained for $domain"
        
        # Update nginx config untuk HTTPS
        local vhost_file="/etc/nginx/sites-available/$domain.conf"
        if [[ -f "$vhost_file" ]]; then
            # Otomatis redirect HTTP ke HTTPS
            sed -i 's/listen 80;/listen 80;\n    listen 443 ssl http2;/' "$vhost_file"
            log_info "Updated nginx config for HTTPS"
        fi
    else
        log_warning "Failed to obtain SSL certificate for $domain"
    fi
}

check_requirements() {
    log_info "Checking system requirements..."
    
    # Cek RAM
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 1024 ]]; then
        log_warning "Low RAM detected: ${total_ram}MB (recommended: 1024MB+)"
    fi
    
    # Cek disk space
    local disk_free=$(df -h / | awk 'NR==2 {print $4}')
    log_info "Disk free space: $disk_free"
    
    # Cek OS version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "OS: $NAME $VERSION"
    fi
}

setup_firewall() {
    log_info "Configuring firewall..."
    
    if check_cmd ufw; then
        ufw allow ssh >> "$LOG_FILE" 2>&1
        ufw allow 'Nginx Full' >> "$LOG_FILE" 2>&1
        ufw --force enable >> "$LOG_FILE" 2>&1
        log_success "Firewall configured"
    else
        log_warning "UFW not found, skipping firewall setup"
    fi
}

install_composer() {
    if ! check_cmd composer; then
        log_info "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php >> "$LOG_FILE" 2>&1
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
        log_success "Composer installed"
    fi
}

# ----------------------------
# ⚡ Ensure curl exists
# ----------------------------
if ! check_cmd curl; then
    log_info "curl not found. Installing curl..."
    apt update -y >> "$LOG_FILE" 2>&1
    apt install -y curl >> "$LOG_FILE" 2>&1
    log_success "curl installed"
fi

# ----------------------------
# 🔄 Auto-update Script (Safe)
# ----------------------------
log_info "Checking for script updates..."
TMP_SCRIPT=$(mktemp)
if curl -fsSL "$SCRIPT_REPO" -o "$TMP_SCRIPT"; then
    CURRENT_HASH=$(sha256sum "$0" | awk '{print $1}')
    NEW_HASH=$(sha256sum "$TMP_SCRIPT" | awk '{print $1}')
    
    if [[ "$CURRENT_HASH" != "$NEW_HASH" ]]; then
        log_info "New version available. Updating..."
        chmod +x "$TMP_SCRIPT"
        mv "$TMP_SCRIPT" "$0"
        log_success "Script updated successfully. Please run again."
        exit 0
    else
        log_info "Script is up to date"
        rm -f "$TMP_SCRIPT"
    fi
else
    log_warning "Cannot check for updates. Continuing with current version."
fi

# ----------------------------
# 🌐 Ensure directories exist
# ----------------------------
mkdir -p "$WWW_DIR" "$BACKUP_DIR"
chmod 755 "$BACKUP_DIR"

# ----------------------------
# 🛡️ Security Check
# ----------------------------
check_requirements

# ----------------------------
# 1️⃣ Install Dependencies
# ----------------------------
log_info "Installing dependencies..."
apt update -y >> "$LOG_FILE" 2>&1

# Install PHP versi yang didukung
apt install -y nginx mariadb-server unzip git curl >> "$LOG_FILE" 2>&1

# Install multiple PHP versions
for version in "${PHP_VERSIONS[@]}"; do
    if ! dpkg -l | grep -q "php$version"; then
        log_info "Installing PHP $version..."
        apt install -y "php$version" "php$version-fpm" "php$version-mysql" \
            "php$version-curl" "php$version-gd" "php$version-mbstring" \
            "php$version-xml" "php$version-zip" "php$version-bcmath" >> "$LOG_FILE" 2>&1
    fi
done

install_composer

# ----------------------------
# 🔧 Setup PHP Pool Configuration
# ----------------------------
log_info "Configuring PHP-FPM pools..."
for version in "${PHP_VERSIONS[@]}"; do
    if [[ -f "/etc/php/$version/fpm/pool.d/www.conf" ]]; then
        # Optimize PHP-FPM settings
        sed -i 's/^pm = .*/pm = dynamic/' "/etc/php/$version/fpm/pool.d/www.conf"
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "/etc/php/$version/fpm/pool.d/www.conf"
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "/etc/php/$version/fpm/pool.d/www.conf"
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "/etc/php/$version/fpm/pool.d/www.conf"
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "/etc/php/$version/fpm/pool.d/www.conf"
    fi
done

# ----------------------------
# 3️⃣ Scan /var/www for Laravel apps
# ----------------------------
log_info "Scanning $WWW_DIR for Laravel applications..."
APPS=()
for dir in "$WWW_DIR"/*; do
    if [[ -d "$dir" ]]; then
        if check_laravel_app "$dir"; then
            APPS+=("$(basename "$dir")")
        fi
    fi
done

APP_COUNT=${#APPS[@]}
if [[ $APP_COUNT -eq 0 ]]; then
    log_error "No Laravel applications found in $WWW_DIR"
    exit 1
fi

log_success "Found $APP_COUNT Laravel apps: ${APPS[*]}"

# ----------------------------
# 4️⃣ Deploy Each App
# ----------------------------
for APP in "${APPS[@]}"; do
    APP_PATH="$WWW_DIR/$APP"
    log_info "🚀 Deploying $APP"
    
    # Validasi aplikasi Laravel
    if ! check_laravel_app "$APP_PATH"; then
        log_warning "Skipping $APP - Not a valid Laravel application"
        continue
    fi
    
    # PHP version selection
    PHP_VERSION="8.1"
    if [[ $SILENT_MODE -eq 0 ]]; then
        while true; do
            PHP_VERSION=$(prompt "Enter PHP version for $APP [7.4|8.0|8.1|8.2|8.3] (default: 8.1): " "8.1")
            if validate_php_version "$PHP_VERSION"; then
                break
            else
                echo "Invalid PHP version. Please choose from: ${PHP_VERSIONS[*]}"
            fi
        done
    fi
    
    # Backup dengan timestamp
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/$APP/$BACKUP_TIMESTAMP"
    mkdir -p "$BACKUP_PATH"
    
    # Backup database jika ada .env
    if [[ -f "$APP_PATH/.env" ]]; then
        # Extract database info from .env
        DB_NAME=$(grep -E '^DB_DATABASE=' "$APP_PATH/.env" | cut -d'=' -f2)
        if [[ -n "$DB_NAME" ]]; then
            mysqldump "$DB_NAME" > "$BACKUP_PATH/database.sql" 2>/dev/null || true
        fi
    fi
    
    # Backup files (exclude node_modules, vendor, storage)
    rsync -a --exclude={'node_modules','vendor','storage/logs','storage/framework/cache'} \
        "$APP_PATH/" "$BACKUP_PATH/files/"
    
    # Cleanup old backups
    cleanup_old_backups "$APP"
    
    log_success "Backup created: $BACKUP_PATH"
    
    # Database setup
    DB_NAME=$(echo "$APP" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')_db
    DB_USER=$(echo "$APP" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')_user
    DB_PASS=$(openssl rand -base64 32 | tr -cd 'a-zA-Z0-9' | head -c 24)
    
    # Create database
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$ERROR_LOG_FILE"
    
    # Create user dengan password yang aman
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$ERROR_LOG_FILE"
    mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';" 2>> "$ERROR_LOG_FILE"
    mysql -e "FLUSH PRIVILEGES;" 2>> "$ERROR_LOG_FILE"
    
    # Update .env file
    if [[ -f "$APP_PATH/.env.example" && ! -f "$APP_PATH/.env" ]]; then
        cp "$APP_PATH/.env.example" "$APP_PATH/.env"
    fi
    
    if [[ -f "$APP_PATH/.env" ]]; then
        # Backup original .env
        cp "$APP_PATH/.env" "$APP_PATH/.env.backup-$BACKUP_TIMESTAMP"
        
        # Update database configuration
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$APP_PATH/.env"
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" "$APP_PATH/.env"
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD='$DB_PASS'/" "$APP_PATH/.env"
        sed -i "s/^APP_URL=.*/APP_URL=http:\/\/$DOMAIN/" "$APP_PATH/.env"
        
        # Set APP_DEBUG to false for production
        sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/" "$APP_PATH/.env"
        
        # Generate application key if not exists
        if ! grep -q "^APP_KEY=base64:" "$APP_PATH/.env"; then
            cd "$APP_PATH"
            php artisan key:generate --force >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # Save database credentials to secure file
    DB_INFO_FILE="$BACKUP_DIR/$APP/db_credentials.txt"
    echo "=== Database Credentials for $APP ===" > "$DB_INFO_FILE"
    echo "Database: $DB_NAME" >> "$DB_INFO_FILE"
    echo "Username: $DB_USER" >> "$DB_INFO_FILE"
    echo "Password: $DB_PASS" >> "$DB_INFO_FILE"
    echo "Backup: $BACKUP_PATH" >> "$DB_INFO_FILE"
    echo "=====================================" >> "$DB_INFO_FILE"
    chmod 600 "$DB_INFO_FILE"
    
    echo -e "\n💾 DB INFO for $APP"
    echo "Database : $DB_NAME"
    echo "User     : $DB_USER"
    echo "Password : $DB_PASS"
    echo "Backup   : $BACKUP_PATH"
    echo "---------------------------"
    
    # Run Laravel optimizations
    cd "$APP_PATH"
    
    # Install composer dependencies
    if [[ -f "composer.json" ]]; then
        log_info "Installing Composer dependencies..."
        composer install --no-dev --optimize-autoloader >> "$LOG_FILE" 2>&1
    fi
    
    # Run migrations
    log_info "Running database migrations..."
    php artisan migrate --force >> "$LOG_FILE" 2>&1
    
    # Clear and cache
    php artisan config:cache >> "$LOG_FILE" 2>&1
    php artisan route:cache >> "$LOG_FILE" 2>&1
    php artisan view:cache >> "$LOG_FILE" 2>&1
    
    # Permissions dengan lebih spesifik
    chown -R www-data:www-data "$APP_PATH"
    find "$APP_PATH" -type d -exec chmod 755 {} \;
    find "$APP_PATH" -type f -exec chmod 644 {} \;
    
    # Special permissions for storage and cache
    chmod -R 775 "$APP_PATH/storage"
    chmod -R 775 "$APP_PATH/bootstrap/cache"
    
    # Set proper ownership for log files
    touch "$APP_PATH/storage/logs/laravel.log"
    chown www-data:www-data "$APP_PATH/storage/logs/laravel.log"
    chmod 664 "$APP_PATH/storage/logs/laravel.log"
    
    # Nginx configuration
    DOMAIN="$APP.local"
    if [[ $SILENT_MODE -eq 0 ]]; then
        while true; do
            DOMAIN=$(prompt "Enter domain for $APP [$APP.local]: " "$APP.local")
            if validate_domain "$DOMAIN"; then
                break
            else
                echo "Invalid domain format. Please enter a valid domain (example.com)"
            fi
        done
    fi
    
    VHOST_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
    
    # Security headers dan optimasi
    cat > "$VHOST_FILE" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    root $APP_PATH/public;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    index index.php index.html;
    
    charset utf-8;
    
    # Security: Hide PHP version
    fastcgi_hide_header X-Powered-By;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    
    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Deny access to sensitive files
    location ~* \.(env|log|sql|git|svn|htaccess)\$ {
        deny all;
    }
    
    client_max_body_size 100M;
    client_body_timeout 300s;
}
EOL
    
    # Enable site
    ln -sf "$VHOST_FILE" "/etc/nginx/sites-enabled/"
    
    # Test nginx configuration
    if nginx -t >> "$LOG_FILE" 2>&1; then
        log_success "Nginx configuration test passed for $DOMAIN"
    else
        log_error "Nginx configuration test failed for $DOMAIN"
        # Disable broken config
        rm -f "/etc/nginx/sites-enabled/$DOMAIN.conf"
    fi
    
    # Setup SSL jika diinginkan
    if [[ $SILENT_MODE -eq 0 ]]; then
        read -p "Setup SSL for $DOMAIN? (y/n) [n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_ssl "$DOMAIN" "$APP_PATH"
        fi
    fi
    
    log_success "Completed deployment for $APP"
done

# ----------------------------
# 5️⃣ Restart Services
# ----------------------------
log_info "Restarting services..."
systemctl restart nginx

# Restart semua PHP-FPM versi yang diinstall
for version in "${PHP_VERSIONS[@]}"; do
    if systemctl list-unit-files | grep -q "php$version-fpm"; then
        systemctl restart "php$version-fpm"
    fi
done

# Setup firewall
setup_firewall

# ----------------------------
# 📊 Generate Deployment Report
# ----------------------------
REPORT_FILE="/var/log/laravel_deployment_report_$(date +%Y%m%d).txt"
echo "=== Laravel Deployment Report ===" > "$REPORT_FILE"
echo "Date: $(date)" >> "$REPORT_FILE"
echo "Total Apps: $APP_COUNT" >> "$REPORT_FILE"
echo "Apps Deployed: ${APPS[*]}" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

for APP in "${APPS[@]}"; do
    echo "--- $APP ---" >> "$REPORT_FILE"
    DB_INFO_FILE="$BACKUP_DIR/$APP/db_credentials.txt"
    if [[ -f "$DB_INFO_FILE" ]]; then
        cat "$DB_INFO_FILE" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
done

echo "=====================================" >> "$REPORT_FILE"
chmod 600 "$REPORT_FILE"

# ----------------------------
# ✅ Finish
# ----------------------------
log_success "Laravel Multi-Domain Deploy Completed!"
log_info "Detailed report: $REPORT_FILE"
log_info "Error log: $ERROR_LOG_FILE"

if [[ $SILENT_MODE -eq 0 ]]; then
    echo ""
    echo "🎉 All deployments completed successfully!"
    echo "📋 Summary Report: $REPORT_FILE"
    echo "📝 Detailed Log: $LOG_FILE"
    echo "❌ Error Log: $ERROR_LOG_FILE"
    echo ""
    echo "Next steps:"
    echo "1. Update DNS records for your domains"
    echo "2. Configure SSL certificates if needed"
    echo "3. Set up monitoring and backups"
    echo ""
fi