#!/bin/bash
# ==============================================
# 🚀 Laravel Deploy Pro - Complete Solution
# Version       : 5.0-production
# Author        : Nasrul
# GitHub        : https://github.com/nasrulll/laravel-deploy
# Description   : Complete Laravel deployment with provisioning,
#                 multi-app support, SSL, backup, and database management
# ==============================================

set -euo pipefail
shopt -s nullglob

# ----------------------------
# 🌟 CONFIGURATION
# ----------------------------
readonly CONFIG_FILE="/etc/laravel-deploy/config.conf"
readonly LOG_FILE="/var/log/laravel-deploy/deploy.log"
readonly ERROR_LOG="/var/log/laravel-deploy/errors.log"
readonly BACKUP_ROOT="/var/backups/laravel"
readonly DEPLOYMENTS_ROOT="/var/deployments"
readonly SSL_DIR="/etc/ssl/laravel"

# Default configuration
declare -A CONFIG=(
    [WWW_DIR]="/var/www"
    [PHP_VERSION]="8.1"
    [MYSQL_ROOT_PASS]=""
    [REDIS_ENABLED]="1"
    [SSL_ENABLED]="1"
    [AUTO_BACKUP]="1"
    [BACKUP_RETENTION]="30"
    [MAX_BACKUPS]="5"
    [ENABLE_MONITORING]="1"
    [DEPLOYMENT_TIMEOUT]="300"
    [ZERO_DOWNTIME]="1"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------
# 📊 LOGGING & UTILITIES
# ----------------------------
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")     echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS")  echo -e "${GREEN}[✓]${NC} $message" ;;
        "WARNING")  echo -e "${YELLOW}[!]${NC} $message" ;;
        "ERROR")    echo -e "${RED}[✗]${NC} $message" >&2 ;;
    esac
    
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

validate_input() {
    local input="$1"
    local pattern="$2"
    local description="$3"
    
    if [[ ! $input =~ $pattern ]]; then
        log_error "Invalid input for $description: $input"
        return 1
    fi
    return 0
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

# ----------------------------
# 1️⃣ SERVER PROVISIONING AUTOMATION
# ----------------------------
provision_server() {
    log_info "🚀 Starting server provisioning..."
    
    local os=$(detect_os)
    
    case $os in
        ubuntu|debian)
            provision_debian_based
            ;;
        *)
            log_error "Unsupported OS: $os. Currently only Ubuntu/Debian are supported."
            exit 1
            ;;
    esac
    
    log_success "✅ Server provisioning completed!"
}

provision_debian_based() {
    log_info "Detected Debian-based system. Starting provisioning..."
    
    # Update system
    log_info "Updating system packages..."
    apt update -y && apt upgrade -y
    
    # Install essential packages
    log_info "Installing essential packages..."
    apt install -y curl wget git unzip build-essential software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release
    
    # Install Nginx
    log_info "Installing Nginx..."
    apt install -y nginx
    
    # Install MySQL/MariaDB
    log_info "Installing MariaDB..."
    apt install -y mariadb-server mariadb-client
    
    # Secure MariaDB installation
    secure_mariadb
    
    # Install PHP and extensions
    install_php
    
    # Install Composer
    log_info "Installing Composer..."
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    php -r "unlink('composer-setup.php');"
    
    # Install Redis
    if [[ "${CONFIG[REDIS_ENABLED]}" == "1" ]]; then
        log_info "Installing Redis..."
        apt install -y redis-server
        systemctl enable redis-server
    fi
    
    # Install Node.js (for frontend builds)
    log_info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    
    # Install PM2 for process management
    npm install -g pm2
    
    # Configure PHP-FPM
    configure_php_fpm
    
    # Configure Nginx
    configure_nginx
    
    # Enable services
    log_info "Enabling services..."
    systemctl enable nginx
    systemctl enable php${CONFIG[PHP_VERSION]}-fpm
    systemctl enable mariadb
    
    # Start services
    log_info "Starting services..."
    systemctl restart nginx
    systemctl restart php${CONFIG[PHP_VERSION]}-fpm
    systemctl restart mariadb
    
    # Configure firewall
    configure_firewall
    
    # Create directories
    log_info "Creating required directories..."
    mkdir -p "${CONFIG[WWW_DIR]}" "$BACKUP_ROOT" "$DEPLOYMENTS_ROOT" "$SSL_DIR" \
        /var/log/laravel-deploy /etc/laravel-deploy
    
    # Set permissions
    chmod 755 "${CONFIG[WWW_DIR]}"
    chmod 750 "$BACKUP_ROOT"
    
    # Save configuration
    save_configuration
}

secure_mariadb() {
    log_info "Securing MariaDB..."
    # Check if MySQL root password is set in config
    local root_pass="${CONFIG[MYSQL_ROOT_PASS]}"
    if [[ -z "$root_pass" ]]; then
        root_pass=$(openssl rand -base64 32)
        CONFIG[MYSQL_ROOT_PASS]="$root_pass"
    fi
    
    # Run secure installation non-interactively
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';"
    mysql -u root -p"$root_pass" -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p"$root_pass" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -p"$root_pass" -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p"$root_pass" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -p"$root_pass" -e "FLUSH PRIVILEGES;"
}

