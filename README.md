# 🚀 Laravel Multi-Domain Deploy Script

![Laravel](https://img.shields.io/badge/Laravel-8-red?style=flat-square)
![Debian](https://img.shields.io/badge/Debian-11-blue?style=flat-square)
![PHP](https://img.shields.io/badge/PHP-7.4-purple?style=flat-square)
![MariaDB](https://img.shields.io/badge/MariaDB-10.5-green?style=flat-square)
![Nginx](https://img.shields.io/badge/Nginx-stable-orange?style=flat-square)

---

## 📌 Description

This script allows **automatic deployment of multiple Laravel applications** on a single **Debian/Ubuntu server**, including:

- Multi-domain Laravel apps  
- Auto-detect PHP & MariaDB versions  
- Auto database creation for each app  
- Permission fix for WinSCP / FTP uploads  
- Automatic Nginx virtual host configuration  
- ionCube loader installation for PHP 7.4  
- Silent & non-silent modes  
- Logging at `/var/log/laravel_ultra_deploy.log`  

> 🎨 The script comes with **emoji & interactive prompts** for non-silent mode.

---

## ⚡ Key Features

| Feature | Silent Mode | Visual Mode |
|---------|------------|------------|
| Auto-scan `/var/www/` for Laravel apps | ✅ | ✅ |
| Auto create DB & user per app | ✅ | ✅ (shows password) |
| Auto permission fix (`chown` + `chmod`) | ✅ | ✅ |
| Auto Nginx virtualhost creation | ✅ | ✅ |
| Install PHP 7.4, MariaDB, Nginx | ✅ | ✅ |
| Install ionCube loader 7.4 | ✅ | ✅ |
| Logging to file | ✅ | ✅ |
| Emoji & interactive prompts | ❌ | ✅ |
| Silent Ultra-Automated | ✅ | ❌ |

---

## 🖥️ Server Requirements

1. OS: **Debian 11 / Ubuntu 20+**  
2. Laravel apps directory: `/var/www/`  
3. Server must have **internet access**  
4. User with **sudo privileges**

---

## 🚀 Deployment Instructions

### Non-Silent / Interactive Mode

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)"
Script will show prompts, emoji, and PHP/SSL options

Recommended for first-time deployment or testing

## Silent / Ultra-Automated Mode

sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)" -- --silent >> /var/log/laravel_ultra_deploy.log 2>&1

Auto detects all options

Full logging at /var/log/laravel_ultra_deploy.log

Ideal for cron jobs or automated deployments

🗄️ Database Structure
For each Laravel app:

Database automatically created: appname_db

User automatically created: appname_user

Random password, displayed in terminal (non-silent mode)

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