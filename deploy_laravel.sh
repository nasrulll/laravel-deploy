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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="/etc/laravel-deploy/config.conf"
readonly LOG_FILE="/var/log/laravel-deploy/deploy.log"
readonly ERROR_LOG="/var/log/laravel-deploy/errors.log"
readonly BACKUP_ROOT="/var/backups/laravel"
readonly DEPLOYMENTS_ROOT="/var/deployments"
readonly SSL_DIR="/etc/ssl/laravel"
readonly TEMP_DIR="/tmp/laravel-deploy"

# Default configuration
declare -A CONFIG=(
    [WWW_DIR]="/var/www"
    [PHP_VERSION]="8.2"
    [MYSQL_ROOT_PASS]="$(openssl rand -base64 32)"
    [REDIS_ENABLED]="1"
    [SSL_ENABLED]="1"
    [AUTO_BACKUP]="1"
    [BACKUP_RETENTION]="30"
    [MAX_BACKUPS]="5"
    [ENABLE_MONITORING]="1"
    [DEPLOYMENT_TIMEOUT]="300"
    [ZERO_DOWNTIME]="1"
    [ENABLE_FIREWALL]="1"
    [ENABLE_FAIL2BAN]="1"
    [TIMEZONE]="UTC"
    [SWAP_SIZE]="2G"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# OS Detection
OS=""
OS_VERSION=""
OS_CODENAME=""

# ----------------------------
# 📊 LOGGING & UTILITIES
# ----------------------------
init_logging() {
    mkdir -p "/var/log/laravel-deploy"
    touch "$LOG_FILE" "$ERROR_LOG"
    chmod 640 "$LOG_FILE" "$ERROR_LOG"
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")     echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS")  echo -e "${GREEN}[✓]${NC} $message" ;;
        "WARNING")  echo -e "${YELLOW}[!]${NC} $message" ;;
        "ERROR")    echo -e "${RED}[✗]${NC} $message" >&2 ;;
        "DEBUG")    [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $message" ;;
    esac
    
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    
    if [[ "$level" == "ERROR" ]]; then
        echo "$timestamp [$level] $message" >> "$ERROR_LOG"
    fi
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

spinner() {
    local pid=$1
    local msg="$2"
    local delay=0.1
    local spinstr='⣾⣽⣻⢿⡿⣟⣯⣷'
    
    echo -n -e "${BLUE}[ ]${NC} $msg  "
    
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 7); do
            echo -ne "\b${spinstr:$i:1}"
            sleep $delay
        done
    done
    
    echo -ne "\b\b\b\b${GREEN}[✓]${NC} $msg completed\n"
}

run_with_spinner() {
    local cmd="$1"
    local msg="$2"
    
    eval "$cmd" > /tmp/spinner.log 2>&1 &
    local pid=$!
    
    spinner $pid "$msg"
    
    wait $pid
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Failed: $msg"
        cat /tmp/spinner.log >> "$ERROR_LOG"
        return $exit_code
    fi
    
    return 0
}

check_dependencies() {
    local dependencies=("curl" "wget" "git" "gpg")
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing[@]}"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME="$VERSION_CODENAME"
        log_info "Detected: $NAME $VERSION ($OS_CODENAME)"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
        log_info "Detected: Debian $OS_VERSION"
    elif [[ -f /etc/centos-release ]]; then
        OS="centos"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release)
        log_info "Detected: CentOS $OS_VERSION"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
        log_info "Detected: RHEL $OS_VERSION"
    else
        log_error "Unsupported operating system"
        exit 1
    fi
}

install_apt_key() {
    local url="$1"
    local key_file="$2"
    
    if ! curl -fsSL "$url" | gpg --dearmor -o "$key_file" 2>/dev/null; then
        log_warning "Failed to download GPG key from $url, trying alternative..."
        wget -q -O- "$url" | gpg --dearmor -o "$key_file" 2>/dev/null || return 1
    fi
    
    mv "$key_file" /etc/apt/trusted.gpg.d/
    chmod 644 "/etc/apt/trusted.gpg.d/$key_file"
}

add_apt_repository() {
    local repo="$1"
    local key_url="$2"
    local list_file="$3"
    
    if [[ -n "$key_url" ]]; then
        local key_name=$(basename "$list_file" .list)
        install_apt_key "$key_url" "$key_name.gpg"
    fi
    
    echo "$repo" > "/etc/apt/sources.list.d/$list_file"
    apt-get update -qq
}

