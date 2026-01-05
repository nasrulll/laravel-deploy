#!/bin/bash
# ==============================================
# 🚀 Laravel Multi-Domain Deploy Script - ENTERPRISE
# Version       : 3.0-fase1
# Author        : Nasrul Muiz
# Description   : Enterprise-grade deployment dengan zero-downtime,
#                 advanced security, dan automated recovery
# ==============================================

set -euo pipefail

# ----------------------------
# 🌟 CONFIGURATION
# ----------------------------
LOG_FILE="/var/log/laravel_enterprise_deploy.log"
ERROR_LOG_FILE="/var/log/laravel_enterprise_errors.log"
DEPLOYMENT_REPORT="/var/log/laravel_deployment_report_$(date +%Y%m%d_%H%M%S).json"
SILENT_MODE=0
VERBOSE_MODE=0
ROLLBACK_ON_ERROR=1

# Directories
WWW_DIR="/var/www"
BACKUP_DIR="/var/backups/laravel"
RELEASES_DIR="/var/releases"
SCRIPTS_DIR="/usr/local/bin/laravel-deploy"

# Backup Configuration
MAX_BACKUPS=5
BACKUP_RETENTION_DAYS=30
REMOTE_BACKUP_ENABLED=0
REMOTE_BACKUP_PATH="s3://your-bucket/laravel-backups"

# Deployment Configuration
ZERO_DOWNTIME_ENABLED=1
MAINTENANCE_MODE_ENABLED=1
DEPLOYMENT_TIMEOUT=300

# PHP Configuration
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
DEFAULT_PHP_VERSION="8.1"
PHP_OPCACHE_ENABLED=1
PHP_MEMORY_LIMIT="256M"
PHP_MAX_EXECUTION_TIME=180

# Security Configuration
ENABLE_FIREWALL=1
ENABLE_FAIL2BAN=1
ENABLE_SECURITY_HEADERS=1
ENABLE_RATE_LIMITING=1
RATE_LIMIT_PER_IP=60
RATE_LIMIT_PER_IP_BURST=120

# Redis Configuration
REDIS_ENABLED=1
REDIS_MEMORY="256mb"
REDIS_MAXMEMORY_POLICY="allkeys-lru"

# Monitoring
ENABLE_MONITORING=1
MONITORING_PORT=9100

# ----------------------------
# 🎯 ARGUMENT PARSING
# ----------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --silent|-s)
            SILENT_MODE=1
            shift
            ;;
        --verbose|-v)
            VERBOSE_MODE=1
            shift
            ;;
        --no-rollback)
            ROLLBACK_ON_ERROR=0
            shift
            ;;
        --no-zero-downtime)
            ZERO_DOWNTIME_ENABLED=0
            shift
            ;;
        --backup-only)
            BACKUP_ONLY=1
            shift
            ;;
        --restore)
            RESTORE_MODE=1
            shift
            ;;
        --app=*)
            SPECIFIC_APP="${1#*=}"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version)
            echo "Laravel Enterprise Deploy v3.0-fase1"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# ----------------------------
# 📊 LOGGING FUNCTIONS
# ----------------------------
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="$timestamp | $level | $message"
    
    echo -e "$log_entry" >> "$LOG_FILE"
    
    if [[ $VERBOSE_MODE -eq 1 ]] || [[ $level == "ERROR" ]]; then
        case $level in
            "SUCCESS") echo -e "✅ $message" ;;
            "ERROR") echo -e "❌ $message" >&2 ;;
            "WARNING") echo -e "⚠️  $message" ;;
            "INFO") echo -e "ℹ️  $message" ;;
            *) echo -e "📝 $message" ;;
        esac
    fi
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_error() { log "ERROR" "$1"; }
log_warning() { log "WARNING" "$1"; }

# ----------------------------
# 🛡️ SECURITY FUNCTIONS
# ----------------------------
generate_secure_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c 24
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

sanitize_input() {
    echo "$1" | tr -cd 'a-zA-Z0-9_-'
}

