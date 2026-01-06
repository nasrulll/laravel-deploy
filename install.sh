#!/bin/bash
# ==============================================
# 🚀 Laravel Deploy Pro - Installation Script
# Author: Nasrul
# GitHub: https://github.com/nasrulll/laravel-deploy
# Description: Anti-fail installation script for Laravel Deploy Pro
# ==============================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
readonly SCRIPT_NAME="laravel-deploy"
readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/laravel-deploy"
readonly LOG_DIR="/var/log/laravel-deploy"
readonly BACKUP_DIR="/var/backups/laravel"
readonly SCRIPT_URL="https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/laravel-deploy.sh"
readonly LATEST_VERSION_URL="https://api.github.com/repos/nasrulll/laravel-deploy/releases/latest"

# Functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

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
    
    eval "$cmd" > /tmp/install-spinner.log 2>&1 &
    local pid=$!
    
    spinner $pid "$msg"
    
    wait $pid
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Failed: $msg"
        [[ -f /tmp/install-spinner.log ]] && cat /tmp/install-spinner.log
        return $exit_code
    fi
    
    return 0
}

check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Unsupported operating system"
        return 1
    fi
    
    . /etc/os-release
    
    # Supported OS
    local supported_os=("ubuntu" "debian" "centos" "rhel" "rocky" "almalinux")
    local os_supported=0
    
    for os in "${supported_os[@]}"; do
        if [[ "$ID" == "$os" ]]; then
            os_supported=1
            break
        fi
    done
    
    if [[ $os_supported -eq 0 ]]; then
        warning "OS $ID may not be fully supported. Continuing anyway..."
    fi
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "aarch64" ]]; then
        warning "Architecture $arch may not be fully supported"
    fi
    
    # Check disk space
    local disk_space=$(df / | tail -1 | awk '{print $4}')
    if [[ $disk_space -lt 1048576 ]]; then
        warning "Low disk space (less than 1GB free)"
    fi
    
    # Check memory
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $mem_total -lt 1048576 ]]; then
        warning "Low memory (less than 1GB)"
    fi
    
    success "System requirements check passed"
}

