#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}⚠️  WARNING: This will remove Laravel Deploy Pro${NC}"
read -p "Are you sure? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo "Removing Laravel Deploy Pro..."

# Remove main script
rm -f /usr/local/bin/laravel-deploy

# Remove cron jobs
crontab -l | grep -v 'laravel-deploy' | crontab - || true

# Ask about removing data
read -p "Remove configuration files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /etc/laravel-deploy
    echo "Configuration removed."
fi

read -p "Remove backups? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /var/backups/laravel
    echo "Backups removed."
fi

read -p "Remove logs? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /var/log/laravel-deploy
    echo "Logs removed."
fi

echo -e "${GREEN}✅ Uninstall completed!${NC}"