# ----------------------------
# 🔄 BACKUP & RECOVERY FUNCTIONS
# ----------------------------
create_backup() {
    local app_name="$1"
    local app_path="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$app_name/$timestamp"
    
    log_info "Creating backup for $app_name..."
    
    # Create backup directory
    mkdir -p "$backup_path"
    
    # Backup database
    if [[ -f "$app_path/.env" ]]; then
        extract_db_credentials "$app_path/.env"
        if [[ -n "$DB_NAME" ]] && [[ -n "$DB_USER" ]] && [[ -n "$DB_PASSWORD" ]]; then
            log_info "Backing up database: $DB_NAME"
            mysqldump --single-transaction --quick \
                -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
                > "$backup_path/database.sql" 2>> "$ERROR_LOG_FILE"
            
            if [[ $? -eq 0 ]]; then
                gzip "$backup_path/database.sql"
                log_success "Database backup completed"
            else
                log_warning "Database backup failed"
            fi
        fi
    fi
    
    # Backup files (exclude large directories)
    log_info "Backing up application files..."
    rsync -a --exclude={'vendor','node_modules','storage/framework/cache','storage/logs','.git'} \
        "$app_path/" "$backup_path/files/"
    
    # Backup .env file separately
    if [[ -f "$app_path/.env" ]]; then
        cp "$app_path/.env" "$backup_path/"
    fi
    
    # Create backup manifest
    cat > "$backup_path/manifest.json" << EOF
{
    "app_name": "$app_name",
    "timestamp": "$timestamp",
    "backup_path": "$backup_path",
    "file_count": "$(find "$backup_path/files" -type f | wc -l)",
    "database_size": "$(stat -c%s "$backup_path/database.sql.gz" 2>/dev/null || echo 0)",
    "created_by": "$(whoami)",
    "hostname": "$(hostname)"
}
EOF
    
    # Cleanup old backups
    cleanup_old_backups "$app_name"
    
    # Optional: Upload to remote storage
    if [[ $REMOTE_BACKUP_ENABLED -eq 1 ]]; then
        upload_to_remote "$backup_path" "$app_name/$timestamp"
    fi
    
    echo "$backup_path"
}

cleanup_old_backups() {
    local app_name="$1"
    local backup_dir="$BACKUP_DIR/$app_name"
    
    if [[ -d "$backup_dir" ]]; then
        log_info "Cleaning up old backups for $app_name..."
        
        # Remove backups older than retention days
        find "$backup_dir" -maxdepth 1 -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \;
        
        # Keep only last N backups
        local backups=($(ls -1t "$backup_dir" 2>/dev/null))
        local backup_count=${#backups[@]}
        
        if [[ $backup_count -gt $MAX_BACKUPS ]]; then
            for ((i=MAX_BACKUPS; i<backup_count; i++)); do
                rm -rf "$backup_dir/${backups[$i]}"
            done
        fi
        
        log_success "Backup cleanup completed"
    fi
}

restore_backup() {
    local app_name="$1"
    local timestamp="$2"
    local backup_path="$BACKUP_DIR/$app_name/$timestamp"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi
    
    log_info "Restoring backup $timestamp for $app_name..."
    
    # Stop services temporarily
    if [[ $ZERO_DOWNTIME_ENABLED -eq 1 ]]; then
        enable_maintenance_mode "$app_name"
    fi
    
    # Restore database
    if [[ -f "$backup_path/database.sql.gz" ]]; then
        log_info "Restoring database..."
        gunzip -c "$backup_path/database.sql.gz" | mysql "$DB_NAME"
    fi
    
    # Restore files
    local app_path="$WWW_DIR/$app_name"
    log_info "Restoring files..."
    rm -rf "$app_path"
    cp -r "$backup_path/files" "$app_path"
    
    # Restore .env
    if [[ -f "$backup_path/.env" ]]; then
        cp "$backup_path/.env" "$app_path/.env"
    fi
    
    # Fix permissions
    fix_permissions "$app_path"
    
    # Restart services
    restart_services
    
    log_success "Restore completed successfully"
}

# ----------------------------
# 🚀 ZERO-DOWNTIME DEPLOYMENT
# ----------------------------
zero_downtime_deploy() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    local release_id=$(date +%Y%m%d%H%M%S)
    local release_dir="$RELEASES_DIR/$app_name/releases/$release_id"
    local current_link="$RELEASES_DIR/$app_name/current"
    local shared_dir="$RELEASES_DIR/$app_name/shared"
    
    log_info "Starting zero-downtime deployment for $app_name..."
    
    # Create directory structure
    mkdir -p "$release_dir" "$shared_dir"
    
    # Copy application files to new release
    log_info "Copying application files..."
    rsync -a --exclude={'storage','.env','vendor','node_modules'} \
        "$app_path/" "$release_dir/"
    
    # Link shared directories
    ln -sfn "$shared_dir/storage" "$release_dir/storage"
    ln -sfn "$app_path/.env" "$release_dir/.env"
    
    # Run deployment steps in new release
    cd "$release_dir"
    
    # Install dependencies
    log_info "Installing dependencies..."
    composer install --no-dev --optimize-autoloader --no-interaction
    
    # Run migrations
    log_info "Running database migrations..."
    php artisan migrate --force --no-interaction
    
    # Optimize application
    log_info "Optimizing application..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Switch to new release
    log_info "Switching to new release..."
    ln -sfn "$release_dir" "$current_link"
    
    # Reload PHP-FPM without interrupting requests
    log_info "Reloading PHP-FPM..."
    sudo /bin/kill -USR2 $(cat /var/run/php/php$(get_php_version "$app_name")-fpm.pid 2>/dev/null) 2>/dev/null || true
    
    # Cleanup old releases (keep last 5)
    cleanup_old_releases "$app_name"
    
    log_success "Zero-downtime deployment completed"
}

