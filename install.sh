#!/bin/bash
# ==============================================
# 🚀 Laravel Deploy - Installation Script
# Version       : 5.0.0
# Author        : Nasrul
# GitHub        : https://github.com/nasrulll/laravel-deploy
# Description   : One-line installer for Laravel Deploy
# ==============================================

set -euo pipefail

# ----------------------------
# 🌟 CONFIGURATION
# ----------------------------
readonly VERSION="5.0.0"
readonly REPO_URL="https://github.com/nasrulll/laravel-deploy"
readonly RAW_URL="https://raw.githubusercontent.com/nasrulll/laravel-deploy/main"
readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/laravel-deploy"
readonly LOG_DIR="/var/log/laravel-deploy"
readonly BACKUP_DIR="/var/backups/laravel-deploy-install"
readonly SYSTEMD_DIR="/etc/systemd/system"

# Default configuration
declare -A DEFAULT_CONFIG=(
    [PHP_VERSION]="8.1"
    [WWW_DIR]="/var/www"
    [BACKUP_RETENTION_DAYS]="30"
    [MAX_BACKUPS]="5"
    [ENABLE_MONITORING]="1"
    [ENABLE_FIREWALL]="1"
    [ENABLE_SSL]="1"
    [REDIS_ENABLED]="1"
    [ZERO_DOWNTIME]="1"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# ----------------------------
# 📊 LOGGING FUNCTIONS
# ----------------------------
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")     echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS")  echo -e "${GREEN}[✓]${NC} $message" ;;
        "WARNING")  echo -e "${YELLOW}[⚠]${NC} $message" ;;
        "ERROR")    echo -e "${RED}[✗]${NC} $message" >&2 ;;
        "DEBUG")    echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        *)          echo -e "${WHITE}[*]${NC} $message" ;;
    esac
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# Progress spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    local temp
    
    printf " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ----------------------------
# 🛡️ SECURITY & VALIDATION
# ----------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo -e "${YELLOW}Try: sudo bash <(curl ...)${NC}"
        exit 1
    fi
}

check_os() {
    log_info "Checking operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        
        case $OS in
            ubuntu|debian)
                log_success "Detected: $PRETTY_NAME"
                return 0
                ;;
            *)
                log_warning "Unsupported OS: $OS"
                if [[ "$FORCE_INSTALL" == "1" ]]; then
                    log_warning "Force install enabled, continuing anyway..."
                    return 0
                else
                    log_error "This script only supports Ubuntu/Debian"
                    exit 1
                fi
                ;;
        esac
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
}

check_internet() {
    log_info "Checking internet connection..."
    
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection detected"
        log_info "Please check your network and try again"
        exit 1
    fi
    
    # Test GitHub connectivity
    if ! curl -s --head --fail --max-time 5 "$RAW_URL" >/dev/null 2>&1; then
        log_warning "Cannot reach GitHub. Some features may not work."
    else
        log_success "Internet connection OK"
    fi
}

# ----------------------------
# 📦 DEPENDENCY MANAGEMENT
# ----------------------------
check_dependencies() {
    log_info "Checking system dependencies..."
    
    local deps=("curl" "wget" "git" "tar" "gzip")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        apt-get update -y >/dev/null 2>&1
        
        for dep in "${missing[@]}"; do
            apt-get install -y "$dep" >/dev/null 2>&1 &
            local pid=$!
            spinner $pid
            wait $pid
            
            if command -v "$dep" >/dev/null 2>&1; then
                log_debug "Installed: $dep"
            else
                log_error "Failed to install: $dep"
                return 1
            fi
        done
    fi
    
    log_success "All dependencies are available"
    return 0
}

# ----------------------------
# 🔄 BACKUP & RESTORE
# ----------------------------
backup_existing() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        local backup_file="${BACKUP_DIR}/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        if cp "$file" "$backup_file" 2>/dev/null; then
            log_debug "Backed up: $file -> $backup_file"
            echo "$backup_file"
        else
            log_warning "Failed to backup: $file"
        fi
    fi
}

restore_backup() {
    local backup_file="$1"
    local target_file="$2"
    
    if [[ -f "$backup_file" ]]; then
        if cp "$backup_file" "$target_file" 2>/dev/null; then
            log_debug "Restored: $backup_file -> $target_file"
            return 0
        else
            log_error "Failed to restore from backup"
            return 1
        fi
    fi
    return 1
}

