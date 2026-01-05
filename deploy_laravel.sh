#!/bin/bash
# ==============================================
# 🚀 Laravel Enterprise Deploy - Installer
# Version       : 1.0
# Author        : Nasrul Muiz
# GitHub        : https://github.com/nasrulmuiz/laravel-enterprise-deploy
# ==============================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_NAME="laravel-deploy"
SCRIPT_VERSION="3.0-fase1-fixed"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/laravel-deploy"
LOG_DIR="/var/log/laravel-deploy"
REPO_URL="https://github.com/nasrulll/laravel-deploy"
RAW_URL="https://raw.githubusercontent.com/nasrulll/laravel-deploy/main"
BACKUP_DIR="/var/backups/laravel-deploy-install"

# Functions
print_color() {
    echo -e "${2}${1}${NC}"
}

print_success() { print_color "✅ $1" "$GREEN"; }
print_error() { print_color "❌ $1" "$RED"; }
print_warning() { print_color "⚠️  $1" "$YELLOW"; }
print_info() { print_color "ℹ️  $1" "$BLUE"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    local deps=("curl" "wget" "git" "unzip")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_info "Installing missing dependencies: ${missing[*]}"
        apt update
        apt install -y "${missing[@]}"
    fi
}

backup_existing() {
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        print_info "Backing up existing installation..."
        mkdir -p "$BACKUP_DIR"
        cp "$INSTALL_DIR/$SCRIPT_NAME" "$BACKUP_DIR/$SCRIPT_NAME.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"
    fi
}

download_script() {
    local method="$1"
    
    print_info "Downloading Laravel Enterprise Deploy v$SCRIPT_VERSION..."
    
    case $method in
        "curl")
            curl -sSL "$RAW_URL/laravel-deploy.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
            ;;
        "wget")
            wget -q "$RAW_URL/laravel-deploy.sh" -O "$INSTALL_DIR/$SCRIPT_NAME"
            ;;
        "git")
            git clone "$REPO_URL" /tmp/laravel-deploy-tmp
            cp "/tmp/laravel-deploy-tmp/laravel-deploy.sh" "$INSTALL_DIR/$SCRIPT_NAME"
            rm -rf /tmp/laravel-deploy-tmp
            ;;
        *)
            print_error "Invalid download method"
            return 1
            ;;
    esac
    
    if [[ $? -eq 0 ]] && [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_success "Script downloaded successfully"
        return 0
    else
        print_error "Failed to download script"
        return 1
    fi
}

install_configs() {
    print_info "Installing configuration files..."
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    # Download sample configuration
    curl -sSL "$RAW_URL/config/sample.conf" -o "$CONFIG_DIR/sample.conf" 2>/dev/null || true
    
    # Create default configuration
    if [[ ! -f "$CONFIG_DIR/default.conf" ]]; then
        cat > "$CONFIG_DIR/default.conf" << 'EOF'
# Laravel Enterprise Deploy Configuration
# ==============================================

# Deployment Settings
ZERO_DOWNTIME_ENABLED=1
MAINTENANCE_MODE_ENABLED=1
ROLLBACK_ON_ERROR=1
MAX_BACKUPS=5
BACKUP_RETENTION_DAYS=30

# Security Settings
ENABLE_FIREWALL=1
ENABLE_FAIL2BAN=1
ENABLE_RATE_LIMITING=1
RATE_LIMIT_PER_IP=60

# Optimization Settings
REDIS_ENABLED=1
PHP_OPCACHE_ENABLED=1

# Monitoring Settings
ENABLE_MONITORING=1
MONITORING_PORT=9100

# PHP Versions
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
DEFAULT_PHP_VERSION="8.1"

# Directories
WWW_DIR="/var/www"
BACKUP_DIR="/var/backups/laravel"
RELEASES_DIR="/var/releases"

# Logging
LOG_LEVEL="INFO"
LOG_ROTATION_DAYS=30
EOF
        print_success "Default configuration created"
    fi
    
    # Create logrotate configuration
    cat > /etc/logrotate.d/laravel-deploy << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate $LOG_ROTATION_DAYS
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
    postrotate
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
}