check_internet() {
    log "Checking internet connection..."
    
    # Try multiple endpoints
    local endpoints=(
        "https://github.com"
        "https://google.com"
        "https://raw.githubusercontent.com"
        "https://deb.nodesource.com"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -s --max-time 5 --head "$endpoint" >/dev/null 2>&1; then
            success "Internet connection OK"
            return 0
        fi
    done
    
    # Try with wget if curl fails
    for endpoint in "${endpoints[@]}"; do
        if wget -q --timeout=5 --tries=1 --spider "$endpoint" >/dev/null 2>&1; then
            success "Internet connection OK (via wget)"
            return 0
        fi
    done
    
    error "No internet connection. Please check your network."
    return 1
}

install_dependencies() {
    log "Installing dependencies..."
    
    . /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            run_with_spinner "apt-get update -qq" "Updating package list"
            
            local deps=("curl" "wget" "git" "gnupg" "ca-certificates" "lsb-release")
            local missing_deps=()
            
            for dep in "${deps[@]}"; do
                if ! dpkg -l | grep -q "^ii  $dep "; then
                    missing_deps+=("$dep")
                fi
            done
            
            if [[ ${#missing_deps[@]} -gt 0 ]]; then
                run_with_spinner "apt-get install -y -qq ${missing_deps[*]}" "Installing dependencies"
            fi
            ;;
            
        centos|rhel|rocky|almalinux)
            if [[ "$ID" == "centos" && "$VERSION_ID" == "7" ]]; then
                # Enable EPEL for CentOS 7
                run_with_spinner "yum install -y -q epel-release" "Enabling EPEL"
            fi
            
            local deps=("curl" "wget" "git" "gnupg" "ca-certificates")
            run_with_spinner "yum install -y -q ${deps[*]}" "Installing dependencies"
            ;;
            
        *)
            warning "Unknown OS: $ID. Trying to install dependencies anyway..."
            ;;
    esac
    
    success "Dependencies installed"
}

download_script() {
    log "Downloading Laravel Deploy Pro..."
    
    local temp_script="/tmp/laravel-deploy-temp.sh"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -fsSL "$SCRIPT_URL" -o "$temp_script" 2>/dev/null; then
            success "Script downloaded successfully"
            
            # Verify script is not empty
            if [[ ! -s "$temp_script" ]]; then
                error "Downloaded script is empty"
                return 1
            fi
            
            # Verify it's a bash script
            if ! head -1 "$temp_script" | grep -q "^#!/bin/bash"; then
                error "Downloaded file is not a bash script"
                return 1
            fi
            
            chmod +x "$temp_script"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        warning "Download failed, retrying ($retry_count/$max_retries)..."
        sleep 2
    done
    
    # Try alternative download method
    warning "Trying alternative download method..."
    if wget -q "$SCRIPT_URL" -O "$temp_script" 2>/dev/null; then
        chmod +x "$temp_script"
        return 0
    fi
    
    error "Failed to download script after $max_retries attempts"
    return 1
}

check_version() {
    log "Checking for updates..."
    
    if curl -fsSL "$LATEST_VERSION_URL" -o /tmp/latest_version.json 2>/dev/null; then
        local latest_version=$(grep -o '"tag_name": "[^"]*"' /tmp/latest_version.json | cut -d'"' -f4)
        if [[ -n "$latest_version" ]]; then
            log "Latest version: $latest_version"
            # You can add version comparison logic here
        fi
    fi
    
    rm -f /tmp/latest_version.json
}

setup_environment() {
    log "Setting up environment..."
    
    # Create directories
    run_with_spinner "mkdir -p $CONFIG_DIR $LOG_DIR $BACKUP_DIR" "Creating directories"
    
    # Create initial configuration
    if [[ ! -f "$CONFIG_DIR/config.conf" ]]; then
        cat > "$CONFIG_DIR/config.conf" << EOF
# Laravel Deploy Pro Configuration
# Generated: $(date)

WWW_DIR="/var/www"
PHP_VERSION="8.2"
MYSQL_ROOT_PASS="$(openssl rand -base64 32)"
REDIS_ENABLED="1"
SSL_ENABLED="1"
AUTO_BACKUP="1"
BACKUP_RETENTION="30"
MAX_BACKUPS="5"
ENABLE_MONITORING="1"
DEPLOYMENT_TIMEOUT="300"
ZERO_DOWNTIME="1"
ENABLE_FIREWALL="1"
ENABLE_FAIL2BAN="1"
TIMEZONE="UTC"
SWAP_SIZE="2G"
EOF
        chmod 600 "$CONFIG_DIR/config.conf"
    fi
    
    # Install the script
    if [[ -f "/tmp/laravel-deploy-temp.sh" ]]; then
        cp "/tmp/laravel-deploy-temp.sh" "$INSTALL_DIR/$SCRIPT_NAME"
        chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
    fi
    
    # Create symlink for easier access
    if [[ ! -L "/usr/bin/$SCRIPT_NAME" ]]; then
        ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "/usr/bin/$SCRIPT_NAME"
    fi
    
    # Create log rotation
    cat > /etc/logrotate.d/laravel-deploy << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
    postrotate
        [ -f /var/run/laravel-deploy.pid ] && kill -USR1 \$(cat /var/run/laravel-deploy.pid) 2>/dev/null || true
    endscript
}
EOF
    
    success "Environment setup completed"
}

create_uninstall_script() {
    cat > "/usr/local/bin/uninstall-laravel-deploy.sh" << 'EOF'
#!/bin/bash
# Uninstall Laravel Deploy Pro

set -e

echo "⚠️  This will uninstall Laravel Deploy Pro"
read -p "Are you sure? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Remove main script
rm -f /usr/local/bin/laravel-deploy
rm -f /usr/bin/laravel-deploy

# Remove configuration (ask first)
read -p "Remove configuration files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /etc/laravel-deploy
fi

# Remove logs (ask first)
read -p "Remove log files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /var/log/laravel-deploy
fi

# Remove backups (ask first)
read -p "Remove backup files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /var/backups/laravel
fi

# Remove cron jobs
crontab -l | grep -v "laravel-deploy" | crontab -

# Remove logrotate config
rm -f /etc/logrotate.d/laravel-deploy

# Remove this uninstall script
rm -f /usr/local/bin/uninstall-laravel-deploy.sh

echo "✅ Laravel Deploy Pro has been uninstalled."
EOF
    
    chmod +x "/usr/local/bin/uninstall-laravel-deploy.sh"
}

create_example_config() {
    cat > "$CONFIG_DIR/example-app.conf" << 'EOF'
# Example Application Configuration
# Copy this file to /etc/laravel-deploy/apps/your-app.conf

APP_NAME="your-app"
APP_PATH="/var/www/your-app"
PHP_VERSION="8.2"
DOMAIN="yourdomain.com"
ENVIRONMENT="production"

# Database Configuration
DB_NAME="your_app_db"
DB_USER="your_app_user"
DB_PASSWORD="$(openssl rand -base64 32)"

# SSL Configuration
ENABLE_SSL=1
SSL_EMAIL="admin@yourdomain.com"

# Queue Configuration
ENABLE_QUEUE=1
QUEUE_WORKERS=2
ENABLE_SCHEDULER=1

# Backup Configuration
BACKUP_SCHEDULE="0 2 * * *"

# Deployment Configuration
DEPLOYMENT_METHOD="git"
REPO_URL="git@github.com:username/repository.git"
BRANCH="main"
DEPLOYMENT_HOOKS_ENABLED=1

# Security Configuration
ENABLE_2FA=0
ALLOWED_IPS=""
EOF
}

show_summary() {
    echo ""
    echo "==========================================="
    echo "    🚀 INSTALLATION COMPLETED SUCCESSFULLY"
    echo "==========================================="
    echo ""
    echo "📦 What was installed:"
    echo "   ✓ Main script: /usr/local/bin/laravel-deploy"
    echo "   ✓ Configuration: /etc/laravel-deploy/"
    echo "   ✓ Logs: /var/log/laravel-deploy/"
    echo "   ✓ Backups: /var/backups/laravel/"
    echo ""
    echo "🔧 Available commands:"
    echo "   laravel-deploy provision     # Setup your server"
    echo "   laravel-deploy deploy        # Deploy applications"
    echo "   laravel-deploy backup        # Backup applications"
    echo "   laravel-deploy monitor       # Check system status"
    echo "   laravel-deploy help          # Show help"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Run: laravel-deploy provision"
    echo "   2. Setup your first app: laravel-deploy setup-app <name> <domain>"
    echo "   3. Deploy: laravel-deploy deploy <app-name>"
    echo ""
    echo "❌ To uninstall:"
    echo "   sudo /usr/local/bin/uninstall-laravel-deploy.sh"
    echo ""
    echo "📚 Documentation:"
    echo "   https://github.com/nasrulll/laravel-deploy"
    echo ""
    echo "==========================================="
}

main() {
    echo -e "${BOLD}${CYAN}"
    echo "==========================================="
    echo "   Laravel Deploy Pro - Installation"
    echo "==========================================="
    echo -e "${NC}"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        echo "Try: sudo bash install.sh"
        exit 1
    fi
    
    # Run installation steps
    check_requirements
    check_internet
    install_dependencies
    download_script
    check_version
    setup_environment
    create_uninstall_script
    create_example_config
    
    # Verify installation
    if command -v laravel-deploy >/dev/null 2>&1; then
        success "Installation verified successfully"
    else
        error "Installation verification failed"
        exit 1
    fi
    
    show_summary
}

# Handle errors
trap 'error "Installation failed on line $LINENO"; exit 1' ERR

# Run main function
main "$@"