# ----------------------------
# 📥 DOWNLOAD FUNCTIONS
# ----------------------------
download_file() {
    local url="$1"
    local output="$2"
    local method="${3:-curl}"
    
    case $method in
        "curl")
            if curl -sSL --fail --retry 3 --retry-delay 2 -o "$output" "$url"; then
                return 0
            fi
            ;;
        "wget")
            if wget -q --tries=3 --timeout=10 -O "$output" "$url"; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

download_main_script() {
    local method="$1"
    local output="$2"
    
    log_info "Downloading Laravel Deploy v$VERSION..."
    
    local sources=(
        "$RAW_URL/src/core/deploy.sh"
        "$RAW_URL/deploy.sh"
    )
    
    for source in "${sources[@]}"; do
        log_debug "Trying: $source"
        if download_file "$source" "$output" "$method"; then
            log_success "Script downloaded successfully"
            chmod +x "$output"
            return 0
        fi
    done
    
    log_error "Failed to download main script"
    return 1
}

download_component() {
    local component="$1"
    local output="$2"
    
    local url="$RAW_URL/src/$component"
    
    if download_file "$url" "$output" "curl"; then
        log_debug "Downloaded: $component"
        return 0
    else
        log_warning "Failed to download: $component"
        return 1
    fi
}

# ----------------------------
# 🏗️ INSTALLATION FUNCTIONS
# ----------------------------
create_directory_structure() {
    log_info "Creating directory structure..."
    
    local directories=(
        "$CONFIG_DIR"
        "$CONFIG_DIR/apps"
        "$LOG_DIR"
        "/var/backups/laravel"
        "/var/deployments"
        "/etc/nginx/sites-available"
        "/etc/nginx/sites-enabled"
    )
    
    for dir in "${directories[@]}"; do
        if mkdir -p "$dir" 2>/dev/null; then
            log_debug "Created: $dir"
        else
            log_error "Failed to create: $dir"
            return 1
        fi
    done
    
    # Set permissions
    chmod 755 "$CONFIG_DIR"
    chmod 750 "/var/backups/laravel"
    
    log_success "Directory structure created"
    return 0
}

install_main_script() {
    local method="$1"
    
    log_info "Installing main script..."
    
    # Backup existing installation
    backup_existing "$INSTALL_DIR/laravel-deploy"
    
    # Download and install main script
    if download_main_script "$method" "$INSTALL_DIR/laravel-deploy"; then
        # Create symlink for easy access
        ln -sf "$INSTALL_DIR/laravel-deploy" "/usr/local/bin/ldeploy" 2>/dev/null || true
        
        # Test the script
        if "$INSTALL_DIR/laravel-deploy" --version >/dev/null 2>&1; then
            log_success "Main script installed successfully"
            return 0
        else
            log_error "Script installation verification failed"
            return 1
        fi
    fi
    
    return 1
}

