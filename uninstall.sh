#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG / PAM-MQ - ONE-CLICK COMPLETE UNINSTALLER SCRIPT
# Cleanly removes all services, databases, packages, and installation data
# ==============================================================================

set -e

# UI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

INSTALL_DIR_CPG="/opt/PAM-CPG"
INSTALL_DIR_MQ="/opt/pam-mq"
SERVICE_CPG="pam-cpg"
SERVICE_MQ="pam-mq"

# Safe helper for reading TTY input
read_input() {
    local prompt_msg="$1"
    local default_val="$2"
    local var_name="$3"
    local user_val=""

    if [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" user_val < /dev/tty || true
    else
        read -r -p "$prompt_msg" user_val || true
    fi

    if [ -z "$user_val" ]; then
        user_val="$default_val"
    fi
    eval "$var_name=\"\$user_val\""
}

clear
echo -e "${RED}${BOLD}"
echo "=========================================================================="
echo "          PAM-CPG / PAM-MQ - COMPLETE SYSTEM UNINSTALLER                 "
echo "=========================================================================="
echo -e "${NC}"

# 1. Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Error: You must run this script with root privileges (sudo ./uninstall.sh)${NC}"
    exit 1
fi

# OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME="unknown"
fi

echo -e "${YELLOW}Warning: This script will stop all PAM services, delete installation directories, drop the database, and optionally purge MariaDB Server.${NC}\n"
read_input "Are you sure you want to completely UNINSTALL the system? (y/N): " "N" CONFIRM_UNINSTALL

if ! [[ "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}-> Uninstall aborted. System remains unchanged.${NC}"
    exit 0
fi

read_input "Do you want to COMPLETELY PURGE the MariaDB/MySQL Server package from this host? (y/N) [Default: y]: " "y" PURGE_MARIADB

# Read port from .env to close firewall rule if present
INSTALLED_PORT=""
if [ -f "${INSTALL_DIR_CPG}/.env" ]; then
    INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR_CPG}/.env" | cut -d'=' -f2 | tr -d ' "')
elif [ -f "${INSTALL_DIR_MQ}/.env" ]; then
    INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR_MQ}/.env" | cut -d'=' -f2 | tr -d ' "')
fi

# 2. Stop and remove Systemd Services
echo -e "\n${CYAN}[1/5] Stopping and unregistering Systemd Services...${NC}"
systemctl stop ${SERVICE_CPG} >/dev/null 2>&1 || true
systemctl disable ${SERVICE_CPG} >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_CPG}.service"

systemctl stop ${SERVICE_MQ} >/dev/null 2>&1 || true
systemctl disable ${SERVICE_MQ} >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_MQ}.service"

systemctl daemon-reload
pkill -9 -f "pam-cpg" >/dev/null 2>&1 || true
pkill -9 -f "PAM-MQ" >/dev/null 2>&1 || true
echo -e "      ${GREEN}✔ Stopped and removed Systemd services.${NC}"

# 3. Drop Database & User in MariaDB / MySQL
echo -e "\n${CYAN}[2/5] Dropping Database \`pamcpg\` and User \`pamcpg\`...${NC}"
MYSQL_CMD="mariadb"
if ! command -v mariadb >/dev/null 2>&1; then
    MYSQL_CMD="mysql"
fi

if command -v $MYSQL_CMD >/dev/null 2>&1; then
    $MYSQL_CMD -u root <<EOF >/dev/null 2>&1 || true
DROP DATABASE IF EXISTS pamcpg;
DROP USER IF EXISTS 'pamcpg'@'127.0.0.1';
DROP USER IF EXISTS 'pamcpg'@'localhost';
FLUSH PRIVILEGES;
EOF
    echo -e "      ${GREEN}✔ Dropped Database \`pamcpg\` and associated user permissions.${NC}"
else
    echo -e "      ${YELLOW}⚠ MariaDB/MySQL Client not found, skipping DB drop.${NC}"
fi

# 4. Purge MariaDB Server package if requested
if [[ "$PURGE_MARIADB" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}[3/5] Purging MariaDB Server package and MySQL data directories...${NC}"
    systemctl stop mariadb mysql >/dev/null 2>&1 || true
    systemctl disable mariadb mysql >/dev/null 2>&1 || true

    if [ "$OS_NAME" = "ubuntu" ] || [ "$OS_NAME" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y -qq mariadb-server mariadb-client mariadb-common mysql-common >/dev/null 2>&1 || true
        apt-get autoremove -y -qq >/dev/null 2>&1 || true
        rm -rf /var/lib/mysql /etc/mysql /var/log/mysql
    elif [ "$OS_NAME" = "centos" ] || [ "$OS_NAME" = "rhel" ] || [ "$OS_NAME" = "rocky" ] || [ "$OS_NAME" = "almalinux" ]; then
        yum remove -y mariadb-server mariadb >/dev/null 2>&1 || true
        rm -rf /var/lib/mysql /etc/my.cnf* /var/log/mariadb
    fi
    echo -e "      ${GREEN}✔ MariaDB Server package purged completely from operating system.${NC}"
else
    echo -e "\n${CYAN}[3/5] Skipping MariaDB Server removal (preserving other system databases).${NC}"
fi

# 5. Remove installation directories and configuration files
echo -e "\n${CYAN}[4/5] Removing installation directories and related files...${NC}"
rm -rf "${INSTALL_DIR_CPG}"
rm -rf "${INSTALL_DIR_MQ}"
rm -rf "/root/.Tool-SSH"
rm -rf "/tmp/pam-cpg"
rm -rf "/tmp/pam-cpg-test"
echo -e "      ${GREEN}✔ Cleaned up directories: ${INSTALL_DIR_CPG}, ${INSTALL_DIR_MQ}, /root/.Tool-SSH${NC}"

# 6. Revert Firewall rules (UFW)
echo -e "\n${CYAN}[5/5] Checking and cleaning up Firewall rules (UFW)...${NC}"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    if [ -n "$INSTALLED_PORT" ]; then
        ufw delete allow "${INSTALLED_PORT}/tcp" >/dev/null 2>&1 || true
    fi
    ufw delete allow 9000/tcp >/dev/null 2>&1 || true
    ufw delete allow 8083/tcp >/dev/null 2>&1 || true
    echo -e "      ${GREEN}✔ Revoked open firewall port rules.${NC}"
else
    echo -e "      ${GREEN}✔ UFW firewall inactive or no rules to delete.${NC}"
fi

echo -e "\n${GREEN}${BOLD}"
echo "=========================================================================="
echo "    🎉 COMPLETE! SYSTEM HAS BEEN UNINSTALLED & CLEANED 100%!              "
echo "=========================================================================="
echo -e "${NC}"
echo -e "Host server is now restored to a clean state."
echo -e "You can reinstall anytime using the one-click installer command:"
echo -e "👉 ${CYAN}${BOLD}bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/cuongnguyen955/pam-cpg/main/auto-install.sh?t=\$(date +%s))\"${NC}\n"