setup_completion() {
    print_info "Setting up bash completion..."
    
    # Create bash completion script
    local comp_dir="/etc/bash_completion.d"
    mkdir -p "$comp_dir"
    
    cat > "$comp_dir/$SCRIPT_NAME" << 'EOF'
_laravel_deploy_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--help --version --install --update --uninstall --config --list-apps --backup-all --restore --monitor --status --silent --verbose --no-rollback --no-zero-downtime --app"
    
    case "${prev}" in
        --app)
            # Auto-complete application names from /var/www
            local apps=$(ls -1 /var/www/ 2>/dev/null | tr '\n' ' ')
            COMPREPLY=( $(compgen -W "${apps}" -- ${cur}) )
            return 0
            ;;
        *)
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
    esac
}
complete -F _laravel_deploy_completion laravel-deploy
EOF
    
    # Load completion in current shell
    if [[ -f "$comp_dir/$SCRIPT_NAME" ]]; then
        source "$comp_dir/$SCRIPT_NAME" 2>/dev/null || true
    fi
}

create_systemd_service() {
    print_info "Creating systemd service for scheduled deployments..."
    
    cat > /etc/systemd/system/laravel-deploy.service << EOF
[Unit]
Description=Laravel Enterprise Deploy Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=$INSTALL_DIR/$SCRIPT_NAME --silent
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/laravel-deploy.timer << EOF
[Unit]
Description=Run Laravel Deploy Daily
Requires=laravel-deploy.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    print_success "Systemd service created"
}

setup_cron() {
    print_info "Setting up cron job for automatic backups..."
    
    # Create daily backup cron
    local cron_file="/etc/cron.d/laravel-deploy-backup"
    cat > "$cron_file" << EOF
# Laravel Enterprise Deploy - Automatic Backups
# Run daily at 2:00 AM
0 2 * * * root $INSTALL_DIR/$SCRIPT_NAME --backup-all --silent >> $LOG_DIR/cron.log 2>&1

# Weekly optimization every Sunday at 3:00 AM
0 3 * * 0 root $INSTALL_DIR/$SCRIPT_NAME --optimize --silent >> $LOG_DIR/cron.log 2>&1

# Monthly cleanup on 1st of month at 4:00 AM
0 4 1 * * root $INSTALL_DIR/$SCRIPT_NAME --cleanup --silent >> $LOG_DIR/cron.log 2>&1
EOF
    
    chmod 644 "$cron_file"
    print_success "Cron jobs configured"
}