install_config_files() {
    log_info "Installing configuration files..."
    
    # Default global configuration
    if [[ ! -f "$CONFIG_DIR/config.conf" ]]; then
        cat > "$CONFIG_DIR/config.conf" << EOF
# Laravel Deploy - Global Configuration
# Generated: $(date)
# Version: $VERSION

$(for key in "${!DEFAULT_CONFIG[@]}"; do
    echo "$key=\"${DEFAULT_CONFIG[$key]}\""
done | sort)

# Logging Configuration
LOG_LEVEL="INFO"
LOG_ROTATION_DAYS=30
LOG_FORMAT="json"

# Backup Configuration
BACKUP_ENCRYPTION_ENABLED=0
BACKUP_CLOUD_STORAGE=0
BACKUP_TO_S3=0
BACKUP_TO_GOOGLE_DRIVE=0

# Monitoring Configuration
MONITORING_PORT=9100
HEALTH_CHECK_INTERVAL=60
ALERT_ENABLED=0

# Notification Configuration
NOTIFY_ON_SUCCESS=1
NOTIFY_ON_FAILURE=1
NOTIFY_ON_BACKUP=1
EOF
        log_debug "Created default configuration"
    fi
    
    # Sample app configuration
    if [[ ! -f "$CONFIG_DIR/apps/sample.conf" ]]; then
        cat > "$CONFIG_DIR/apps/sample.conf" << 'EOF'
# Sample Application Configuration
# Copy this file to your-app-name.conf and modify as needed

APP_NAME="myapp"
APP_PATH="/var/www/myapp"
DOMAIN="myapp.example.com"
PHP_VERSION="8.1"

# Database Configuration
DB_NAME="myapp_db"
DB_USER="myapp_user"
DB_PASSWORD=""
DB_HOST="localhost"
DB_PORT="3306"

# Deployment Configuration
REPO_URL="git@github.com:username/myapp.git"
BRANCH="main"
DEPLOYMENT_METHOD="git"
DEPLOYMENT_HOOKS_ENABLED=1

# SSL Configuration
ENABLE_SSL=1
SSL_EMAIL="admin@example.com"
SSL_AUTO_RENEW=1

# Queue Configuration
ENABLE_QUEUE=1
QUEUE_WORKERS=2
QUEUE_CONNECTION="redis"

# Backup Configuration
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30

# Monitoring
HEALTH_CHECK_ENABLED=1
HEALTH_CHECK_PATH="/health"
EOF
        log_debug "Created sample app configuration"
    fi
    
    # Nginx template
    if [[ ! -f "$CONFIG_DIR/templates/nginx-laravel.conf" ]]; then
        mkdir -p "$CONFIG_DIR/templates"
        
        cat > "$CONFIG_DIR/templates/nginx-laravel.conf" << 'NGINX'
# Laravel Nginx Configuration Template
# Variables: {DOMAIN}, {APP_PATH}, {PHP_VERSION}

server {
    listen 80;
    listen [::]:80;
    server_name {DOMAIN} www.{DOMAIN};
    
    root {APP_PATH}/public;
    index index.php index.html index.htm;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Laravel rewrite rules
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP handling
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php{PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    }
    
    # Deny access to sensitive files
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    # Static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX
        log_debug "Created Nginx template"
    fi
    
    log_success "Configuration files installed"
    return 0
}

install_systemd_service() {
    if [[ "$SKIP_SYSTEMD" == "1" ]]; then
        log_info "Skipping systemd service installation"
        return 0
    fi
    
    log_info "Installing systemd service..."
    
    # Backup existing service
    backup_existing "$SYSTEMD_DIR/laravel-deploy.service"
    backup_existing "$SYSTEMD_DIR/laravel-deploy.timer"
    
    # Create service file
    cat > "$SYSTEMD_DIR/laravel-deploy.service" << EOF
[Unit]
Description=Laravel Deploy Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=$INSTALL_DIR/laravel-deploy --maintenance
WorkingDirectory=/
StandardOutput=journal
StandardError=journal
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    # Create timer for automated maintenance
    cat > "$SYSTEMD_DIR/laravel-deploy.timer" << EOF
[Unit]
Description=Run Laravel Deploy Maintenance Daily
Requires=laravel-deploy.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    # Reload systemd
    if systemctl daemon-reload >/dev/null 2>&1; then
        systemctl enable laravel-deploy.timer >/dev/null 2>&1
        systemctl start laravel-deploy.timer >/dev/null 2>&1
        log_success "Systemd service installed and enabled"
        return 0
    else
        log_warning "Failed to install systemd service (systemctl not available)"
        return 1
    fi
}

install_cron_jobs() {
    if [[ "$SKIP_CRON" == "1" ]]; then
        log_info "Skipping cron jobs installation"
        return 0
    fi
    
    log_info "Installing cron jobs..."
    
    # Backup cron
    local cron_backup="$BACKUP_DIR/crontab.backup.$(date +%Y%m%d_%H%M%S)"
    crontab -l > "$cron_backup" 2>/dev/null || true
    
    # Create cron directory
    mkdir -p /etc/cron.d
    
    # Create backup cron
    cat > /etc/cron.d/laravel-deploy-backup << 'CRON'
# Laravel Deploy - Automated Backups
# Run daily at 2:00 AM
0 2 * * * root /usr/local/bin/laravel-deploy --backup-all --silent >> /var/log/laravel-deploy/cron.log 2>&1

# Weekly maintenance on Sundays at 3:00 AM
0 3 * * 0 root /usr/local/bin/laravel-deploy --maintenance --silent >> /var/log/laravel-deploy/cron.log 2>&1

# Monthly cleanup on 1st of month at 4:00 AM
0 4 1 * * root /usr/local/bin/laravel-deploy --cleanup --silent >> /var/log/laravel-deploy/cron.log 2>&1
CRON

    chmod 644 /etc/cron.d/laravel-deploy-backup
    
    log_success "Cron jobs installed"
    return 0
}

install_bash_completion() {
    if [[ "$SKIP_COMPLETION" == "1" ]]; then
        log_info "Skipping bash completion installation"
        return 0
    fi
    
    log_info "Installing bash completion..."
    
    local completion_dir="/etc/bash_completion.d"
    mkdir -p "$completion_dir"
    
    # Download or create completion script
    if download_file "$RAW_URL/scripts/completion.sh" "$completion_dir/laravel-deploy" "curl"; then
        log_debug "Downloaded completion script"
    else
        # Create basic completion
        cat > "$completion_dir/laravel-deploy" << 'COMPLETION'
_laravel_deploy_completion() {
    local cur prev words cword
    _init_completion || return

    case $prev in
        laravel-deploy|ldeploy)
            COMPREPLY=($(compgen -W "provision deploy backup restore ssl db:backup db:optimize list monitor status help version" -- "$cur"))
            ;;
        --app)
            # Auto-complete application names
            local apps
            apps=$(ls -1 /var/www/ 2>/dev/null | tr '\n' ' ')
            COMPREPLY=($(compgen -W "$apps" -- "$cur"))
            ;;
        *)
            case $cur in
                -*)
                    COMPREPLY=($(compgen -W "--help --version --silent --verbose --force --yes --no-cron --no-systemd --no-completion" -- "$cur"))
                    ;;
            esac
            ;;
    esac
}

