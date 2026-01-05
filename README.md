# 🌟 Laravel Multi-Domain Deployment Script 🚀

![Laravel](https://img.shields.io/badge/Laravel-8-red?style=for-the-badge)
![Debian](https://img.shields.io/badge/Debian-11-blue?style=for-the-badge)
![PHP](https://img.shields.io/badge/PHP-7.4-purple?style=for-the-badge)
![MariaDB](https://img.shields.io/badge/MariaDB-10.5-green?style=for-the-badge)
![Nginx](https://img.shields.io/badge/Nginx-stable-orange?style=for-the-badge)
![GitHub](https://img.shields.io/badge/GitHub-repo-black?style=for-the-badge)

---

## 📖 Overview

Welcome to **Laravel Multi-Domain Deployment Script**! 🎉  

This ultra-automated script makes deploying **multiple Laravel apps** on a single **Debian/Ubuntu server** a breeze:  

✨ **Features:**
- Multi-domain Laravel apps  
- Auto-detect PHP & MariaDB versions  
- Auto-create DB per app & user  
- Auto Nginx vhost configuration  
- Permission fix for WinSCP / FTP uploads  
- Install ionCube loader for PHP 7.4  
- Emoji & interactive prompts (Visual Mode)  
- Silent / Ultra-Automated mode  
- Logging at `/var/log/laravel_ultra_deploy.log`  

> ⚡ Visual mode is fully interactive and fun, Silent mode is ultra-automated for cron jobs!

---

## 🎯 Features Comparison

| Feature | Visual Mode 🎨 | Silent Mode 🤖 |
|---------|----------------|----------------|
| Scan `/var/www/` for Laravel apps | ✅ | ✅ |
| Auto create DB & user | ✅ (shows password) | ✅ |
| Permission fix (`chown` + `chmod`) | ✅ | ✅ |
| Auto Nginx vhost per app | ✅ | ✅ |
| Install PHP 7.4, MariaDB, Nginx | ✅ | ✅ |
| Install ionCube loader 7.4 | ✅ | ✅ |
| Logging | ✅ | ✅ |
| Emoji & interactive prompts | ✅ | ❌ |
| Ultra-Automated Deployment | ❌ | ✅ |

---

## 🖥️ Server Requirements

- OS: Debian 11 / Ubuntu 20+  
- Laravel Apps Folder: `/var/www/`  
- User: Must have `sudo` privileges  
- Internet: Required for dependency installation  

---

## 🚀 Deployment Instructions

### 1️⃣ Visual / Interactive Mode

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/deploy_laravel.sh)"

✅ Prompts with emojis

✅ Choose PHP version, SSL options, number of apps

🚀 Perfect for first-time deployment



2️⃣ Silent / Ultra-Automated Mode

sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/deploy_laravel.sh)" -- --silent >> /var/log/laravel_ultra_deploy.log 2>&1

✅ Auto detects all options

✅ Full log at /var/log/laravel_ultra_deploy.log

🤖 Ideal for cron jobs or automated deployment


🗄️ Database Auto-Creation

For each Laravel app:


App:        myapp
DB Name:    myapp_db
DB User:    myapp_user
DB Password: random_secure_password

Password shown in Visual Mode, logged in silent mode
Fully automated creation

⚙️ Nginx Virtual Hosts

Script automatically generates a virtual host per app:

/etc/nginx/sites-available/<appname>.conf
/etc/nginx/sites-enabled/<appname>.conf
Default domain: <appname>.local

Can be customized as needed

🔧 Permission Fix

Script automatically sets permissions for WinSCP / FTP uploads:

chown -R www-data:www-data /var/www/<app>
chmod -R 775 /var/www/<app>/storage /var/www/<app>/bootstrap/cache


📂 Repository Structure

laravel-deploy/
├─ deploy_laravel.sh      # Main deployment script
├─ README.md              # Documentation
└─ .gitignore             # Optional

📝 Tips
To always use the latest script version, run directly via curl:


sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nasrulll/laravel-deploy/main/deploy_laravel.sh)" -- --silent

To auto-update Laravel apps, make sure they are git repositories and include git pull in the script.

Logging for silent mode: /var/log/laravel_ultra_deploy.log

🎨 Visual / Emoji Example

🚀 Deploying App1
💻 Installing dependencies...
🗄️ Creating database app1_db
🔑 Fixing permissions...
🌐 Creating Nginx config...
🎉 Deployment Completed!
🤝 Contributing


Fork the repository

Add new features / fixes

Commit & push to a new branch

Create a Pull Request

📄 License
MIT License
© 2026 Nasrul Muiz