check_internet() {
    log_info "Checking internet connection..."
    
    if ! curl -s --max-time 10 -I https://github.com > /dev/null 2>&1; then
        if ! curl -s --max-time 10 -I https://google.com > /dev/null 2>&1; then
            log_error "No internet connection. Please check your network."
            exit 1
        fi
    fi
    
    # Test GitHub API
    if ! curl -s --max-time 10 https://api.github.com > /dev/null 2>&1; then
        log_warning "GitHub API may be slow, but proceeding anyway..."
    fi
    
    log_success "Internet connection OK"
}

create_swap() {
    local swap_size="${CONFIG[SWAP_SIZE]}"
    
    if [[ -n "$swap_size" && "$swap_size" != "0" && "$swap_size" != "false" ]]; then
        log_info "Creating swap file ($swap_size)..."
        
        # Check if swap already exists
        if swapon --show | grep -q "swapfile"; then
            log_info "Swap already exists"
            return 0
        fi
        
        # Create swap file
        fallocate -l "$swap_size" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Make permanent
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        
        # Optimize swappiness
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
        sysctl -p
        
        log_success "Swap file created and configured"
    fi
}

# ----------------------------
# 1️⃣ SERVER PROVISIONING AUTOMATION
# ----------------------------
provision_server() {
    log_info "🚀 Starting server provisioning..."
    
    detect_os
    check_internet
    check_dependencies
    
    # Set timezone
    timedatectl set-timezone "${CONFIG[TIMEZONE]}"
    
    # Update system
    log_info "Updating system packages..."
    run_with_spinner "apt-get update -y && apt-get upgrade -y" "System update"
    
    # Install essential packages
    log_info "Installing essential packages..."
    local essential_packages=(
        curl wget git unzip build-essential software-properties-common
        apt-transport-https ca-certificates gnupg lsb-release
        net-tools htop ncdu jq tree pv screen tmux
        zip unzip p7zip-full rar unrar
        dnsutils whois traceroute mtr
    )
    
    run_with_spinner "apt-get install -y ${essential_packages[*]}" "Essential packages"
    
    # Create swap if needed
    create_swap
    
    # Install Nginx
    log_info "Installing Nginx..."
    run_with_spinner "apt-get install -y nginx" "Nginx"
    
    # Install MySQL/MariaDB
    if [[ "$OS" == "ubuntu" && "$OS_VERSION" == "22.04" ]] || [[ "$OS" == "debian" && "$OS_VERSION" == "11" ]]; then
        log_info "Installing MySQL..."
        apt-get install -y mysql-server mysql-client
    else
        log_info "Installing MariaDB..."
        apt-get install -y mariadb-server mariadb-client
    fi
    
    # Secure MySQL installation
    log_info "Securing MySQL..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${CONFIG[MYSQL_ROOT_PASS]}';"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Install PHP
    log_info "Installing PHP ${CONFIG[PHP_VERSION]} and extensions..."
    add_apt_repository "ppa:ondrej/php" "" "ondrej-php.list"
    
    local php_packages=(
        "php${CONFIG[PHP_VERSION]}"
        "php${CONFIG[PHP_VERSION]}-fpm"
        "php${CONFIG[PHP_VERSION]}-mysql"
        "php${CONFIG[PHP_VERSION]}-pgsql"
        "php${CONFIG[PHP_VERSION]}-sqlite3"
        "php${CONFIG[PHP_VERSION]}-curl"
        "php${CONFIG[PHP_VERSION]}-gd"
        "php${CONFIG[PHP_VERSION]}-mbstring"
        "php${CONFIG[PHP_VERSION]}-xml"
        "php${CONFIG[PHP_VERSION]}-zip"
        "php${CONFIG[PHP_VERSION]}-bcmath"
        "php${CONFIG[PHP_VERSION]}-intl"
        "php${CONFIG[PHP_VERSION]}-redis"
        "php${CONFIG[PHP_VERSION]}-memcached"
        "php${CONFIG[PHP_VERSION]}-opcache"
        "php${CONFIG[PHP_VERSION]}-imagick"
        "php${CONFIG[PHP_VERSION]}-xsl"
        "php${CONFIG[PHP_VERSION]}-soap"
        "php${CONFIG[PHP_VERSION]}-ldap"
        "php${CONFIG[PHP_VERSION]}-msgpack"
        "php${CONFIG[PHP_VERSION]}-igbinary"
    )
    
    run_with_spinner "apt-get install -y ${php_packages[*]}" "PHP packages"
    
    # Install Composer
    log_info "Installing Composer..."
    local EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    local ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
    
    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        log_error "Composer installer checksum verification failed!"
        rm composer-setup.php
        exit 1
    fi
    
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    
    # Install Node.js
    log_info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Install Redis if enabled
    if [[ "${CONFIG[REDIS_ENABLED]}" == "1" ]]; then
        log_info "Installing Redis..."
        apt-get install -y redis-server
        systemctl enable redis-server
    fi
    
    # Install Supervisor
    log_info "Installing Supervisor..."
    apt-get install -y supervisor
    
    # Configure PHP-FPM
    log_info "Configuring PHP-FPM..."
    cat > "/etc/php/${CONFIG[PHP_VERSION]}/fpm/pool.d/laravel.conf" << EOF
[laravel]
user = www-data
group = www-data
listen = /run/php/php${CONFIG[PHP_VERSION]}-fpm-laravel.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
pm.max_requests = 500
pm.process_idle_timeout = 10s
request_terminate_timeout = 300
request_slowlog_timeout = 5s
slowlog = /var/log/php-fpm/laravel-slow.log
chdir = /
php_admin_value[error_log] = /var/log/php-fpm/laravel-error.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = 256M
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size] = 64M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
EOF
    
    # Configure Nginx
    log_info "Configuring Nginx..."
    cat > /etc/nginx/nginx.conf << 'NGINX'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 64M;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=two:10m rate=5r/s;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Logging Settings
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main buffer=32k flush=5s;
    error_log /var/log/nginx/error.log warn;
    
    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        image/svg+xml
        font/ttf
        font/otf
        font/woff
        font/woff2;
    
    # Cache Settings
    open_file_cache max=200000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX
    
    # Configure firewall if enabled
    if [[ "${CONFIG[ENABLE_FIREWALL]}" == "1" ]]; then
        log_info "Configuring firewall..."
        if command -v ufw &> /dev/null; then
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow ssh
            ufw allow http
            ufw allow https
            ufw --force enable
            log_success "UFW firewall configured"
        fi
    fi
    
    # Install fail2ban if enabled
    if [[ "${CONFIG[ENABLE_FAIL2BAN]}" == "1" ]]; then
        log_info "Installing fail2ban..."
        apt-get install -y fail2ban
        
        cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3

