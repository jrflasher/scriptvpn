#!/bin/bash

#========================================#
#   JR-XRAY VPN MANAGER SCRIPT          #
#   Author: RaisTech                    #
#   Version: V1.0                       #
#========================================#

# Warna & Style
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BANNER="
 ${CYAN}
╔══════════════════════════════════════════════════════════════╗
║                    JR-XRAY VPN MANAGER                      ║
║                         by RaisTech                         ║
║                          Version V1.0                       ║
╚══════════════════════════════════════════════════════════════╝
 ${NC}
"

# Variabel Global
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="$SCRIPT_DIR/database"
LOG_FILE="$SCRIPT_DIR/logs/jr-xray.log"
CONFIG_DIR="$SCRIPT_DIR/config"
SSL_DIR="$SCRIPT_DIR/ssl"
WEB_PORT="8080"
BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
NOTIF_TOKEN="YOUR_TELEGRAM_NOTIF_TOKEN"
ADMIN_PASS="admin@2025"

# Inisialisasi Database
init_db() {
    mkdir -p $DB_DIR $SCRIPT_DIR/logs $SSL_DIR
    sqlite3 $DB_DIR/accounts.db "CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        uuid TEXT,
        ip_limit TEXT,
        speed_limit TEXT,
        expiry_days INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );"
    
    sqlite3 $DB_DIR/api_keys.db "CREATE TABLE IF NOT EXISTS api_keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT UNIQUE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );"
}

# Fungsi Logging
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a $LOG_FILE
}

# Cek Root Access
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Jalankan script sebagai root!${NC}"
        exit 1
    fi
}

# Deteksi OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}OS tidak didukung!${NC}"
        exit 1
    fi

    if [[ ! ("$OS" == "ubuntu" && "$VERSION" == "22.04") && ! ("$OS" == "debian" && "$VERSION" == "10") ]]; then
        echo -e "${RED}Hanya support Ubuntu 22.04 LTS dan Debian 10!${NC}"
        exit 1
    fi
}

# Update Sistem
update_system() {
    log "Memperbarui sistem..."
    apt-get update -y && apt-get upgrade -y
    apt-get install -y curl wget sqlite3 python3-pip qrencode nginx
}

# Konfigurasi Jaringan
configure_network() {
    log "Mengonfigurasi jaringan..."
    
    # Disable IPv6
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    sysctl -p
    
    # Enable IPv4 HTTP
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
}

# Install Xray
install_xray() {
    log "Menginstall Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # Generate konfigurasi dasar
    cp $CONFIG_DIR/xray_config.json /usr/local/etc/xray/config.json
    sed -i "s|/path/to/ssl|$SSL_DIR|g" /usr/local/etc/xray/config.json
}

# Install SSH dengan Fitur Lengkap
install_ssh() {
    log "Mengonfigurasi SSH..."
    
    # Backup konfigurasi asli
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Konfigurasi SSH baru
    cp $CONFIG_DIR/ssh_config /etc/ssh/sshd_config
    systemctl restart sshd
}

# Menu Manajemen Akun
account_menu() {
    while true; do
        clear
        echo -e "$BANNER"
        echo -e "${CYAN}=== MENU MANAJEMEN AKUN ===${NC}"
        echo "1. Tambah Akun SSH/Xray"
        echo "2. Edit Akun"
        echo "3. Hapus Akun"
        echo "4. Lihat Semua Akun"
        echo "5. Kembali"
        read -p "Pilih opsi [1-5]: " opt
        
        case $opt in
            1) add_account ;;
            2) edit_account ;;
            3) delete_account ;;
            4) list_accounts ;;
            5) break ;;
            *) echo -e "${RED}Opsi tidak valid!${NC}" ;;
        esac
    done
}

# Tambah Akun
add_account() {
    clear
    echo -e "${CYAN}=== TAMBAH AKUN BARU ===${NC}"
    read -p "Username: " username
    read -p "Password: " password
    read -p "Limit IP (0 untuk tanpa limit): " ip_limit
    read -p "Limit Speed (Mbps atau 'unlimited'): " speed_limit
    read -p "Durasi (hari): " expiry_days
    
    # Generate UUID
    uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Simpan ke database
    sqlite3 $DB_DIR/accounts.db "INSERT INTO accounts (username, password, uuid, ip_limit, speed_limit, expiry_days) 
                                VALUES ('$username', '$password', '$uuid', '$ip_limit', '$speed_limit', $expiry_days);"
    
    # Buat user sistem
    useradd -m -s /bin/bash $username
    echo "$username:$password" | chpasswd
    
    # Kirim notifikasi Telegram
    send_notif "Akun baru dibuat: $username\nUUID: $uuid\nIP Limit: $ip_limit\nSpeed Limit: $speed_limit\nExpiry: $expiry_days hari"
    
    log "Akun $username berhasil dibuat!"
}

