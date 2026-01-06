#!/bin/bash
# ==============================================
# 🚀 Laravel Deploy - Installation Script
# Version       : 5.0.0
# Author        : Nasrul
# GitHub        : https://github.com/nasrulll/laravel-deploy
# Description   : One-line installer for Laravel Deploy
# ==============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Version
VERSION="5.0-production"
REPO_URL="https://github.com/nasrulll/laravel-deploy"

log() {
    echo -e "${BLUE}[Laravel Deploy]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

log "🚀 Installing Laravel Deploy Pro v$VERSION"

# Download main script
log "Downloading script..."
curl -sSL -o /tmp/laravel-deploy.sh \
  "$REPO_URL/raw/main/laravel-deploy.sh"

# Make executable
chmod +x /tmp/laravel-deploy.sh

# Install to system
mv /tmp/laravel-deploy.sh /usr/local/bin/laravel-deploy

# Create directories
log "Creating directories..."
mkdir -p /etc/laravel-deploy \
         /var/log/laravel-deploy \
         /var/backups/laravel \
         /var/deployments \
         /etc/ssl/laravel

# Create default config if doesn't exist
if [[ ! -f /etc/laravel-deploy/config.conf ]]; then
    log "Creating default configuration..."
    cat > /etc/laravel-deploy/config.conf << EOF
# Laravel Deploy Configuration
# Generated: $(date)

WWW_DIR="/var/www"
PHP_VERSION="8.2"
MYSQL_ROOT_PASS=""
REDIS_ENABLED="1"
SSL_ENABLED="1"
AUTO_BACKUP="1"
BACKUP_RETENTION="30"
MAX_BACKUPS="5"
ENABLE_MONITORING="1"
DEPLOYMENT_TIMEOUT="300"
ZERO_DOWNTIME="1"
BACKUP_ENCRYPTION_KEY=""
EOF
fi

# Create sample app config
mkdir -p /etc/laravel-deploy/apps
if [[ ! -f /etc/laravel-deploy/apps/example.conf ]]; then
    cat > /etc/laravel-deploy/apps/example.conf << 'EOF'
# Example Application Configuration
# Copy to /etc/laravel-deploy/apps/your-app.conf

APP_NAME="example-app"
APP_PATH="/var/www/example-app"
PHP_VERSION="8.2"
DOMAIN="example.com"
ENVIRONMENT="production"
DB_NAME="example_db"
DB_USER="example_user"
DB_PASSWORD=""
ENABLE_SSL=1
SSL_EMAIL="admin@example.com"
ENABLE_QUEUE=1
QUEUE_WORKERS=2
ENABLE_SCHEDULER=1
BACKUP_SCHEDULE="0 2 * * *"
DEPLOYMENT_METHOD="git"
REPO_URL="https://github.com/username/repo.git"
BRANCH="main"
DEPLOYMENT_HOOKS_ENABLED=1
EOF
fi

# Set permissions
chmod 750 /var/log/laravel-deploy
chmod 750 /var/backups/laravel

success "Installation completed!"
echo ""
echo "📦 What's next?"
echo "   1. Edit configuration: sudo nano /etc/laravel-deploy/config.conf"
echo "   2. Provision server:   sudo laravel-deploy provision"
echo "   3. Deploy application: sudo laravel-deploy deploy"
echo ""
echo "📚 Documentation: $REPO_URL"
echo "❓ Help: sudo laravel-deploy help"