install_php() {
    log_info "Installing PHP ${CONFIG[PHP_VERSION]} and extensions..."
    add-apt-repository -y ppa:ondrej/php
    apt update
    
    apt install -y php${CONFIG[PHP_VERSION]} php${CONFIG[PHP_VERSION]}-fpm \
        php${CONFIG[PHP_VERSION]}-mysql php${CONFIG[PHP_VERSION]}-curl \
        php${CONFIG[PHP_VERSION]}-gd php${CONFIG[PHP_VERSION]}-mbstring \
        php${CONFIG[PHP_VERSION]}-xml php${CONFIG[PHP_VERSION]}-zip \
        php${CONFIG[PHP_VERSION]}-bcmath php${CONFIG[PHP_VERSION]}-intl \
        php${CONFIG[PHP_VERSION]}-redis php${CONFIG[PHP_VERSION]}-memcached \
        php${CONFIG[PHP_VERSION]}-opcache php${CONFIG[PHP_VERSION]}-imagick
}

configure_php_fpm() {
    log_info "Configuring PHP-FPM..."
    cat > /etc/php/${CONFIG[PHP_VERSION]}/fpm/pool.d/laravel.conf << EOF
[laravel]
user = www-data
group = www-data
listen = /run/php/php${CONFIG[PHP_VERSION]}-fpm-laravel.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
pm.max_requests = 500
slowlog = /var/log/php-fpm/laravel-slow.log
request_slowlog_timeout = 5s
EOF
}

configure_nginx() {
    log_info "Configuring Nginx..."
    cat > /etc/nginx/nginx.conf << 'NGINX'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
    use epoll;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Logging Settings
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        image/svg+xml;
    
    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX
}

configure_firewall() {
    log_info "Configuring firewall..."
    if command -v ufw &> /dev/null; then
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw --force enable
    fi
}