create_management_script() {
    print_info "Creating management utility..."
    
    cat > "$INSTALL_DIR/$SCRIPT_NAME-manage" << 'EOF'
#!/bin/bash
# Laravel Enterprise Deploy - Management Utility

SCRIPT_NAME="laravel-deploy"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/laravel-deploy"
LOG_DIR="/var/log/laravel-deploy"

case "$1" in
    "status")
        echo "=== Laravel Enterprise Deploy Status ==="
        echo "Script: $(which $SCRIPT_NAME)"
        echo "Version: $($SCRIPT_NAME --version 2>/dev/null || echo "Unknown")"
        echo "Config Directory: $CONFIG_DIR"
        echo "Log Directory: $LOG_DIR"
        echo "Last Run: $(stat -c %y $INSTALL_DIR/$SCRIPT_NAME 2>/dev/null || echo "Unknown")"
        echo "Systemd Service: $(systemctl is-active laravel-deploy.timer 2>/dev/null || echo "Not installed")"
        ;;
    "logs")
        tail -f "$LOG_DIR"/*.log 2>/dev/null || echo "No logs found"
        ;;
    "config")
        ls -la "$CONFIG_DIR/" 2>/dev/null || echo "Config directory not found"
        ;;
    "reload")
        systemctl daemon-reload
        systemctl restart laravel-deploy.timer 2>/dev/null || true
        echo "Service reloaded"
        ;;
    "test")
        echo "Testing script execution..."
        $SCRIPT_NAME --version
        echo "Testing backup..."
        $SCRIPT_NAME --backup-all --silent
        echo "Test completed"
        ;;
    *)
        echo "Usage: $SCRIPT_NAME-manage {status|logs|config|reload|test}"
        ;;
esac
EOF
    
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME-manage"
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME-manage" "/usr/local/bin/ldeploy-manage"
}

create_aliases() {
    print_info "Creating command aliases..."
    
    # Create alias file
    cat > /etc/profile.d/laravel-deploy-aliases.sh << 'EOF'
# Laravel Enterprise Deploy Aliases
alias ldeploy='laravel-deploy'
alias ldeploy-status='laravel-deploy --status'
alias ldeploy-backup='laravel-deploy --backup-all'
alias ldeploy-list='laravel-deploy --list-apps'
alias ldeploy-monitor='laravel-deploy --monitor'
alias ldeploy-logs='tail -f /var/log/laravel-deploy/*.log'
alias ldeploy-config='nano /etc/laravel-deploy/default.conf'
EOF
    
    # Source aliases in current shell
    source /etc/profile.d/laravel-deploy-aliases.sh 2>/dev/null || true
}

verify_installation() {
    print_info "Verifying installation..."
    
    local errors=0
    
    # Check if script is installed
    if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        print_error "Script not found in $INSTALL_DIR"
        errors=$((errors+1))
    fi
    
    # Check if script is executable
    if [[ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        print_error "Script is not executable"
        errors=$((errors+1))
    fi
    
    # Test script version
    if version=$("$INSTALL_DIR/$SCRIPT_NAME" --version 2>/dev/null); then
        print_success "Script version: $version"
    else
        print_error "Failed to get script version"
        errors=$((errors+1))
    fi
    
    # Check dependencies
    if "$INSTALL_DIR/$SCRIPT_NAME" --check-deps 2>/dev/null | grep -q "Missing"; then
        print_warning "Some dependencies are missing"
    else
        print_success "All dependencies are available"
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_success "Installation verified successfully"
        return 0
    else
        print_error "Installation verification failed with $errors error(s)"
        return 1
    fi
}

show_banner() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║     🚀 Laravel Enterprise Deploy - Installation          ║
╠══════════════════════════════════════════════════════════╣
║     Version: 3.0-fase1-fixed                             ║
║     Author:  Nasrul Muiz                                 ║
║     GitHub:  github.com/nasrulll/laravel-deploy  ║
╚══════════════════════════════════════════════════════════╝

EOF
}

show_help() {
    cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --install          Install Laravel Enterprise Deploy
  --update           Update to latest version
  --uninstall        Remove installation
  --silent           Silent installation (no prompts)
  --no-config        Skip configuration setup
  --no-cron          Skip cron job setup
  --no-systemd       Skip systemd service setup
  --force            Force installation (overwrite existing)
  --help             Show this help message
  --version          Show version information

Examples:
  ./install.sh --install          # Interactive installation
  ./install.sh --install --silent # Silent installation
  ./install.sh --update           # Update existing installation
  ./install.sh --uninstall        # Remove installation
EOF
}

install_main() {
    local silent_mode=0
    local skip_config=0
    local skip_cron=0
    local skip_systemd=0
    local force_install=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --silent) silent_mode=1 ;;
            --no-config) skip_config=1 ;;
            --no-cron) skip_cron=1 ;;
            --no-systemd) skip_systemd=1 ;;
            --force) force_install=1 ;;
            *) ;;
        esac
        shift
    done
    
    show_banner
    
    if [[ $silent_mode -eq 0 ]]; then
        print_warning "This script will install Laravel Enterprise Deploy."
        print_warning "It requires root privileges and will modify system files."
        echo
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled"
            exit 0
        fi
    fi
    
    # Check root privileges
    check_root
    
    # Check dependencies
    check_dependencies
    
    # Backup existing
    backup_existing
    
    # Download script
    print_info "Select download method:"
    print_info "1) curl (recommended)"
    print_info "2) wget"
    print_info "3) git clone"
    
    local method="curl"
    if [[ $silent_mode -eq 0 ]]; then
        read -p "Enter choice [1]: " choice
        case $choice in
            1|"") method="curl" ;;
            2) method="wget" ;;
            3) method="git" ;;
            *) method="curl" ;;
        esac
    fi
    
    if ! download_script "$method"; then
        print_error "Installation failed"
        exit 1
    fi
    
    # Install configurations
    if [[ $skip_config -eq 0 ]]; then
        install_configs
    fi
    
    # Setup bash completion
    setup_completion
    
    # Setup systemd service
    if [[ $skip_systemd -eq 0 ]]; then
        create_systemd_service
    fi
    
    # Setup cron jobs
    if [[ $skip_cron -eq 0 ]]; then
        setup_cron
    fi
    
    # Create management script
    create_management_script
    
    # Create aliases
    create_aliases
    
    # Verify installation
    if verify_installation; then
        print_success "========================================"
        print_success "🚀 INSTALLATION COMPLETED SUCCESSFULLY!"
        print_success "========================================"
        echo
        print_info "Quick Start:"
        echo "  laravel-deploy --help              # Show help"
        echo "  laravel-deploy --list-apps         # List applications"
        echo "  laravel-deploy --backup-all        # Backup all apps"
        echo "  ldeploy-manage status              # Check status"
        echo
        print_info "Configuration:"
        echo "  Config files: /etc/laravel-deploy/"
        echo "  Log files: /var/log/laravel-deploy/"
        echo
        print_info "Aliases Available:"
        echo "  ldeploy        - laravel-deploy"
        echo "  ldeploy-status - Check deployment status"
        echo "  ldeploy-backup - Backup all applications"
        echo "  ldeploy-logs   - View logs"
        echo
        print_warning "Please review the configuration at: /etc/laravel-deploy/default.conf"
        
        # Test run
        if [[ $silent_mode -eq 0 ]]; then
            read -p "Do you want to test the installation? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Running test..."
                "$INSTALL_DIR/$SCRIPT_NAME" --version
                echo "Test completed!"
            fi
        fi
    else
        print_error "Installation completed with errors"
        exit 1
    fi
}

update_installation() {
    show_banner
    print_info "Updating Laravel Enterprise Deploy..."
    
    check_root
    
    # Backup current version
    backup_existing
    
    # Download latest version
    if download_script "curl"; then
        print_success "Update completed successfully"
        
        # Reload systemd if exists
        if [[ -f /etc/systemd/system/laravel-deploy.service ]]; then
            systemctl daemon-reload
            systemctl restart laravel-deploy.timer 2>/dev/null || true
        fi
        
        # Show new version
        "$INSTALL_DIR/$SCRIPT_NAME" --version
    else
        print_error "Update failed"
        exit 1
    fi
}

uninstall_installation() {
    show_banner
    print_warning "This will remove Laravel Enterprise Deploy from your system."
    print_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to uninstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Uninstallation cancelled"
        exit 0
    fi
    
    check_root
    
    print_info "Removing Laravel Enterprise Deploy..."
    
    # Remove main script
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        rm -f "$INSTALL_DIR/$SCRIPT_NAME"
        print_success "Removed main script"
    fi
    
    # Remove management script
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME-manage" ]]; then
        rm -f "$INSTALL_DIR/$SCRIPT_NAME-manage"
        rm -f "/usr/local/bin/ldeploy-manage"
        print_success "Removed management script"
    fi
    
    # Remove configuration files
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        print_success "Removed configuration files"
    fi
    
    # Remove systemd service
    if [[ -f /etc/systemd/system/laravel-deploy.service ]]; then
        systemctl stop laravel-deploy.timer 2>/dev/null || true
        systemctl disable laravel-deploy.timer 2>/dev/null || true
        rm -f /etc/systemd/system/laravel-deploy.service
        rm -f /etc/systemd/system/laravel-deploy.timer
        systemctl daemon-reload
        print_success "Removed systemd service"
    fi
    
    # Remove cron jobs
    if [[ -f /etc/cron.d/laravel-deploy-backup ]]; then
        rm -f /etc/cron.d/laravel-deploy-backup
        print_success "Removed cron jobs"
    fi
    
    # Remove bash completion
    if [[ -f /etc/bash_completion.d/$SCRIPT_NAME ]]; then
        rm -f /etc/bash_completion.d/$SCRIPT_NAME
        print_success "Removed bash completion"
    fi
    
    # Remove aliases
    if [[ -f /etc/profile.d/laravel-deploy-aliases.sh ]]; then
        rm -f /etc/profile.d/laravel-deploy-aliases.sh
        print_success "Removed aliases"
    fi
    
    # Remove logrotate config
    if [[ -f /etc/logrotate.d/laravel-deploy ]]; then
        rm -f /etc/logrotate.d/laravel-deploy
        print_success "Removed logrotate configuration"
    fi
    
    print_success "========================================"
    print_success "✅ UNINSTALLATION COMPLETED SUCCESSFULLY!"
    print_success "========================================"
    echo
    print_info "Note: Log files in $LOG_DIR were not removed"
    print_info "Note: Backups in /var/backups/laravel were not removed"
    print_info "Note: Application files in /var/www were not removed"
}

# Main execution
case "${1:-}" in
    "--install")
        install_main "${@:2}"
        ;;
    "--update")
        update_installation
        ;;
    "--uninstall")
        uninstall_installation
        ;;
    "--help"|"-h")
        show_help
        ;;
    "--version"|"-v")
        echo "Laravel Enterprise Deploy Installer v1.0"
        ;;
    *)
        show_help
        exit 1
        ;;
esac