# Edit Akun
edit_account() {
    clear
    echo -e "${CYAN}=== EDIT AKUN ===${NC}"
    list_accounts
    read -p "Masukkan ID akun: " id
    
    # Ambil data akun
    account_data=$(sqlite3 $DB_DIR/accounts.db "SELECT * FROM accounts WHERE id=$id;")
    
    if [[ -z "$account_data" ]]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        return
    fi
    
    echo "Data saat ini:"
    echo "$account_data" | awk -F'|' '{printf "Username: %s\nIP Limit: %s\nSpeed Limit: %s\nExpiry: %s hari\n", $2, $5, $6, $7}'
    
    read -p "Username baru (kosongkan untuk skip): " new_username
    read -p "Password baru (kosongkan untuk skip): " new_password
    read -p "IP Limit baru (kosongkan untuk skip): " new_ip_limit
    read -p "Speed Limit baru (kosongkan untuk skip): " new_speed_limit
    read -p "Durasi baru (hari, kosongkan untuk skip): " new_expiry
    
    # Update database
    sqlite3 $DB_DIR/accounts.db "UPDATE accounts SET 
        username = COALESCE(NULLIF('$new_username', ''), username),
        password = COALESCE(NULLIF('$new_password', ''), password),
        ip_limit = COALESCE(NULLIF('$new_ip_limit', ''), ip_limit),
        speed_limit = COALESCE(NULLIF('$new_speed_limit', ''), speed_limit),
        expiry_days = COALESCE(NULLIF('$new_expiry', ''), expiry_days)
        WHERE id=$id;"
    
    log "Akun ID $id berhasil diperbarui!"
}

# Hapus Akun
delete_account() {
    clear
    echo -e "${CYAN}=== HAPUS AKUN ===${NC}"
    list_accounts
    read -p "Masukkan ID akun: " id
    
    # Hapus dari database
    username=$(sqlite3 $DB_DIR/accounts.db "SELECT username FROM accounts WHERE id=$id;")
    sqlite3 $DB_DIR/accounts.db "DELETE FROM accounts WHERE id=$id;"
    
    # Hapus user sistem
    userdel -r $username 2>/dev/null
    
    log "Akun $username berhasil dihapus!"
}

# Lihat Semua Akun
list_accounts() {
    echo -e "${CYAN}=== DAFTAR AKUN ===${NC}"
    sqlite3 $DB_DIR/accounts.db "SELECT id, username, ip_limit, speed_limit, expiry_days FROM accounts;" | \
    while IFS='|' read -r id username ip_limit speed_limit expiry; do
        echo "ID: $id | User: $username | IP Limit: $ip_limit | Speed: $speed_limit | Expiry: $expiry hari"
    done
}

# Kirim Notifikasi Telegram
send_notif() {
    if [[ -n "$NOTIF_TOKEN" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$NOTIF_TOKEN/sendMessage" \
            -d "chat_id=YOUR_CHAT_ID&text=$1" > /dev/null
    fi
}

# Install Web Panel
install_web_panel() {
    log "Menginstall Web Panel..."
    
    # Install Flask
    pip3 install flask flask-httpauth
    
    # Buat service systemd
    cat > /etc/systemd/system/jr-webpanel.service <<EOF
[Unit]
Description=JR-XRAY Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_DIR/lib/web_panel.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable jr-webpanel
    systemctl start jr-webpanel
}

# Install Telegram Bot
install_telegram_bot() {
    log "Menginstall Telegram Bot..."
    
    # Buat service systemd
    cat > /etc/systemd/system/jr-tgbot.service <<EOF
[Unit]
Description=JR-XRAY Telegram Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_DIR/lib/telegram_bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable jr-tgbot
    systemctl start jr-tgbot
}

# Menu Utama
main_menu() {
    while true; do
        clear
        echo -e "$BANNER"
        echo -e "${CYAN}=== MENU UTAMA ===${NC}"
        echo "1. Manajemen Akun"
        echo "2. Install Web Panel"
        echo "3. Install Telegram Bot"
        echo "4. Monitoring Server"
        echo "5. Keluar"
        read -p "Pilih opsi [1-5]: " opt
        
        case $opt in
            1) account_menu ;;
            2) install_web_panel ;;
            3) install_telegram_bot ;;
            4) show_status ;;
            5) exit 0 ;;
            *) echo -e "${RED}Opsi tidak valid!${NC}" ;;
        esac
    done
}

# Monitoring Server
show_status() {
    clear
    echo -e "${CYAN}=== MONITORING SERVER ===${NC}"
    echo -e "${YELLOW}Uptime:$(uptime -p)${NC}"
    echo -e "${YELLOW}CPU Usage:$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')${NC}"
    echo -e "${YELLOW}Memory Usage:$(free -h | grep Mem)${NC}"
    echo -e "${YELLOW}Disk Usage:$(df -h / | tail -1)${NC}"
    
    # Cek service
    echo -e "\n${CYAN}Status Service:${NC}"
    systemctl is-active xray && echo -e "${GREEN}Xray: Running${NC}" || echo -e "${RED}Xray: Stopped${NC}"
    systemctl is-active ssh && echo -e "${GREEN}SSH: Running${NC}" || echo -e "${RED}SSH: Stopped${NC}"
    systemctl is-active jr-webpanel && echo -e "${GREEN}Web Panel: Running${NC}" || echo -e "${RED}Web Panel: Stopped${NC}"
    systemctl is-active jr-tgbot && echo -e "${GREEN}Telegram Bot: Running${NC}" || echo -e "${RED}Telegram Bot: Stopped${NC}"
    
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi Instalasi
install() {
    clear
    echo -e "$BANNER"
    log "Memulai instalasi JR-XRAY..."
    
    check_root
    detect_os
    init_db
    update_system
    configure_network
    install_xray
    install_ssh
    
    log "Instalasi selesai!"
    main_menu
}

# Eksekusi
if [[ "$1" == "--install" ]]; then
    install
else
    echo "Usage: $0 --install"
fi