# ----------------------------
# 2️⃣ MULTI-APPLICATION SUPPORT
# ----------------------------
scan_applications() {
    log_info "🔍 Scanning for Laravel applications..."
    
    local apps=()
    for dir in "${CONFIG[WWW_DIR]}"/*; do
        if [[ -d "$dir" && -f "$dir/artisan" && -f "$dir/composer.json" ]]; then
            local app_name=$(basename "$dir")
            
            # Verify it's a Laravel app
            if grep -q '"laravel/framework"' "$dir/composer.json"; then
                apps+=("$app_name")
                
                # Get app info
                local laravel_version=$(grep -o '"laravel/framework":"[^"]*' "$dir/composer.json" | cut -d'"' -f4)
                local php_version=$(detect_php_version "$dir")
                
                log_info "Found: $app_name (Laravel $laravel_version, PHP $php_version)"
                
                # Create app configuration if not exists
                create_app_config "$app_name" "$dir" "$php_version"
            fi
        fi
    done
    
    if [[ ${#apps[@]} -eq 0 ]]; then
        log_warning "No Laravel applications found"
    else
        log_success "Found ${#apps[@]} application(s)"
    fi
    
    echo "${apps[@]}"
}

detect_php_version() {
    local app_path="$1"
    local default_version="${CONFIG[PHP_VERSION]}"
    
    # Check .env file
    if [[ -f "$app_path/.env" ]]; then
        local env_version=$(grep -E '^PHP_VERSION=' "$app_path/.env" | cut -d'=' -f2)
        [[ -n "$env_version" ]] && echo "$env_version" && return
    fi
    
    # Check composer.json
    if [[ -f "$app_path/composer.json" ]]; then
        local composer_php=$(grep -o '"php":"[^"]*' "$app_path/composer.json" | cut -d'"' -f4)
        
        # Extract major.minor version
        if [[ "$composer_php" =~ ([0-9]+\.[0-9]+) ]]; then
            local version="${BASH_REMATCH[1]}"
            
            # Map to available versions
            case "$version" in
                7.4|8.0|8.1|8.2|8.3)
                    echo "$version"
                    return
                    ;;
            esac
        fi
    fi
    
    echo "$default_version"
}

create_app_config() {
    local app_name="$1"
    local app_path="$2"
    local php_version="$3"
    local config_file="/etc/laravel-deploy/apps/$app_name.conf"
    
    mkdir -p "/etc/laravel-deploy/apps"
    
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" << EOF
# Configuration for: $app_name
APP_NAME="$app_name"
APP_PATH="$app_path"
PHP_VERSION="$php_version"
DOMAIN="${app_name}.localhost"
ENVIRONMENT="production"
DB_NAME="${app_name}_db"
DB_USER="${app_name}_user"
DB_PASSWORD=""
ENABLE_SSL=0
SSL_EMAIL=""
ENABLE_QUEUE=0
QUEUE_WORKERS=2
ENABLE_SCHEDULER=1
BACKUP_SCHEDULE="0 2 * * *"
DEPLOYMENT_METHOD="git"  # git or rsync
REPO_URL=""
BRANCH="main"
DEPLOYMENT_HOOKS_ENABLED=1
EOF
        log_info "Created configuration for $app_name"
    fi
}

deploy_multiple_apps() {
    local apps=($(scan_applications))
    
    if [[ ${#apps[@]} -eq 0 ]]; then
        log_error "No applications to deploy"
        return 1
    fi
    
    log_info "🚀 Deploying ${#apps[@]} application(s)..."
    
    local success_count=0
    local failed_count=0
    local failed_apps=()
    
    for app in "${apps[@]}"; do
        echo ""
        log_info "========================================"
        log_info "Processing: $app"
        log_info "========================================"
        
        if deploy_single_app "$app"; then
            ((success_count++))
            log_success "✅ $app deployed successfully"
        else
            ((failed_count++))
            failed_apps+=("$app")
            log_error "❌ $app deployment failed"
        fi
        
        echo ""
    done
    
    # Generate deployment report
    generate_deployment_report "${apps[@]}" "$success_count" "$failed_count" "${failed_apps[@]}"
    
    return $((failed_count > 0 ? 1 : 0))
}

# ----------------------------
# 3️⃣ BASIC DEPLOYMENT PIPELINE
# ----------------------------
deploy_single_app() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    local config_file="/etc/laravel-deploy/apps/$app_name.conf"
    
    # Load app configuration
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration not found for $app_name"
        return 1
    fi
    
    source "$config_file"
    
    log_info "Starting deployment pipeline for $app_name"
    
    # Pipeline stages
    local stages=(
        "pre_deployment_hooks"
        "create_backup"
        "update_code"
        "install_dependencies"
        "setup_database"
        "run_migrations"
        "build_assets"
        "optimize_application"
        "configure_webserver"
        "setup_ssl"
        "configure_queue"
        "post_deployment_hooks"
        "verify_deployment"
    )
    
    local rollback_needed=0
    
    for stage in "${stages[@]}"; do
        log_info "▶️  Stage: ${stage//_/ }"
        
        if ! $stage "$app_name"; then
            log_error "Stage failed: $stage"
            
            if [[ $rollback_needed -eq 1 ]]; then
                log_warning "Rolling back deployment..."
                rollback_deployment "$app_name"
            fi
            
            return 1
        fi
        
        # After backup stage, mark that rollback is possible
        if [[ "$stage" == "create_backup" ]]; then
            rollback_needed=1
        fi
    done
    
    log_success "✅ Deployment pipeline completed for $app_name"
    return 0
}

pre_deployment_hooks() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    if [[ "$DEPLOYMENT_HOOKS_ENABLED" != "1" ]]; then
        return 0
    fi
    
    # Run pre-deploy.sh if exists
    if [[ -f "$app_path/pre-deploy.sh" ]]; then
        log_info "Running pre-deployment hooks..."
        cd "$app_path"
        chmod +x pre-deploy.sh
        ./pre-deploy.sh "$app_name"
    fi
    
    # Enable maintenance mode
    if [[ -f "$app_path/artisan" ]]; then
        cd "$app_path"
        php artisan down --retry=60 || true
    fi
    
    return 0
}

update_code() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    case "$DEPLOYMENT_METHOD" in
        "git")
            update_code_git "$app_path" "$REPO_URL" "$BRANCH"
            ;;
        "rsync")
            update_code_rsync "$app_path" "$REPO_URL"
            ;;
        *)
            log_error "Unknown deployment method: $DEPLOYMENT_METHOD"
            return 1
            ;;
    esac
}

update_code_git() {
    local app_path="$1"
    local repo_url="$2"
    local branch="$3"
    
    cd "$app_path"
    
    # Initialize git if not already
    if [[ ! -d ".git" ]]; then
        if [[ -z "$repo_url" ]]; then
            log_error "Repo URL not configured"
            return 1
        fi
        
        git init
        git remote add origin "$repo_url"
        git fetch origin "$branch"
        git checkout -b "$branch" --track "origin/$branch"
    else
        # Pull latest changes
        git fetch origin
        git checkout "$branch"
        git pull origin "$branch"
    fi
    
    # Get commit info
    local commit_hash=$(git rev-parse --short HEAD)
    local commit_msg=$(git log -1 --pretty=%B)
    
    log_info "Deployed commit: $commit_hash - $commit_msg"
    
    return 0
}

update_code_rsync() {
    local app_path="$1"
    local source="$2"
    
    log_info "Syncing code from $source to $app_path"
    rsync -avz --delete --exclude='.env' --exclude='storage' "$source/" "$app_path/"
    return $?
}

install_dependencies() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    cd "$app_path"
    
    # Install PHP dependencies
    log_info "Installing Composer dependencies..."
    if [[ -f "composer.json" ]]; then
        composer install --no-dev --optimize-autoloader --no-interaction
        
        # Check for specific Laravel packages
        if grep -q '"laravel/horizon"' composer.json; then
            log_info "Installing Horizon..."
            php artisan horizon:publish
        fi
    fi
    
    # Install Node dependencies if package.json exists
    if [[ -f "package.json" ]]; then
        log_info "Installing Node dependencies..."
        npm ci --production
        
        # Build assets
        if [[ -f "webpack.mix.js" || -f "vite.config.js" ]]; then
            log_info "Building assets..."
            npm run production
        fi
    fi
    
    return 0
}

build_assets() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    cd "$app_path"
    
    # Build frontend assets
    if [[ -f "package.json" ]]; then
        log_info "Building frontend assets..."
        
        if [[ -f "vite.config.js" ]]; then
            npm run build
        elif [[ -f "webpack.mix.js" ]]; then
            npm run production
        fi
    fi
    
    return 0
}

optimize_application() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    cd "$app_path"
    
    log_info "Optimizing Laravel application..."
    
    # Clear caches
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    php artisan cache:clear
    
    # Optimize
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Generate key if not exists
    if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
        php artisan key:generate --force
    fi
    
    # Link storage
    php artisan storage:link || true
    
    return 0
}

post_deployment_hooks() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Run post-deploy.sh if exists
    if [[ -f "$app_path/post-deploy.sh" ]]; then
        log_info "Running post-deployment hooks..."
        cd "$app_path"
        chmod +x post-deploy.sh
        ./post-deploy.sh "$app_name"
    fi
    
    # Disable maintenance mode
    if [[ -f "$app_path/artisan" ]]; then
        cd "$app_path"
        php artisan up
    fi
    
    return 0
}

verify_deployment() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    log_info "Verifying deployment..."
    
    # Check if artisan commands work
    cd "$app_path"
    if ! php artisan --version >/dev/null 2>&1; then
        log_error "Artisan command failed"
        return 1
    fi
    
    # Check if routes are cached
    if [[ ! -f "bootstrap/cache/routes.php" ]]; then
        log_warning "Routes not cached (this is normal for first deployment)"
    fi
    
    # Test database connection
    if php artisan tinker --execute="echo DB::connection()->getPdo() ? 'OK' : 'FAIL';" 2>/dev/null | grep -q "OK"; then
        log_info "Database connection: OK"
    else
        log_warning "Database connection test failed"
    fi
    
    # Health check endpoint
    if curl -s -f "http://localhost/health" >/dev/null 2>&1; then
        log_info "Health check endpoint: OK"
    fi
    
    log_success "Deployment verification passed"
    return 0
}

rollback_deployment() {
    local app_name="$1"
    local backup_dir="$BACKUP_ROOT/$app_name"
    
    log_info "Rolling back $app_name..."
    
    # Find latest backup
    local latest_backup=$(ls -1t "$backup_dir" 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backups found for rollback"
        return 1
    fi
    
    log_info "Restoring from backup: $latest_backup"
    
    # Restore files
    local backup_path="$backup_dir/$latest_backup"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Remove current files
    rm -rf "$app_path"/*
    
    # Restore from backup
    tar -xzf "$backup_path/files.tar.gz" -C /
    
    # Restore database if exists
    if [[ -f "$backup_path/database.sql.gz" ]]; then
        log_info "Restoring database..."
        source "/etc/laravel-deploy/apps/$app_name.conf"
        
        gunzip -c "$backup_path/database.sql.gz" | mysql -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME"
    fi
    
    log_success "Rollback completed"
    return 0
}

# ----------------------------
# 4️⃣ DATABASE MANAGEMENT
# ----------------------------
setup_database() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Load app config
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || true
    
    # Generate password if not set
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(generate_password)
        
        # Update config
        sed -i "s/^DB_PASSWORD=\"\"/DB_PASSWORD=\"$DB_PASSWORD\"/" "/etc/laravel-deploy/apps/$app_name.conf"
    fi
    
    log_info "Setting up database: $DB_NAME"
    
    # Create database
    mysql -u root -p"${CONFIG[MYSQL_ROOT_PASS]}" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Create user with privileges
    mysql -u root -p"${CONFIG[MYSQL_ROOT_PASS]}" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -p"${CONFIG[MYSQL_ROOT_PASS]}" -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    mysql -u root -p"${CONFIG[MYSQL_ROOT_PASS]}" -e "FLUSH PRIVILEGES;"
    
    # Update .env file
    if [[ -f "$app_path/.env" ]]; then
        # Backup original .env
        cp "$app_path/.env" "$app_path/.env.backup_$(date +%Y%m%d_%H%M%S)"
        
        # Update database configuration
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$app_path/.env"
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" "$app_path/.env"
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" "$app_path/.env"
    else
        # Create .env from example
        if [[ -f "$app_path/.env.example" ]]; then
            cp "$app_path/.env.example" "$app_path/.env"
            sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$app_path/.env"
            sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" "$app_path/.env"
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" "$app_path/.env"
        fi
    fi
    
    log_success "Database setup completed"
    return 0
}

run_migrations() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    cd "$app_path"
    
    log_info "Running database migrations..."
    
    if php artisan migrate --force >/dev/null 2>&1; then
        log_info "Migrations completed"
        
        # Run seeders if --seed flag provided
        if [[ "$2" == "--seed" ]]; then
            log_info "Running database seeders..."
            php artisan db:seed --force
        fi
        
        return 0
    else
        log_error "Migrations failed"
        return 1
    fi
}

database_backup() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Load database credentials
    if [[ -f "$app_path/.env" ]]; then
        local db_name=$(grep -E '^DB_DATABASE=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
        local db_user=$(grep -E '^DB_USERNAME=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
        local db_pass=$(grep -E '^DB_PASSWORD=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
    else
        source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 1
        local db_name="$DB_NAME"
        local db_user="$DB_USER"
        local db_pass="$DB_PASSWORD"
    fi
    
    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        log_error "Database credentials not found for $app_name"
        return 1
    fi
    
    local backup_dir="$BACKUP_ROOT/$app_name/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log_info "Backing up database: $db_name"
    
    # Backup database
    if mysqldump --single-transaction --quick -u"$db_user" -p"$db_pass" "$db_name" | gzip > "$backup_dir/database.sql.gz"; then
        log_success "Database backup created: $backup_dir/database.sql.gz"
        
        # Create backup manifest
        cat > "$backup_dir/manifest.json" << EOF
{
    "app": "$app_name",
    "database": "$db_name",
    "timestamp": "$(date -Iseconds)",
    "type": "database",
    "size": "$(stat -c%s "$backup_dir/database.sql.gz")"
}
EOF
        
        return 0
    else
        log_error "Database backup failed"
        rm -rf "$backup_dir"
        return 1
    fi
}

database_optimize() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Load database credentials
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 1
    
    log_info "Optimizing database: $DB_NAME"
    
    # Run optimization queries
    mysql -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << EOF
-- Optimize tables
OPTIMIZE TABLE migrations, failed_jobs, jobs, cache, cache_locks, sessions;
-- Analyze tables
ANALYZE TABLE users, password_resets, personal_access_tokens;
-- Clear old data
DELETE FROM failed_jobs WHERE failed_at < DATE_SUB(NOW(), INTERVAL 30 DAY);
DELETE FROM jobs WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY);
EOF
    
    log_success "Database optimization completed"
    return 0
}

# ----------------------------
# 5️⃣ SSL CERTIFICATE MANAGEMENT
# ----------------------------
setup_ssl() {
    local app_name="$1"
    
    # Load app configuration
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 0
    
    if [[ "$ENABLE_SSL" != "1" ]]; then
        return 0
    fi
    
    if [[ -z "$DOMAIN" || "$DOMAIN" == "*.localhost" ]]; then
        log_warning "No valid domain configured for SSL"
        return 0
    fi
    
    if [[ -z "$SSL_EMAIL" ]]; then
        log_warning "SSL email not configured"
        return 0
    fi
    
    log_info "Setting up SSL for: $DOMAIN"
    
    # Install certbot if not exists
    if ! command -v certbot &> /dev/null; then
        log_info "Installing certbot..."
        apt install -y certbot python3-certbot-nginx
    fi
    
    # Check if certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        log_info "SSL certificate already exists, checking renewal..."
        
        # Check if renewal is needed
        if certbot certificates | grep -q "$DOMAIN" && \
           certbot certificates | grep -A5 "$DOMAIN" | grep -q "VALID: 30 days"; then
            log_info "Certificate is valid, skipping..."
            return 0
        fi
    fi
    
    # Obtain SSL certificate
    log_info "Obtaining SSL certificate from Let's Encrypt..."
    
    if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
        --non-interactive --agree-tos --email "$SSL_EMAIL" \
        --redirect --hsts --uir --staple-ocsp; then
        
        log_success "SSL certificate obtained for $DOMAIN"
        
        # Update Nginx configuration
        update_nginx_ssl_config "$app_name" "$DOMAIN"
        
        # Setup auto-renewal
        setup_ssl_auto_renewal "$DOMAIN"
        
        return 0
    else
        log_error "Failed to obtain SSL certificate"
        return 1
    fi
}

update_nginx_ssl_config() {
    local app_name="$1"
    local domain="$2"
    local nginx_conf="/etc/nginx/sites-available/$domain"
    
    if [[ ! -f "$nginx_conf" ]]; then
        return 1
    fi
    
    # Update configuration to include SSL
    cat > "$nginx_conf" << EOF
# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    # ACME challenge for certbot renewal
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain www.$domain;
    
    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # SSL configuration
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # HSTS (uncomment after testing)
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    root ${CONFIG[WWW_DIR]}/$app_name/public;
    index index.php index.html index.htm;
    
    # ... rest of your Nginx configuration ...
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm-laravel.sock;
    }
}
EOF
    
    # Test and reload Nginx
    nginx -t && systemctl reload nginx
}

setup_ssl_auto_renewal() {
    local domain="$1"
    
    # Create renewal check script
    cat > "/usr/local/bin/check-ssl-renewal.sh" << 'SCRIPT'
#!/bin/bash
DOMAIN="$1"

# Check if certificate expires in less than 30 days
if certbot certificates | grep -q "$DOMAIN" && \
   certbot certificates | grep -A5 "$DOMAIN" | grep -q "VALID: 30 days"; then
    echo "Certificate for $DOMAIN needs renewal"
    
    # Attempt renewal
    if certbot renew --cert-name "$DOMAIN" --quiet; then
        systemctl reload nginx
        echo "Certificate renewed successfully"
        
        # Send notification (optional)
        # curl -X POST https://api.telegram.org/botTOKEN/sendMessage \
        #     -d chat_id=CHAT_ID \
        #     -d text="SSL renewed for $DOMAIN"
    else
        echo "Certificate renewal failed"
        exit 1
    fi
fi
SCRIPT
    
    chmod +x "/usr/local/bin/check-ssl-renewal.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/check-ssl-renewal.sh $domain >> /var/log/ssl-renewal.log 2>&1") | crontab -
    
    log_info "SSL auto-renewal configured"
}

# ----------------------------
# 6️⃣ BACKUP SYSTEM
# ----------------------------
create_backup() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_ROOT/$app_name/$timestamp"
    
    if [[ "${CONFIG[AUTO_BACKUP]}" != "1" ]]; then
        return 0
    fi
    
    log_info "Creating backup for $app_name..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # 1. Backup database
    if ! database_backup "$app_name"; then
        log_warning "Database backup skipped"
    fi
    
    # 2. Backup files
    log_info "Backing up application files..."
    
    # Create exclude list
    local exclude_file="/tmp/backup-exclude-$app_name.txt"
    cat > "$exclude_file" << EXCLUDE
node_modules
vendor
storage/framework/cache
storage/logs
.git
*.log
*.sql
*.tar.gz
*.zip
.DS_Store
Thumbs.db
EXCLUDE
    
    # Create tar archive
    if tar -czf "$backup_dir/files.tar.gz" \
        -C "${CONFIG[WWW_DIR]}" \
        --exclude-from="$exclude_file" \
        "$app_name"; then
        
        log_success "Files backup created: $backup_dir/files.tar.gz"
    else
        log_error "Files backup failed"
        rm -rf "$backup_dir"
        return 1
    fi
    
    # 3. Backup .env file separately
    if [[ -f "$app_path/.env" ]]; then
        cp "$app_path/.env" "$backup_dir/"
    fi
    
    # 4. Create backup manifest
    cat > "$backup_dir/manifest.json" << EOF
{
    "app": "$app_name",
    "timestamp": "$(date -Iseconds)",
    "backup_id": "$timestamp",
    "files": {
        "count": "$(tar -tzf "$backup_dir/files.tar.gz" | wc -l)",
        "size": "$(stat -c%s "$backup_dir/files.tar.gz")"
    },
    "database": "$([[ -f "$backup_dir/database.sql.gz" ]] && echo "yes" || echo "no")"
}
EOF
    
    # 5. Encrypt backup (optional)
    if [[ -n "${CONFIG[BACKUP_ENCRYPTION_KEY]}" ]]; then
        encrypt_backup "$backup_dir" "${CONFIG[BACKUP_ENCRYPTION_KEY]}"
    fi
    
    # 6. Cleanup old backups
    cleanup_old_backups "$app_name"
    
    log_success "✅ Backup completed: $backup_dir"
    return 0
}

cleanup_old_backups() {
    local app_name="$1"
    local backup_dir="$BACKUP_ROOT/$app_name"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi
    
    local retention_days="${CONFIG[BACKUP_RETENTION]:-30}"
    local max_backups="${CONFIG[MAX_BACKUPS]:-5}"
    
    log_info "Cleaning up old backups (keeping last $max_backups, older than $retention_days days)..."
    
    # Remove backups older than retention days
    find "$backup_dir" -maxdepth 1 -type d -mtime +$retention_days -exec rm -rf {} \;
    
    # Keep only last N backups
    local backups=($(ls -1t "$backup_dir" 2>/dev/null))
    local backup_count=${#backups[@]}
    
    if [[ $backup_count -gt $max_backups ]]; then
        for ((i=max_backups; i<backup_count; i++)); do
            rm -rf "$backup_dir/${backups[$i]}"
        done
    fi
    
    log_info "Backup cleanup completed"
}

restore_backup() {
    local app_name="$1"
    local backup_id="$2"
    
    local backup_dir="$BACKUP_ROOT/$app_name"
    
    if [[ -z "$backup_id" ]]; then
        # List available backups
        log_info "Available backups for $app_name:"
        ls -1t "$backup_dir" 2>/dev/null | head -10
        return 1
    fi
    
    local backup_path="$backup_dir/$backup_id"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup not found: $backup_id"
        return 1
    fi
    
    log_info "Restoring backup: $backup_id"
    
    # 1. Stop services if needed
    systemctl stop nginx 2>/dev/null || true
    
    # 2. Restore files
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    log_info "Restoring application files..."
    rm -rf "$app_path"/*
    tar -xzf "$backup_path/files.tar.gz" -C /
    
    # 3. Restore database if exists
    if [[ -f "$backup_path/database.sql.gz" ]]; then
        log_info "Restoring database..."
        
        # Load database credentials
        if [[ -f "$app_path/.env" ]]; then
            local db_name=$(grep -E '^DB_DATABASE=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
            local db_user=$(grep -E '^DB_USERNAME=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
            local db_pass=$(grep -E '^DB_PASSWORD=' "$app_path/.env" | cut -d'=' -f2 | sed "s/['\"]//g")
            
            gunzip -c "$backup_path/database.sql.gz" | mysql -u"$db_user" -p"$db_pass" "$db_name"
        fi
    fi
    
    # 4. Restore .env if exists
    if [[ -f "$backup_path/.env" ]]; then
        cp "$backup_path/.env" "$app_path/.env"
    fi
    
    # 5. Restart services
    systemctl start nginx
    
    log_success "✅ Backup restored successfully"
    return 0
}

setup_auto_backups() {
    local app_name="$1"
    
    # Load app configuration
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 1
    
    local cron_schedule="${BACKUP_SCHEDULE:-"0 2 * * *"}"
    
    # Create backup script
    cat > "/usr/local/bin/backup-$app_name.sh" << SCRIPT
#!/bin/bash
# Auto backup script for $app_name

APP_NAME="$app_name"
LOG_FILE="/var/log/laravel-deploy/backup-\$APP_NAME.log"

echo "[$(date)] Starting backup for \$APP_NAME" >> "\$LOG_FILE"

/usr/local/bin/laravel-deploy backup --app="\$APP_NAME" >> "\$LOG_FILE" 2>&1

if [[ \$? -eq 0 ]]; then
    echo "[$(date)] Backup completed successfully" >> "\$LOG_FILE"
else
    echo "[$(date)] Backup failed" >> "\$LOG_FILE"
    # Send notification
    # curl -X POST https://api.telegram.org/botTOKEN/sendMessage \
    #     -d chat_id=CHAT_ID \
    #     -d text="Backup failed for \$APP_NAME"
fi
SCRIPT
    
    chmod +x "/usr/local/bin/backup-$app_name.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_schedule /usr/local/bin/backup-$app_name.sh") | crontab -
    
    log_success "Auto-backup configured for $app_name (schedule: $cron_schedule)"
}

# ----------------------------
# 🔧 HELPER FUNCTIONS
# ----------------------------
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c 24
}

save_configuration() {
    mkdir -p /etc/laravel-deploy
    
    cat > "$CONFIG_FILE" << EOF
# Laravel Deploy Configuration
# Generated: $(date)

$(for key in "${!CONFIG[@]}"; do
    echo "$key=\"${CONFIG[$key]}\""
done | sort)
EOF
    
    log_info "Configuration saved to $CONFIG_FILE"
}

load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "Configuration loaded from $CONFIG_FILE"
    else
        log_warning "Configuration file not found, using defaults"
    fi
}

configure_webserver() {
    local app_name="$1"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Load app configuration
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 1
    
    log_info "Configuring Nginx for $app_name (domain: $DOMAIN)"
    
    # Create Nginx configuration
    local nginx_conf="/etc/nginx/sites-available/$DOMAIN"
    
    cat > "$nginx_conf" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $DOMAIN www.$DOMAIN;
    root $app_path/public;
    
    index index.php index.html index.htm;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Laravel rewrite rules
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP handling
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm-laravel.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_read_timeout 300;
    }
    
    # Deny access to sensitive files
    location ~ /\.(?!well-known).* {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /\.env\$ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Favicon and robots
    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }
    
    location = /robots.txt {
        access_log off;
        log_not_found off;
    }
    
    # Health check endpoint
    location = /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Client settings
    client_max_body_size 100M;
    client_body_timeout 300s;
}
EOF
    
    # Enable site
    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"
    
    # Test configuration
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx configuration applied"
        return 0
    else
        log_error "Invalid Nginx configuration"
        return 1
    fi
}

configure_queue() {
    local app_name="$1"
    
    # Load app configuration
    source "/etc/laravel-deploy/apps/$app_name.conf" 2>/dev/null || return 0
    
    if [[ "$ENABLE_QUEUE" != "1" ]]; then
        return 0
    fi
    
    log_info "Configuring queue workers for $app_name"
    
    # Install supervisor if not exists
    if ! command -v supervisorctl &> /dev/null; then
        apt install -y supervisor
    fi
    
    local workers="${QUEUE_WORKERS:-2}"
    local app_path="${CONFIG[WWW_DIR]}/$app_name"
    
    # Create supervisor configuration
    cat > "/etc/supervisor/conf.d/$app_name-worker.conf" << EOF
[program:$app_name-worker]
process_name=%(program_name)s_%(process_num)02d
command=php $app_path/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=$workers
redirect_stderr=true
stdout_logfile=$app_path/storage/logs/worker.log
stopwaitsecs=3600
EOF
    
    # Configure scheduler
    if [[ "$ENABLE_SCHEDULER" == "1" ]]; then
        cat > "/etc/supervisor/conf.d/$app_name-scheduler.conf" << EOF
[program:$app_name-scheduler]
command=php $app_path/artisan schedule:run
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=$app_path/storage/logs/scheduler.log
EOF
    fi
    
    # Update supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start "$app_name-worker:*"
    
    if [[ "$ENABLE_SCHEDULER" == "1" ]]; then
        supervisorctl start "$app_name-scheduler"
    fi
    
    log_success "Queue workers configured ($workers workers)"
}

generate_deployment_report() {
    local apps=("${@:1:$#-3}")
    local success_count="${@: -3:1}"
    local failed_count="${@: -2:1}"
    local failed_apps=("${@: -1}")
    
    local report_file="/var/log/laravel-deploy/report-$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "deployment_id": "$(date +%Y%m%d%H%M%S)",
    "timestamp": "$(date -Iseconds)",
    "summary": {
        "total_applications": ${#apps[@]},
        "successful": $success_count,
        "failed": $failed_count
    },
    "applications": [
EOF
    
    for ((i=0; i<${#apps[@]}; i++)); do
        local app="${apps[$i]}"
        local app_path="${CONFIG[WWW_DIR]}/$app"
        
        if [[ $i -gt 0 ]]; then
            echo "," >> "$report_file"
        fi
        
        cat >> "$report_file" << EOF
        {
            "name": "$app",
            "path": "$app_path",
            "status": "$(contains "$app" "${failed_apps[@]}" && echo "failed" || echo "success")",
            "php_version": "$(detect_php_version "$app_path")",
            "last_deployed": "$(date -r "$app_path" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"
        }
EOF
    done
    
    cat >> "$report_file" << EOF
    ],
    "server_info": {
        "hostname": "$(hostname)",
        "os": "$(lsb_release -d | cut -f2)",
        "kernel": "$(uname -r)",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}')",
        "memory": "$(free -h | awk '/^Mem:/ {print $2 "/" $3}')"
    }
}
EOF
    
    log_info "Deployment report generated: $report_file"
}

contains() {
    local item="$1"
    shift
    for element; do
        [[ "$element" == "$item" ]] && return 0
    done
    return 1
}

encrypt_backup() {
    local backup_dir="$1"
    local key="$2"
    
    log_info "Encrypting backup..."
    
    # Encrypt database backup
    if [[ -f "$backup_dir/database.sql.gz" ]]; then
        openssl enc -aes-256-cbc -salt -in "$backup_dir/database.sql.gz" \
            -out "$backup_dir/database.sql.gz.enc" -pass pass:"$key"
        rm "$backup_dir/database.sql.gz"
    fi
    
    # Encrypt files backup
    if [[ -f "$backup_dir/files.tar.gz" ]]; then
        openssl enc -aes-256-cbc -salt -in "$backup_dir/files.tar.gz" \
            -out "$backup_dir/files.tar.gz.enc" -pass pass:"$key"
        rm "$backup_dir/files.tar.gz"
    fi
    
    log_info "Backup encrypted"
}

# ----------------------------
# 🚀 MAIN COMMAND HANDLER
# ----------------------------
main() {
    load_configuration
    
    case "${1:-}" in
        "provision")
            provision_server
            ;;
        "deploy")
            if [[ -n "${2:-}" ]]; then
                deploy_single_app "$2"
            else
                deploy_multiple_apps
            fi
            ;;
        "backup")
            if [[ -n "${2:-}" ]]; then
                create_backup "$2"
            else
                for app in $(scan_applications); do
                    create_backup "$app"
                done
            fi
            ;;
        "restore")
            restore_backup "${2:-}" "${3:-}"
            ;;
        "ssl")
            if [[ -n "${2:-}" ]]; then
                setup_ssl "$2"
            else
                for app in $(scan_applications); do
                    setup_ssl "$app"
                done
            fi
            ;;
        "db:backup")
            database_backup "${2:-}"
            ;;
        "db:restore")
            log_error "Not implemented yet"
            ;;
        "db:optimize")
            database_optimize "${2:-}"
            ;;
        "list")
            echo "Available applications:"
            for app in $(scan_applications); do
                echo "  - $app"
            done
            ;;
        "monitor")
            # Simple monitoring output
            echo "System Monitoring:"
            echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
            echo "  Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
            echo "  Disk: $(df -h / | awk 'NR==2 {print $4 " free"}')"
            echo ""
            echo "Application Status:"
            for app in $(scan_applications); do
                local app_path="${CONFIG[WWW_DIR]}/$app"
                if [[ -f "$app_path/artisan" ]]; then
                    echo "  - $app: $(cd "$app_path" && php artisan --version 2>/dev/null || echo "not responding")"
                fi
            done
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "version"|"--version"|"-v")
            echo "Laravel Deploy Pro v5.0-production"
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    cat << 'EOF'
Laravel Deploy Pro - Complete Deployment Solution

Usage: laravel-deploy [COMMAND] [OPTIONS]

Commands:
  provision                   Provision server with required software
  deploy [app]               Deploy all applications or specific app
  backup [app]               Backup all applications or specific app
  restore <app> [backup_id]  Restore application from backup
  ssl [app]                  Setup SSL for all applications or specific app
  db:backup <app>            Backup database only
  db:optimize <app>          Optimize database tables
  list                       List all Laravel applications
  monitor                    Show system and application status
  help                       Show this help message
  version                    Show version information

Examples:
  laravel-deploy provision          # Setup server
  laravel-deploy deploy             # Deploy all apps
  laravel-deploy deploy myapp       # Deploy specific app
  laravel-deploy backup myapp       # Backup specific app
  laravel-deploy ssl                # Setup SSL for all apps
  laravel-deploy monitor            # Check system status

Configuration:
  Global: /etc/laravel-deploy/config.conf
  Per App: /etc/laravel-deploy/apps/<app>.conf
  Logs: /var/log/laravel-deploy/
  Backups: /var/backups/laravel/

Features:
  ✅ Server provisioning automation
  ✅ Multi-application support
  ✅ Basic deployment pipeline
  ✅ Database management
  ✅ SSL certificate management
  ✅ Backup system with retention
EOF
}

# ----------------------------
# 🚪 ENTRY POINT
# ----------------------------
# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Create log directory
mkdir -p /var/log/laravel-deploy

# Run main function
main "$@"