[laravel-auth]
enabled = true
port = http,https
filter = laravel-auth
logpath = /var/www/*/storage/logs/laravel.log
maxretry = 5
bantime = 86400
EOF
        
        systemctl enable fail2ban
        systemctl start fail2ban
    fi
    
    # Create directories
    log_info "Creating required directories..."
    mkdir -p "${CONFIG[WWW_DIR]}" "$BACKUP_ROOT" "$DEPLOYMENTS_ROOT" "$SSL_DIR" \
        /var/log/laravel-deploy /etc/laravel-deploy/apps \
        /var/log/php-fpm
    
    # Set permissions
    chown -R www-data:www-data "${CONFIG[WWW_DIR]}"
    chmod 755 "${CONFIG[WWW_DIR]}"
    chmod 750 "$BACKUP_ROOT"
    
    # Enable services
    log_info "Enabling services..."
    systemctl enable nginx
    systemctl enable "php${CONFIG[PHP_VERSION]}-fpm"
    systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null
    
    # Start services
    log_info "Starting services..."
    systemctl restart nginx
    systemctl restart "php${CONFIG[PHP_VERSION]}-fpm"
    systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null
    
    if [[ "${CONFIG[REDIS_ENABLED]}" == "1" ]]; then
        systemctl restart redis-server
    fi
    
    # Save configuration
    save_configuration
    
    # Generate summary
    log_success "✅ Server provisioning completed!"
    echo ""
    echo "==========================================="
    echo "         PROVISIONING SUMMARY"
    echo "==========================================="
    echo "PHP Version:        ${CONFIG[PHP_VERSION]}"
    echo "MySQL Root Password: ${CONFIG[MYSQL_ROOT_PASS]}"
    echo "Web Directory:      ${CONFIG[WWW_DIR]}"
    echo "Backup Directory:   $BACKUP_ROOT"
    echo "Log Directory:      /var/log/laravel-deploy"
    echo "Timezone:           ${CONFIG[TIMEZONE]}"
    echo "==========================================="
    echo ""
    echo "Next steps:"
    echo "1. Deploy your first app: laravel-deploy deploy <app-name>"
    echo "2. Check system status: laravel-deploy monitor"
    echo "3. View logs: tail -f /var/log/laravel-deploy/deploy.log"
}

# ----------------------------
# 🔧 HELPER FUNCTIONS (DIPERBAIKI)
# ----------------------------
save_configuration() {
    mkdir -p /etc/laravel-deploy
    
    {
        echo "# Laravel Deploy Configuration"
        echo "# Generated: $(date)"
        echo "# Do not edit manually unless you know what you're doing"
        echo ""
        
        for key in "${!CONFIG[@]}"; do
            echo "${key}=\"${CONFIG[$key]}\""
        done | sort
    } > "$CONFIG_FILE"
    
    chmod 600 "$CONFIG_FILE"
    log_info "Configuration saved to $CONFIG_FILE"
}

load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Backup original IFS
        local OLD_IFS=$IFS
        IFS=$'\n'
        
        while IFS='=' read -r key value; do
            # Remove comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value
            value="${value%\"}"
            value="${value#\"}"
            
            CONFIG["$key"]="$value"
        done < "$CONFIG_FILE"
        
        IFS=$OLD_IFS
        log_info "Configuration loaded from $CONFIG_FILE"
    else
        log_warning "Configuration file not found, using defaults"
    fi
}

generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | fold -w 24 | head -1
}

validate_domain() {
    local domain="$1"
    
    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    # Check for invalid patterns
    if [[ "$domain" =~ \.localhost$ ]] || \
       [[ "$domain" =~ ^localhost\. ]] || \
       [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    
    return 0
}

# ----------------------------
# 🚀 MAIN COMMAND HANDLER
# ----------------------------
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
  setup-app <name> <domain>  Setup new application
  help                       Show this help message
  version                    Show version information

Options:
  --debug                    Enable debug mode
  --no-color                 Disable colored output
  --log-file <file>          Specify log file
  --config <file>            Specify config file

Examples:
  laravel-deploy provision          # Setup server
  laravel-deploy deploy             # Deploy all apps
  laravel-deploy deploy myapp       # Deploy specific app
  laravel-deploy setup-app myapp example.com  # Setup new app
  laravel-deploy backup myapp       # Backup specific app
  laravel-deploy ssl                # Setup SSL for all apps
  laravel-deploy monitor            # Check system status

Configuration:
  Global: /etc/laravel-deploy/config.conf
  Per App: /etc/laravel-deploy/apps/<app>.conf
  Logs: /var/log/laravel-deploy/
  Backups: /var/backups/laravel/
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG=1
                shift
                ;;
            --no-color)
                RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; NC=''; BOLD=''
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    COMMAND="${1:-help}"
    shift
    ARGS=("$@")
}

main() {
    parse_arguments "$@"
    init_logging
    load_configuration
    
    trap 'log_error "Script interrupted by user"; exit 130' INT TERM
    
    case "$COMMAND" in
        "provision")
            provision_server
            ;;
        "deploy")
            if [[ -n "${ARGS[0]:-}" ]]; then
                deploy_single_app "${ARGS[0]}"
            else
                deploy_multiple_apps
            fi
            ;;
        "backup")
            if [[ -n "${ARGS[0]:-}" ]]; then
                create_backup "${ARGS[0]}"
            else
                for app in $(scan_applications); do
                    create_backup "$app"
                done
            fi
            ;;
        "restore")
            if [[ -z "${ARGS[0]:-}" ]]; then
                log_error "Application name required for restore"
                show_help
                exit 1
            fi
            restore_backup "${ARGS[0]}" "${ARGS[1]:-}"
            ;;
        "ssl")
            if [[ -n "${ARGS[0]:-}" ]]; then
                setup_ssl "${ARGS[0]}"
            else
                for app in $(scan_applications); do
                    setup_ssl "$app"
                done
            fi
            ;;
        "db:backup")
            database_backup "${ARGS[0]:-}"
            ;;
        "db:optimize")
            database_optimize "${ARGS[0]:-}"
            ;;
        "list")
            echo "Available applications:"
            for app in $(scan_applications); do
                echo "  - $app"
            done
            ;;
        "monitor")
            show_monitor
            ;;
        "setup-app")
            if [[ -z "${ARGS[0]:-}" || -z "${ARGS[1]:-}" ]]; then
                log_error "Usage: laravel-deploy setup-app <name> <domain>"
                exit 1
            fi
            setup_new_app "${ARGS[0]}" "${ARGS[1]}"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "version"|"--version"|"-v")
            echo "Laravel Deploy Pro v5.0-production"
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# ----------------------------
# 🚪 ENTRY POINT
# ----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
    
    # Run main function with all arguments
    main "$@"
fi