complete -F _laravel_deploy_completion laravel-deploy
complete -F _laravel_deploy_completion ldeploy
COMPLETION
    fi
    
    # Source in current shell
    if [[ -f "$completion_dir/laravel-deploy" ]]; then
        source "$completion_dir/laravel-deploy" 2>/dev/null || true
        log_success "Bash completion installed"
    fi
    
    return 0
}

create_aliases() {
    log_info "Creating command aliases..."
    
    # Create aliases file
    cat > /etc/profile.d/laravel-deploy-aliases.sh << 'ALIASES'
# Laravel Deploy - Command Aliases
alias ldeploy='laravel-deploy'
alias ldeploy-provision='laravel-deploy provision'
alias ldeploy-deploy='laravel-deploy deploy'
alias ldeploy-backup='laravel-deploy backup'
alias ldeploy-restore='laravel-deploy restore'
alias ldeploy-ssl='laravel-deploy ssl'
alias ldeploy-status='laravel-deploy status'
alias ldeploy-monitor='laravel-deploy monitor'
alias ldeploy-logs='tail -f /var/log/laravel-deploy/*.log'
alias ldeploy-config='nano /etc/laravel-deploy/config.conf'
ALIASES

    # Source aliases in current shell
    source /etc/profile.d/laravel-deploy-aliases.sh 2>/dev/null || true
    
    log_success "Command aliases created"
    return 0
}

create_management_script() {
    log_info "Creating management utility..."
    
    cat > "$INSTALL_DIR/laravel-deploy-manage" << 'MANAGE'
#!/bin/bash
# Laravel Deploy - Management Utility

SCRIPT_NAME="laravel-deploy"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/laravel-deploy"
LOG_DIR="/var/log/laravel-deploy"

show_header() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     🚀 Laravel Deploy - Management Console              ║"
    echo "╠══════════════════════════════════════════════════════════╣"
}

show_footer() {
    echo "╚══════════════════════════════════════════════════════════╝"
}

