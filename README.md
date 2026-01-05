# 🚀 Laravel Multi-Domain Deploy Script

![Laravel](https://img.shields.io/badge/Laravel-8-red?style=flat-square)
![Debian](https://img.shields.io/badge/Debian-11-blue?style=flat-square)
![PHP](https://img.shields.io/badge/PHP-7.4-purple?style=flat-square)
![MariaDB](https://img.shields.io/badge/MariaDB-10.5-green?style=flat-square)
![Nginx](https://img.shields.io/badge/Nginx-stable-orange?style=flat-square)

---

## 📌 Deskripsi

Script ini memungkinkan **auto deployment multi Laravel applications** pada satu server **Debian/Ubuntu**, termasuk:

- Multi-domain Laravel apps  
- Auto-detect PHP & MariaDB  
- Auto database creation per app  
- Permission fix untuk WinSCP / FTP  
- Auto Nginx virtual host config  
- ionCube loader 7.4 installation  
- Silent & non-silent modes  
- Logging di `/var/log/laravel_ultra_deploy.log`  

> 🎨 Script sudah dilengkapi **emoji & visual prompts** untuk mode non-silent.

---

## ⚡ Fitur Utama

| Fitur | Mode Silent | Mode Visual |
|-------|------------|------------|
| Auto scan `/var/www/` untuk Laravel apps | ✅ | ✅ |
| Auto create DB & user | ✅ | ✅ (tampilkan password) |
| Auto fix permission (`chown` + `chmod`) | ✅ | ✅ |
| Auto Nginx config per app | ✅ | ✅ |
| Install PHP 7.4, MariaDB, Nginx | ✅ | ✅ |
| Install ionCube loader 7.4 | ✅ | ✅ |
| Logging ke file | ✅ | ✅ |
| Emoji & interaktif prompts | ❌ | ✅ |
| Silent Ultra-Automated | ✅ | ❌ |

---

## 🖥️ Persiapan Server

1. Sistem operasi: **Debian 11 / Ubuntu 20+**  
2. Direktori Laravel apps: `/var/www/`  
3. Pastikan server **terkoneksi internet**  
4. User dengan akses **sudo**

---

## 🚀 Cara Deploy

### Non-Silent / Interaktif (Visual)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)"
Script akan menampilkan prompt, emoji & pilihan PHP, SSL, jumlah apps

Cocok untuk pertama kali deploy atau testing

Silent / Ultra-Automated
bash
Copy code
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)" -- --silent >> /var/log/laravel_ultra_deploy.log 2>&1
Semua opsi auto detect

Logging lengkap ke /var/log/laravel_ultra_deploy.log

Cocok untuk cron jobs / auto deploy

🗄️ Struktur Database
Untuk setiap Laravel app:

Database dibuat otomatis: appname_db

User dibuat otomatis: appname_user

Password random, ditampilkan di terminal (non-silent)

⚙️ Nginx Virtual Hosts
Script otomatis membuat virtual host per app:

swift
Copy code
/etc/nginx/sites-available/<appname>.conf
/etc/nginx/sites-enabled/<appname>.conf
Domain default: <appname>.local

Bisa diubah sesuai kebutuhan

🔧 Permission Fix
Script otomatis set permission agar upload via WinSCP / FTP mudah:

bash
Copy code
chown -R www-data:www-data /var/www/<app>
chmod -R 775 /var/www/<app>/storage /var/www/<app>/bootstrap/cache
📂 Struktur Repo
bash
Copy code
laravel-deploy/
├─ deploy_laravel.sh      # Script utama
├─ README.md              # Dokumentasi (ini file)
└─ .gitignore             # Optional
📝 Tips
Untuk update script otomatis, jalankan selalu via curl:

bash
Copy code
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)" -- --silent
Untuk update Laravel apps otomatis, pastikan apps berada di git repo dan tambahkan git pull di script

Logging silent mode: /var/log/laravel_ultra_deploy.log

🎨 Screenshot / Visual
🖼️ Emoji & visual mode menampilkan progress interaktif per app, pilihan PHP, SSL, dan DB info.

arduino
Copy code
🚀 Deploying App1
💻 Installing dependencies...
🗄️ Creating database app1_db
🔑 Fixing permissions...
🌐 Creating Nginx config...
🎉 Deployment Completed!
🤝 Contributing
Buat fork repo

Tambahkan fitur / perbaikan

Commit & push ke branch baru

Buat pull request

📄 License
MIT License
© 2026 Nasrul Muiz

yaml
Copy code

---

Kalau kamu mau, saya bisa buatkan **versi README dengan visual diagram alur deploy + emoji penuh**, sehingga repo **terlihat profesional, interaktif, dan menarik** bagi user baru.  

Apakah mau saya buatkan versi diagram visual itu juga?






You said:
buat readme.md dalam bahasa inggris


ChatGPT said:
Perfect 😎! Berikut versi README.md dalam bahasa Inggris, menarik, lengkap, dan siap langsung kamu simpan di repo GitHub:

markdown
Copy code
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

Silent / Ultra-Automated Mode
bash
Copy code
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

swift
Copy code
/etc/nginx/sites-available/<appname>.conf
/etc/nginx/sites-enabled/<appname>.conf
Default domain: <appname>.local

Can be customized as needed

🔧 Permission Fix
Script automatically sets permissions for WinSCP / FTP uploads:

bash
Copy code
chown -R www-data:www-data /var/www/<app>
chmod -R 775 /var/www/<app>/storage /var/www/<app>/bootstrap/cache
📂 Repository Structure
bash
Copy code
laravel-deploy/
├─ deploy_laravel.sh      # Main deployment script
├─ README.md              # Documentation
└─ .gitignore             # Optional
📝 Tips
To always use the latest script version, run directly via curl:

bash
Copy code
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/laravel-deploy/main/deploy_laravel.sh)" -- --silent
To auto-update Laravel apps, make sure they are git repositories and include git pull in the script.

Logging for silent mode: /var/log/laravel_ultra_deploy.log

🎨 Visual / Emoji Example
arduino
Copy code
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