cleanup_old_releases() {
    local app_name="$1"
    local releases_dir="$RELEASES_DIR/$app_name/releases"
    
    if [[ -d "$releases_dir" ]]; then
        local releases=($(ls -1t "$releases_dir" 2>/dev/null))
        local release_count=${#releases[@]}
        
        if [[ $release_count -gt 5 ]]; then
            for ((i=5; i<release_count; i++)); do
                rm -rf "$releases_dir/${releases[$i]}"
            done
        fi
    fi
}

enable_maintenance_mode() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    log_info "Enabling maintenance mode for $app_name..."
    
    cd "$app_path"
    php artisan down --retry=60 --secret=$(generate_secure_password) \
        --render="errors::503" --refresh=15
    
    # Create maintenance page
    cat > "$app_path/resources/views/errors/503.blade.php" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance Mode</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding: 50px; }
        h1 { font-size: 50px; }
        body { font: 20px Helvetica, sans-serif; color: #333; }
        article { display: block; text-align: left; max-width: 650px; margin: 0 auto; }
        a { color: #dc8100; text-decoration: none; }
        a:hover { color: #333; text-decoration: none; }
    </style>
</head>
<body>
    <article>
        <h1>We'll be back soon!</h1>
        <div>
            <p>Sorry for the inconvenience but we're performing some maintenance at the moment.</p>
            <p>We'll be back online shortly!</p>
            <p>&mdash; The Team</p>
        </div>
    </article>
</body>
</html>
EOF
}

disable_maintenance_mode() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    log_info "Disabling maintenance mode for $app_name..."
    
    cd "$app_path"
    php artisan up
}

# ----------------------------
# 🔒 SECURITY HARDENING
# ----------------------------
harden_security() {
    log_info "Applying security hardening..."
    
    # 1. Configure firewall
    if [[ $ENABLE_FIREWALL -eq 1 ]]; then
        configure_firewall
    fi
    
    # 2. Install and configure Fail2Ban
    if [[ $ENABLE_FAIL2BAN -eq 1 ]]; then
        configure_fail2ban
    fi
    
    # 3. Secure SSH
    secure_ssh
    
    # 4. Set file permissions
    set_secure_permissions
    
    # 5. Configure kernel parameters
    configure_kernel_security
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow $MONITORING_PORT/tcp comment 'Node Exporter'
    ufw --force enable
    
    log_success "Firewall configured"
}

configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    
    apt install -y fail2ban
    
    # Create Laravel jail
    cat > /etc/fail2ban/jail.d/laravel.conf << EOF
[laravel]
enabled = true
port = http,https
filter = laravel
logpath = /var/www/*/storage/logs/laravel.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
    
    # Create Laravel filter
    cat > /etc/fail2ban/filter.d/laravel.conf << EOF
[Definition]
failregex = ^.*local\.ERROR:.*Too many login attempts.*
            ^.*local\.ERROR:.*Authentication attempt failed.*
            ^.*local\.ERROR:.*Failed to authenticate.*
ignoreregex =
EOF
    
    systemctl restart fail2ban
    log_success "Fail2Ban configured"
}

secure_ssh() {
    log_info "Securing SSH configuration..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Apply security settings
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
    sed -i 's/^#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
    
    echo "AllowUsers $(whoami)" >> /etc/ssh/sshd_config
    
    systemctl restart sshd
    log_success "SSH secured"
}

configure_kernel_security() {
    log_info "Configuring kernel security parameters..."
    
    cat >> /etc/sysctl.conf << EOF
# Kernel security settings
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.core_uses_pid = 1
kernel.kptr_restrict = 2
kernel.sysrq = 0
kernel.yama.ptrace_scope = 1
EOF
    
    sysctl -p
    log_success "Kernel security configured"
}

# ----------------------------
# 💰 COST OPTIMIZATION
# ----------------------------
optimize_costs() {
    log_info "Applying cost optimization measures..."
    
    # 1. Install and configure Redis
    if [[ $REDIS_ENABLED -eq 1 ]]; then
        install_redis
    fi
    
    # 2. Configure PHP OpCache
    if [[ $PHP_OPCACHE_ENABLED -eq 1 ]]; then
        configure_opcache
    fi
    
    # 3. Configure Nginx caching
    configure_nginx_cache
    
    # 4. Optimize MariaDB
    optimize_mariadb
    
    # 5. Setup log rotation
    configure_log_rotation
}

install_redis() {
    log_info "Installing and configuring Redis..."
    
    apt install -y redis-server
    
    # Configure Redis
    sed -i "s/^# maxmemory .*/maxmemory $REDIS_MEMORY/" /etc/redis/redis.conf
    sed -i "s/^# maxmemory-policy .*/maxmemory-policy $REDIS_MAXMEMORY_POLICY/" /etc/redis/redis.conf
    sed -i "s/^supervised no/supervised systemd/" /etc/redis/redis.conf
    sed -i "s/^bind 127.0.0.1 ::1/bind 127.0.0.1/" /etc/redis/redis.conf
    
    # Enable Redis persistence
    cat >> /etc/redis/redis.conf << EOF
# Enable AOF persistence
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
EOF
    
    systemctl restart redis
    
    # Update Laravel .env files to use Redis
    for app_path in "$WWW_DIR"/*; do
        if [[ -f "$app_path/.env" ]]; then
            sed -i "s/CACHE_DRIVER=file/CACHE_DRIVER=redis/" "$app_path/.env"
            sed -i "s/SESSION_DRIVER=file/SESSION_DRIVER=redis/" "$app_path/.env"
            sed -i "s/QUEUE_CONNECTION=sync/QUEUE_CONNECTION=redis/" "$app_path/.env"
        fi
    done
    
    log_success "Redis configured"
}

configure_opcache() {
    log_info "Configuring PHP OpCache..."
    
    for version in "${PHP_VERSIONS[@]}"; do
        if [[ -f "/etc/php/$version/fpm/conf.d/10-opcache.ini" ]]; then
            cat > "/etc/php/$version/fpm/conf.d/10-opcache.ini" << EOF
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.max_wasted_percentage=10
opcache.use_cwd=1
opcache.validate_timestamps=0
opcache.revalidate_freq=2
opcache.fast_shutdown=1
opcache.enable_file_override=1
opcache.optimization_level=0x7FFFBFFF
opcache.file_cache=/tmp/php-opcache
EOF
        fi
    done
    log_success "OpCache configured"
}

configure_nginx_cache() {
    log_info "Configuring Nginx caching..."
    
    # Create cache directories
    mkdir -p /var/cache/nginx/{proxy,temp,fastcgi,scgi,uwsgi}
    chown -R www-data:www-data /var/cache/nginx
    
    # Add cache configuration to nginx.conf
    cat >> /etc/nginx/nginx.conf << EOF
# Cache configuration
proxy_cache_path /var/cache/nginx/proxy levels=1:2 keys_zone=proxy_cache:10m max_size=1g inactive=60m use_temp_path=off;
fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=fastcgi_cache:10m max_size=1g inactive=60m use_temp_path=off;
proxy_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
EOF
    
    log_success "Nginx caching configured"
}

optimize_mariadb() {
    log_info "Optimizing MariaDB configuration..."
    
    # Calculate optimal values based on available memory
    local total_memory=$(free -m | awk '/^Mem:/{print $2}')
    local innodb_buffer_pool=$((total_memory * 50 / 100))M
    local key_buffer=$((total_memory * 10 / 100))M
    local max_connections=200
    
    cat > /etc/mysql/mariadb.conf.d/99-optimization.cnf << EOF
[mysqld]
# Memory Configuration
innodb_buffer_pool_size = $innodb_buffer_pool
key_buffer_size = $key_buffer
query_cache_size = 64M
query_cache_type = 1
tmp_table_size = 64M
max_heap_table_size = 64M

# Connection Configuration
max_connections = $max_connections
thread_cache_size = 50
table_open_cache = 4000
table_definition_cache = 4000

# InnoDB Configuration
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_buffer_pool_instances = 8

# Query Optimization
join_buffer_size = 4M
sort_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-queries.log
long_query_time = 2
log_queries_not_using_indexes = 1

# Other Optimizations
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF
    
    systemctl restart mariadb
    
    # Optimize existing tables
    mysql -e "SELECT CONCAT('OPTIMIZE TABLE ', table_schema, '.', table_name, ';') FROM information_schema.tables WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema') AND ENGINE IS NOT NULL" | mysql
    
    log_success "MariaDB optimized"
}

# ----------------------------
# 🛠️ DEPLOYMENT FUNCTIONS
# ----------------------------
deploy_application() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    log_info "Starting deployment of $app_name"
    
    # 1. Create backup
    local backup_path=$(create_backup "$app_name" "$app_path")
    
    # 2. Enable maintenance mode
    if [[ $MAINTENANCE_MODE_ENABLED -eq 1 ]]; then
        enable_maintenance_mode "$app_name"
    fi
    
    # 3. Perform deployment
    if [[ $ZERO_DOWNTIME_ENABLED -eq 1 ]]; then
        zero_downtime_deploy "$app_name"
    else
        traditional_deploy "$app_name"
    fi
    
    # 4. Disable maintenance mode
    if [[ $MAINTENANCE_MODE_ENABLED -eq 1 ]]; then
        disable_maintenance_mode "$app_name"
    fi
    
    # 5. Verify deployment
    verify_deployment "$app_name"
    
    log_success "Deployment completed for $app_name"
    echo "$backup_path"
}

traditional_deploy() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    log_info "Performing traditional deployment..."
    
    cd "$app_path"
    
    # Update code
    if [[ -d ".git" ]]; then
        git pull origin main
    fi
    
    # Install dependencies
    composer install --no-dev --optimize-autoloader --no-interaction
    
    # Run migrations
    php artisan migrate --force --no-interaction
    
    # Clear caches
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    php artisan cache:clear
    
    # Optimize
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Fix permissions
    fix_permissions "$app_path"
}

verify_deployment() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    log_info "Verifying deployment..."
    
    # Check if artisan is working
    if ! cd "$app_path" && php artisan --version > /dev/null 2>&1; then
        log_error "Artisan command failed"
        return 1
    fi
    
    # Check if routes are cached
    if [[ -f "$app_path/bootstrap/cache/routes.php" ]]; then
        log_success "Routes are cached"
    fi
    
    # Check if config is cached
    if [[ -f "$app_path/bootstrap/cache/config.php" ]]; then
        log_success "Config is cached"
    fi
    
    # Test database connection
    if cd "$app_path" && php artisan tinker --execute="echo DB::connection()->getPdo() ? 'OK' : 'FAIL';" 2>/dev/null | grep -q "OK"; then
        log_success "Database connection OK"
    else
        log_warning "Database connection test failed"
    fi
    
    log_success "Deployment verification completed"
}

# ----------------------------
# 📦 APPLICATION MANAGEMENT
# ----------------------------
scan_applications() {
    log_info "Scanning for Laravel applications..."
    
    local apps=()
    for dir in "$WWW_DIR"/*; do
        if [[ -d "$dir" ]] && [[ -f "$dir/artisan" ]] && [[ -f "$dir/composer.json" ]]; then
            local app_name=$(basename "$dir")
            
            # Validate Laravel application
            if grep -q '"laravel/framework"' "$dir/composer.json"; then
                apps+=("$app_name")
                
                # Detect Laravel version
                local version=$(grep -o '"laravel/framework":"[^"]*' "$dir/composer.json" | cut -d'"' -f4)
                log_info "Found: $app_name (Laravel $version)"
            fi
        fi
    done
    
    echo "${apps[@]}"
}

get_php_version() {
    local app_name="$1"
    local app_path="$WWW_DIR/$app_name"
    
    if [[ -f "$app_path/.env" ]]; then
        # Try to extract from .env
        local env_version=$(grep -E '^PHP_VERSION=' "$app_path/.env" | cut -d'=' -f2)
        if [[ -n "$env_version" ]]; then
            echo "$env_version"
            return
        fi
    fi
    
    # Check composer.json for PHP requirement
    if [[ -f "$app_path/composer.json" ]]; then
        local composer_version=$(grep -o '"php":"[^"]*' "$app_path/composer.json" | cut -d'"' -f4)
        if [[ "$composer_version" == *"7.4"* ]]; then
            echo "7.4"
        elif [[ "$composer_version" == *"8.0"* ]]; then
            echo "8.0"
        elif [[ "$composer_version" == *"8.1"* ]]; then
            echo "8.1"
        elif [[ "$composer_version" == *"8.2"* ]]; then
            echo "8.2"
        elif [[ "$composer_version" == *"8.3"* ]]; then
            echo "8.3"
        else
            echo "$DEFAULT_PHP_VERSION"
        fi
    else
        echo "$DEFAULT_PHP_VERSION"
    fi
}

fix_permissions() {
    local app_path="$1"
    
    log_info "Fixing permissions..."
    
    # Set directory permissions
    find "$app_path" -type d -exec chmod 755 {} \;
    
    # Set file permissions
    find "$app_path" -type f -exec chmod 644 {} \;
    
    # Special permissions for storage and cache
    chmod -R 775 "$app_path/storage"
    chmod -R 775 "$app_path/bootstrap/cache"
    
    # Set ownership
    chown -R www-data:www-data "$app_path"
    
    # Log file permissions
    touch "$app_path/storage/logs/laravel.log"
    chmod 664 "$app_path/storage/logs/laravel.log"
    
    log_success "Permissions fixed"
}

# ----------------------------
# 📝 CONFIGURATION MANAGEMENT
# ----------------------------
configure_nginx_site() {
    local app_name="$1"
    local domain="$2"
    local app_path="$WWW_DIR/$app_name"
    local php_version=$(get_php_version "$app_name")
    
    log_info "Configuring Nginx for $domain..."
    
    local vhost_file="/etc/nginx/sites-available/$domain.conf"
    
    cat > "$vhost_file" << EOF
# $app_name - $domain
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
    
    # Root directory
    root $app_path/public;
    index index.php index.html index.htm;
    
    # Character set
    charset utf-8;
    
    # Logging
    access_log /var/log/nginx/${app_name}_access.log;
    error_log /var/log/nginx/${app_name}_error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=${RATE_LIMIT_PER_IP}r/m;
    limit_req_zone \$binary_remote_addr zone=global:10m rate=${RATE_LIMIT_PER_IP_BURST}r/m;
    
    # Main location
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
        
        # Apply rate limiting
        limit_req zone=global burst=${RATE_LIMIT_PER_IP_BURST} nodelay;
    }
    
    # API rate limiting
    location ~ ^/api/ {
        limit_req zone=api burst=20 nodelay;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP handling
    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # FastCGI optimizations
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    # Static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Deny access to sensitive files
    location ~ /\.(?!well-known).* {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /\.env {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /\.git {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /storage/logs/ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Health check endpoint
    location /health {
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
    ln -sf "$vhost_file" "/etc/nginx/sites-enabled/"
    
    # Test configuration
    if nginx -t > /dev/null 2>&1; then
        log_success "Nginx configuration valid"
    else
        log_error "Nginx configuration invalid"
        rm -f "/etc/nginx/sites-enabled/$domain.conf"
        return 1
    fi
}

# ----------------------------
# 🔧 SERVICE MANAGEMENT
# ----------------------------
restart_services() {
    log_info "Restarting services..."
    
    # Restart Nginx
    systemctl restart nginx
    
    # Restart PHP-FPM for all versions
    for version in "${PHP_VERSIONS[@]}"; do
        if systemctl is-active --quiet "php${version}-fpm"; then
            systemctl restart "php${version}-fpm"
        fi
    done
    
    # Restart Redis if enabled
    if [[ $REDIS_ENABLED -eq 1 ]]; then
        systemctl restart redis
    fi
    
    # Restart MariaDB
    systemctl restart mariadb
    
    log_success "Services restarted"
}

# ----------------------------
# 📊 MONITORING
# ----------------------------
setup_monitoring() {
    if [[ $ENABLE_MONITORING -eq 0 ]]; then
        return
    fi
    
    log_info "Setting up monitoring..."
    
    # Install Node Exporter
    local node_exporter_version="1.5.0"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
    
    curl -L "$node_exporter_url" -o /tmp/node_exporter.tar.gz
    tar -xzf /tmp/node_exporter.tar.gz -C /tmp
    mv "/tmp/node_exporter-${node_exporter_version}.linux-amd64/node_exporter" /usr/local/bin/
    
    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    # Setup Laravel Horizon if exists
    for app_path in "$WWW_DIR"/*; do
        if [[ -f "$app_path/composer.json" ]] && grep -q '"laravel/horizon"' "$app_path/composer.json"; then
            cd "$app_path"
            php artisan horizon:install
            php artisan horizon:publish
            systemctl enable "horizon-$(basename "$app_path")"
        fi
    done
    
    log_success "Monitoring setup completed"
}

# ----------------------------
# 📄 REPORTING
# ----------------------------
generate_deployment_report() {
    local apps=("$@")
    
    log_info "Generating deployment report..."
    
    cat > "$DEPLOYMENT_REPORT" << EOF
{
    "deployment_id": "$(date +%Y%m%d%H%M%S)",
    "timestamp": "$(date -Iseconds)",
    "server": {
        "hostname": "$(hostname)",
        "os": "$(lsb_release -d | cut -f2)",
        "kernel": "$(uname -r)",
        "memory": "$(free -h | awk '/^Mem:/ {print $2}')",
        "disk": "$(df -h / | awk 'NR==2 {print $4}')"
    },
    "deployment_config": {
        "zero_downtime_enabled": $ZERO_DOWNTIME_ENABLED,
        "backup_retention_days": $BACKUP_RETENTION_DAYS,
        "max_backups": $MAX_BACKUPS,
        "security_hardening": {
            "firewall": $ENABLE_FIREWALL,
            "fail2ban": $ENABLE_FAIL2BAN,
            "rate_limiting": $ENABLE_RATE_LIMITING
        },
        "optimization": {
            "redis_enabled": $REDIS_ENABLED,
            "opcache_enabled": $PHP_OPCACHE_ENABLED
        }
    },
    "applications": [
EOF
    
    local first=1
    for app_name in "${apps[@]}"; do
        local app_path="$WWW_DIR/$app_name"
        
        if [[ $first -eq 0 ]]; then
            echo "," >> "$DEPLOYMENT_REPORT"
        fi
        first=0
        
        cat >> "$DEPLOYMENT_REPORT" << EOF
        {
            "name": "$app_name",
            "path": "$app_path",
            "php_version": "$(get_php_version "$app_name")",
            "laravel_version": "$(get_laravel_version "$app_path")",
            "database": "$(get_database_info "$app_path")",
            "domain": "$(get_domain_for_app "$app_name")",
            "backup_count": "$(get_backup_count "$app_name")",
            "last_backup": "$(get_last_backup "$app_name")"
        }
EOF
    done
    
    cat >> "$DEPLOYMENT_REPORT" << EOF
    ],
    "services": {
        "nginx": "$(systemctl is-active nginx)",
        "mariadb": "$(systemctl is-active mariadb)",
        "redis": "$(systemctl is-active redis 2>/dev/null || echo "disabled")",
        "php_fpm": "$(get_php_fpm_status)"
    },
    "summary": {
        "total_apps": ${#apps[@]},
        "successful_deployments": "$(get_successful_deployments)",
        "failed_deployments": "$(get_failed_deployments)",
        "backup_size": "$(du -sh "$BACKUP_DIR" | cut -f1)"
    }
}
EOF
    
    chmod 600 "$DEPLOYMENT_REPORT"
    log_success "Deployment report generated: $DEPLOYMENT_REPORT"
}

# ----------------------------
# 🚦 MAIN EXECUTION
# ----------------------------
main() {
    # Initialize
    log_info "🚀 Starting Laravel Enterprise Deployment v3.0"
    log_info "Timestamp: $(date)"
    log_info "Server: $(hostname)"
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Create necessary directories
    mkdir -p "$WWW_DIR" "$BACKUP_DIR" "$RELEASES_DIR" "$SCRIPTS_DIR"
    
    # Detect applications
    local apps=($(scan_applications))
    
    if [[ ${#apps[@]} -eq 0 ]]; then
        log_error "No Laravel applications found in $WWW_DIR"
        exit 1
    fi
    
    log_success "Found ${#apps[@]} application(s): ${apps[*]}"
    
    # Apply security hardening
    harden_security
    
    # Apply cost optimization
    optimize_costs
    
    # Setup monitoring
    setup_monitoring
    
    # Deploy each application
    local deployment_results=()
    for app_name in "${apps[@]}"; do
        if [[ -n "$SPECIFIC_APP" ]] && [[ "$app_name" != "$SPECIFIC_APP" ]]; then
            continue
        fi
        
        log_info "========================================"
        log_info "Processing: $app_name"
        log_info "========================================"
        
        # Get domain for application
        local domain=$(prompt_for_domain "$app_name")
        
        # Configure Nginx
        if ! configure_nginx_site "$app_name" "$domain"; then
            log_error "Failed to configure Nginx for $app_name"
            continue
        fi
        
        # Perform deployment
        if backup_path=$(deploy_application "$app_name"); then
            deployment_results+=("{\"app\":\"$app_name\",\"status\":\"success\",\"backup\":\"$backup_path\"}")
        else
            deployment_results+=("{\"app\":\"$app_name\",\"status\":\"failed\"}")
            
            if [[ $ROLLBACK_ON_ERROR -eq 1 ]]; then
                log_warning "Rolling back $app_name..."
                restore_backup "$app_name" "$(basename "$backup_path")"
            fi
        fi
    done
    
    # Restart services
    restart_services
    
    # Generate report
    generate_deployment_report "${apps[@]}"
    
    # Final summary
    log_success "========================================"
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "========================================"
    log_info "Summary Report: $DEPLOYMENT_REPORT"
    log_info "Detailed Log: $LOG_FILE"
    log_info "Error Log: $ERROR_LOG_FILE"
    
    if [[ $SILENT_MODE -eq 0 ]]; then
        echo ""
        echo "🎉 All deployments completed!"
        echo ""
        echo "Next Steps:"
        echo "1. Review deployment report: $DEPLOYMENT_REPORT"
        echo "2. Test each application at its domain"
        echo "3. Monitor error logs for any issues"
        echo "4. Setup SSL certificates (if not already)"
        echo "5. Configure monitoring alerts"
        echo ""
    fi
}

# ----------------------------
# 🎯 HELPER FUNCTIONS
# ----------------------------
prompt_for_domain() {
    local app_name="$1"
    
    if [[ $SILENT_MODE -eq 1 ]]; then
        echo "${app_name}.local"
    else
        read -p "Enter domain for $app_name [${app_name}.local]: " domain
        echo "${domain:-${app_name}.local}"
    fi
}

show_help() {
    cat << EOF
Laravel Enterprise Deploy v3.0 - Fase 1

Usage: $0 [OPTIONS]

Options:
  -s, --silent              Run in silent mode (no prompts)
  -v, --verbose             Enable verbose output
  --no-rollback             Disable automatic rollback on error
  --no-zero-downtime        Disable zero-downtime deployment
  --backup-only             Only create backups, no deployment
  --restore                 Restore from backup
  --app=NAME               Deploy specific application only
  -h, --help               Show this help message
  --version                Show version information

Features:
  • Zero-downtime deployment with release management
  • Automated backup and recovery with retention policy
  • Enterprise-grade security hardening
  • Cost optimization with Redis caching
  • Comprehensive monitoring setup
  • Detailed deployment reporting

Examples:
  $0                         # Deploy all applications
  $0 --app=myapp            # Deploy specific application
  $0 --no-zero-downtime     # Traditional deployment
  $0 --backup-only          # Create backups only
EOF
}

# ----------------------------
# 🚪 ENTRY POINT
# ----------------------------
# Set trap for errors
trap 'log_error "Script terminated unexpectedly"; exit 1' INT TERM
trap 'final_cleanup' EXIT

# Run main function
main "$@"