case "${1:-}" in
    "status")
        show_header
        echo "║                                                      ║"
        echo "║  📊 System Status                                   ║"
        echo "║  • Script: $(which $SCRIPT_NAME)                    ║"
        echo "║  • Version: $($SCRIPT_NAME --version 2>/dev/null || echo "Unknown")"
        echo "║  • Config: $CONFIG_DIR                              ║"
        echo "║  • Logs: $LOG_DIR                                   ║"
        echo "║  • Systemd: $(systemctl is-active laravel-deploy.timer 2>/dev/null || echo "Not installed")"
        echo "║                                                      ║"
        show_footer
        ;;
        
    "logs")
        if [[ -d "$LOG_DIR" ]]; then
            tail -f "$LOG_DIR"/*.log
        else
            echo "No logs found in $LOG_DIR"
        fi
        ;;
        
    "config")
        ls -la "$CONFIG_DIR/" 2>/dev/null || echo "Config directory not found"
        ;;
        
    "reload")
        echo "Reloading services..."
        systemctl daemon-reload 2>/dev/null || true
        systemctl restart laravel-deploy.timer 2>/dev/null || true
        echo "Services reloaded"
        ;;
        
    "test")
        echo "Running tests..."
        $SCRIPT_NAME --version
        echo "Testing backup function..."
        $SCRIPT_NAME --backup-all --silent
        echo "Test completed"
        ;;
        
    "update")
        echo "Updating Laravel Deploy..."
        curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh | sudo bash -s -- --update
        ;;
        
    *)
        echo "Usage: $SCRIPT_NAME-manage {status|logs|config|reload|test|update}"
        echo ""
        echo "Commands:"
        echo "  status   - Show system status"
        echo "  logs     - View live logs"
        echo "  config   - List configuration files"
        echo "  reload   - Reload systemd services"
        echo "  test     - Run diagnostic tests"
        echo "  update   - Update to latest version"
        ;;
esac
MANAGE

    chmod +x "$INSTALL_DIR/laravel-deploy-manage"
    ln -sf "$INSTALL_DIR/laravel-deploy-manage" "/usr/local/bin/ldeploy-manage" 2>/dev/null || true
    
    log_success "Management utility created"
    return 0
}

# ----------------------------
# 🔍 VERIFICATION
# ----------------------------
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    local warnings=0
    
    # Check if main script is installed
    if [[ ! -f "$INSTALL_DIR/laravel-deploy" ]]; then
        log_error "Main script not found in $INSTALL_DIR"
        errors=$((errors+1))
    fi
    
    # Check if script is executable
    if [[ -f "$INSTALL_DIR/laravel-deploy" ]] && [[ ! -x "$INSTALL_DIR/laravel-deploy" ]]; then
        log_error "Main script is not executable"
        errors=$((errors+1))
    fi
    
    # Test script execution
    if version=$("$INSTALL_DIR/laravel-deploy" --version 2>/dev/null); then
        log_debug "Script version: $version"
    else
        log_error "Failed to execute main script"
        errors=$((errors+1))
    fi
    
    # Check configuration directory
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "Configuration directory not found"
        errors=$((errors+1))
    fi
    
    # Check log directory
    if [[ ! -d "$LOG_DIR" ]]; then
        log_warning "Log directory not found"
        warnings=$((warnings+1))
    fi
    
    # Check dependencies
    log_info "Checking runtime dependencies..."
    local runtime_deps=("nginx" "mariadb-server" "php-fpm")
    for dep in "${runtime_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii.*$dep"; then
            log_warning "Runtime dependency not installed: $dep"
            warnings=$((warnings+1))
        fi
    done
    
    # Generate verification report
    if [[ $errors -eq 0 ]]; then
        if [[ $warnings -eq 0 ]]; then
            log_success "Installation verified successfully"
            return 0
        else
            log_warning "Installation verified with $warnings warning(s)"
            return 0
        fi
    else
        log_error "Installation verification failed with $errors error(s)"
        return 1
    fi
}

generate_install_report() {
    local success="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    local report_file="$LOG_DIR/install-report-$timestamp.txt"
    
    cat > "$report_file" << EOF
===========================================
 Laravel Deploy - Installation Report
===========================================
Date: $(date)
Version: $VERSION
Status: $( [[ $success -eq 0 ]] && echo "SUCCESS" || echo "FAILED" )

System Information:
- OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)
- Kernel: $(uname -r)
- Architecture: $(uname -m)
- Hostname: $(hostname)

Installation Details:
- Install Directory: $INSTALL_DIR
- Config Directory: $CONFIG_DIR
- Log Directory: $LOG_DIR
- Backup Directory: $BACKUP_DIR

Features Installed:
$( [[ "$SKIP_SYSTEMD" != "1" ]] && echo "- Systemd Service: YES" || echo "- Systemd Service: NO" )
$( [[ "$SKIP_CRON" != "1" ]] && echo "- Cron Jobs: YES" || echo "- Cron Jobs: NO" )
$( [[ "$SKIP_COMPLETION" != "1" ]] && echo "- Bash Completion: YES" || echo "- Bash Completion: NO" )
- Management Utility: YES
- Command Aliases: YES

Backup Information:
$(if [[ -d "$BACKUP_DIR" ]]; then
    echo "- Backups created: $(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)"
else
    echo "- No backups created"
fi)

Next Steps:
1. Configure your applications in $CONFIG_DIR/apps/
2. Run 'laravel-deploy provision' to setup server
3. Add your Laravel applications to /var/www/
4. Run 'laravel-deploy deploy' to deploy apps

Quick Commands:
- ldeploy --help              # Show help
- ldeploy-manage status       # Check status
- ldeploy-logs               # View logs

Support:
- GitHub: $REPO_URL
- Issues: $REPO_URL/issues
EOF

    log_info "Installation report saved to: $report_file"
    
    if [[ $success -eq 0 ]]; then
        log_success "========================================"
        log_success "🚀 INSTALLATION COMPLETED SUCCESSFULLY!"
        log_success "========================================"
        
        if [[ "$SILENT_MODE" != "1" ]]; then
            echo ""
            echo "🎉 Laravel Deploy v$VERSION has been installed!"
            echo ""
            echo "📋 Quick Start:"
            echo "   1. Configure: nano $CONFIG_DIR/config.conf"
            echo "   2. Provision: laravel-deploy provision"
            echo "   3. Deploy: laravel-deploy deploy"
            echo ""
            echo "🔧 Management:"
            echo "   • ldeploy           - Main command"
            echo "   • ldeploy-manage    - Management console"
            echo "   • ldeploy-status    - Check system status"
            echo ""
            echo "📖 Documentation: $REPO_URL"
            echo ""
        fi
    else
        log_error "========================================"
        log_error "❌ INSTALLATION FAILED!"
        log_error "========================================"
        echo ""
        echo "Please check the logs above for errors."
        echo "You can try running with --verbose for more details."
        echo ""
        echo "For help, visit: $REPO_URL/issues"
    fi
}

# ----------------------------
# 🔄 UPDATE FUNCTION
# ----------------------------
update_installation() {
    log_info "Checking for updates..."
    
    # Get current version
    local current_version
    if [[ -f "$INSTALL_DIR/laravel-deploy" ]]; then
        current_version=$("$INSTALL_DIR/laravel-deploy" --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    else
        current_version="not installed"
    fi
    
    log_info "Current version: $current_version"
    log_info "Latest version: $VERSION"
    
    if [[ "$current_version" == "$VERSION" ]]; then
        log_success "Already on latest version"
        return 0
    fi
    
    if [[ "$current_version" == "not installed" ]]; then
        log_error "Laravel Deploy is not installed"
        return 1
    fi
    
    # Compare versions
    if [[ "$current_version" != "$VERSION" ]]; then
        log_info "Update available: $current_version -> $VERSION"
        
        if [[ "$AUTO_CONFIRM" != "1" ]]; then
            read -p "Update to v$VERSION? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n "$REPLY" ]]; then
                log_info "Update cancelled"
                return 0
            fi
        fi
        
        # Backup current installation
        log_info "Backing up current installation..."
        local backup_dir="$BACKUP_DIR/update-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        cp -r "$CONFIG_DIR" "$backup_dir/config" 2>/dev/null || true
        cp "$INSTALL_DIR/laravel-deploy" "$backup_dir/" 2>/dev/null || true
        
        # Re-run installation
        log_info "Updating to v$VERSION..."
        if perform_installation; then
            log_success "Update completed successfully"
            
            # Check for config migrations
            migrate_configuration "$backup_dir/config"
            
            return 0
        else
            log_error "Update failed, restoring from backup..."
            restore_backup "$backup_dir/laravel-deploy" "$INSTALL_DIR/laravel-deploy"
            cp -r "$backup_dir/config/"* "$CONFIG_DIR/" 2>/dev/null || true
            return 1
        fi
    fi
    
    return 0
}

migrate_configuration() {
    local old_config_dir="$1"
    
    if [[ ! -d "$old_config_dir" ]]; then
        return 0
    fi
    
    log_info "Migrating configuration..."
    
    # Check for old config format and migrate
    if [[ -f "$old_config_dir/config.conf" ]] && [[ ! -f "$CONFIG_DIR/config.conf" ]]; then
        cp "$old_config_dir/config.conf" "$CONFIG_DIR/config.conf"
        log_debug "Migrated main configuration"
    fi
    
    # Migrate app configurations
    if [[ -d "$old_config_dir/apps" ]]; then
        cp -r "$old_config_dir/apps/"* "$CONFIG_DIR/apps/" 2>/dev/null || true
        log_debug "Migrated app configurations"
    fi
    
    log_success "Configuration migration completed"
}

# ----------------------------
# 🗑️ UNINSTALL FUNCTION
# ----------------------------
uninstall_installation() {
    log_warning "This will remove Laravel Deploy from your system!"
    log_warning "This action cannot be undone!"
    echo ""
    
    if [[ "$AUTO_CONFIRM" != "1" ]]; then
        read -p "Are you sure you want to uninstall? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Uninstallation cancelled"
            exit 0
        fi
    fi
    
    log_info "Starting uninstallation..."
    
    # 1. Stop and disable services
    if systemctl is-active laravel-deploy.timer >/dev/null 2>&1; then
        systemctl stop laravel-deploy.timer
        systemctl disable laravel-deploy.timer
        log_debug "Stopped systemd timer"
    fi
    
    if systemctl is-active laravel-deploy.service >/dev/null 2>&1; then
        systemctl stop laravel-deploy.service
        systemctl disable laravel-deploy.service
        log_debug "Stopped systemd service"
    fi
    
    # 2. Remove main script
    if [[ -f "$INSTALL_DIR/laravel-deploy" ]]; then
        rm -f "$INSTALL_DIR/laravel-deploy"
        log_debug "Removed main script"
    fi
    
    # 3. Remove management script
    if [[ -f "$INSTALL_DIR/laravel-deploy-manage" ]]; then
        rm -f "$INSTALL_DIR/laravel-deploy-manage"
        rm -f "/usr/local/bin/ldeploy-manage"
        log_debug "Removed management script"
    fi
    
    # 4. Remove symlinks
    rm -f "/usr/local/bin/ldeploy"
    
    # 5. Remove configuration (optional)
    if [[ "$KEEP_CONFIG" != "1" ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            # Backup config before removal
            local backup_path="$BACKUP_DIR/config-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_path" -C "$CONFIG_DIR" . 2>/dev/null || true
            
            rm -rf "$CONFIG_DIR"
            log_debug "Removed configuration directory (backup: $backup_path)"
        fi
    else
        log_info "Keeping configuration directory: $CONFIG_DIR"
    fi
    
    # 6. Remove log directory (optional)
    if [[ "$KEEP_LOGS" != "1" ]] && [[ -d "$LOG_DIR" ]]; then
        # Backup logs before removal
        local log_backup="$BACKUP_DIR/logs-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$log_backup" -C "$LOG_DIR" . 2>/dev/null || true
        
        rm -rf "$LOG_DIR"
        log_debug "Removed log directory (backup: $log_backup)"
    fi
    
    # 7. Remove systemd files
    rm -f "$SYSTEMD_DIR/laravel-deploy.service"
    rm -f "$SYSTEMD_DIR/laravel-deploy.timer"
    systemctl daemon-reload 2>/dev/null || true
    log_debug "Removed systemd files"
    
    # 8. Remove cron jobs
    rm -f /etc/cron.d/laravel-deploy-backup
    log_debug "Removed cron jobs"
    
    # 9. Remove bash completion
    rm -f /etc/bash_completion.d/laravel-deploy
    log_debug "Removed bash completion"
    
    # 10. Remove aliases
    rm -f /etc/profile.d/laravel-deploy-aliases.sh
    log_debug "Removed aliases"
    
    log_success "========================================"
    log_success "✅ UNINSTALLATION COMPLETED SUCCESSFULLY!"
    log_success "========================================"
    
    echo ""
    echo "Note: The following were NOT removed:"
    echo "  • Your Laravel applications in /var/www/"
    echo "  • Your backups in /var/backups/laravel/"
    echo "  • Nginx/MariaDB/PHP configurations"
    echo ""
    echo "To completely clean up, you may also want to:"
    echo "  1. Remove web applications: rm -rf /var/www/*"
    echo "  2. Remove backups: rm -rf /var/backups/laravel"
    echo "  3. Uninstall services: apt remove nginx mariadb-server php-fpm"
}

# ----------------------------
# 🏗️ MAIN INSTALLATION
# ----------------------------
perform_installation() {
    local method="${1:-curl}"
    
    # 1. Create directory structure
    if ! create_directory_structure; then
        return 1
    fi
    
    # 2. Install main script
    if ! install_main_script "$method"; then
        return 1
    fi
    
    # 3. Install configuration files
    if ! install_config_files; then
        return 1
    fi
    
    # 4. Install systemd service
    if ! install_systemd_service; then
        log_warning "Continuing without systemd service"
    fi
    
    # 5. Install cron jobs
    if ! install_cron_jobs; then
        log_warning "Continuing without cron jobs"
    fi
    
    # 6. Install bash completion
    if ! install_bash_completion; then
        log_warning "Continuing without bash completion"
    fi
    
    # 7. Create aliases
    if ! create_aliases; then
        log_warning "Continuing without aliases"
    fi
    
    # 8. Create management utility
    if ! create_management_script; then
        log_warning "Continuing without management utility"
    fi
    
    return 0
}

# ----------------------------
# 🎯 MAIN FUNCTION
# ----------------------------
main() {
    # Parse arguments
    local SILENT_MODE=0
    local VERBOSE_MODE=0
    local FORCE_INSTALL=0
    local AUTO_CONFIRM=0
    local SKIP_SYSTEMD=0
    local SKIP_CRON=0
    local SKIP_COMPLETION=0
    local KEEP_CONFIG=0
    local KEEP_LOGS=0
    local ACTION="install"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                ACTION="install"
                shift
                ;;
            --update)
                ACTION="update"
                shift
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            --silent|-s)
                SILENT_MODE=1
                shift
                ;;
            --verbose|-v)
                VERBOSE_MODE=1
                shift
                ;;
            --force|-f)
                FORCE_INSTALL=1
                shift
                ;;
            --yes|-y)
                AUTO_CONFIRM=1
                shift
                ;;
            --no-systemd)
                SKIP_SYSTEMD=1
                shift
                ;;
            --no-cron)
                SKIP_CRON=1
                shift
                ;;
            --no-completion)
                SKIP_COMPLETION=1
                shift
                ;;
            --keep-config)
                KEEP_CONFIG=1
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version)
                echo "Laravel Deploy Installer v$VERSION"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Export variables for use in functions
    export SILENT_MODE VERBOSE_MODE FORCE_INSTALL AUTO_CONFIRM
    export SKIP_SYSTEMD SKIP_CRON SKIP_COMPLETION KEEP_CONFIG KEEP_LOGS
    
    # Show banner
    if [[ $SILENT_MODE -eq 0 ]]; then
        show_banner
    fi
    
    case $ACTION in
        "install")
            run_installation
            ;;
        "update")
            run_update
            ;;
        "uninstall")
            run_uninstallation
            ;;
    esac
}

run_installation() {
    # Initial checks
    check_root
    check_os
    check_internet
    
    if [[ $SILENT_MODE -eq 0 ]] && [[ $AUTO_CONFIRM -eq 0 ]]; then
        log_warning "This script will install Laravel Deploy v$VERSION"
        log_warning "It requires root privileges and will modify system files."
        echo ""
        read -p "Do you want to continue? [Y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n "$REPLY" ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        log_error "Failed to install dependencies"
        exit 1
    fi
    
    # Determine download method
    local method="curl"
    if command -v wget >/dev/null 2>&1; then
        method="wget"
    fi
    
    # Perform installation
    log_info "Starting installation process..."
    
    if perform_installation "$method"; then
        # Verify installation
        if verify_installation; then
            generate_install_report 0
            exit 0
        else
            generate_install_report 1
            exit 1
        fi
    else
        log_error "Installation failed"
        generate_install_report 1
        exit 1
    fi
}

run_update() {
    check_root
    check_os
    check_internet
    
    if ! check_dependencies; then
        exit 1
    fi
    
    update_installation
}

run_uninstallation() {
    check_root
    uninstall_installation
}

show_banner() {
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║     🚀 Laravel Deploy - Installation                    ║
╠══════════════════════════════════════════════════════════╣
║     Version: 5.0.0                                      ║
║     Author:  Nasrul                                     ║
║     GitHub:  github.com/nasrulll/laravel-deploy         ║
╚══════════════════════════════════════════════════════════╝

BANNER
}

show_help() {
    cat << 'HELP'
Laravel Deploy - Installation Script

Usage: bash <(curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh) [OPTIONS]

Options:
  --install                Install Laravel Deploy (default)
  --update                 Update existing installation
  --uninstall              Remove Laravel Deploy
  --silent, -s             Silent installation (no prompts)
  --verbose, -v            Verbose output
  --force, -f              Force installation on unsupported OS
  --yes, -y                Auto-confirm all prompts
  --no-systemd             Skip systemd service installation
  --no-cron                Skip cron jobs installation
  --no-completion          Skip bash completion installation
  --keep-config            Keep configuration when uninstalling
  --keep-logs              Keep logs when uninstalling
  --help, -h               Show this help message
  --version                Show version information

Examples:
  # Standard installation
  curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh | sudo bash
  
  # Silent installation
  curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh | sudo bash -s -- --install --silent
  
  # Update existing installation
  curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh | sudo bash -s -- --update
  
  # Uninstall
  curl -sSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/scripts/install.sh | sudo bash -s -- --uninstall --yes

Features Installed:
  ✅ Main deployment script
  ✅ Configuration management
  ✅ Systemd service (auto-maintenance)
  ✅ Cron jobs (automated backups)
  ✅ Bash completion
  ✅ Command aliases
  ✅ Management utility

Documentation: https://github.com/nasrulll/laravel-deploy
HELP
}

# ----------------------------
# 🚪 ENTRY POINT
# ----------------------------
# Trap for cleanup on exit
trap 'cleanup_on_exit' EXIT INT TERM

cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminated with error code: $exit_code"
    fi
    
    # Remove temporary files
    rm -rf /tmp/laravel-deploy-* 2>/dev/null || true
    
    exit $exit_code
}

# Run main function
main "$@"
