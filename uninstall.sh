#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG / PAM-MQ - ONE-CLICK COMPLETE UNINSTALLER SCRIPT
# Tự động gỡ bỏ sạch sẽ toàn bộ dịch vụ, database, packages và dữ liệu cài đặt
# ==============================================================================

set -e

# Màu sắc giao diện
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

# Helper an toàn đọc dữ liệu từ Terminal TTY
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

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Lỗi: Bạn bắt buộc phải chạy script này với quyền root (sudo ./uninstall.sh)${NC}"
    exit 1
fi

# Phát hiện OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME="unknown"
fi

echo -e "${YELLOW}Cảnh báo: Script này sẽ dừng toàn bộ dịch vụ PAM, xóa thư mục cài đặt, xóa Database và tùy chọn gỡ bỏ MariaDB Server.${NC}\n"
read_input "Bạn có chắc chắn muốn tiến hành GỠ BỎ TOÀN BỘ hệ thống? (y/N): " "N" CONFIRM_UNINSTALL

if ! [[ "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}-> Đã hủy thao tác gỡ bỏ. Hệ thống được giữ nguyên.${NC}"
    exit 0
fi

read_input "Bạn có muốn GỠ BỎ HOÀN TOÀN gói MariaDB/MySQL Server khỏi máy chủ không? (y/N) [Mặc định: y]: " "y" PURGE_MARIADB

# Lấy port từ .env để đóng firewall nếu có
INSTALLED_PORT=""
if [ -f "${INSTALL_DIR_CPG}/.env" ]; then
    INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR_CPG}/.env" | cut -d'=' -f2 | tr -d ' "')
elif [ -f "${INSTALL_DIR_MQ}/.env" ]; then
    INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR_MQ}/.env" | cut -d'=' -f2 | tr -d ' "')
fi

# 2. Dừng và gỡ bỏ Systemd Services
echo -e "\n${CYAN}[1/5] Đang dừng và hủy đăng ký Systemd Services...${NC}"
systemctl stop ${SERVICE_CPG} >/dev/null 2>&1 || true
systemctl disable ${SERVICE_CPG} >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_CPG}.service"

systemctl stop ${SERVICE_MQ} >/dev/null 2>&1 || true
systemctl disable ${SERVICE_MQ} >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_MQ}.service"

systemctl daemon-reload
pkill -9 -f "pam-cpg" >/dev/null 2>&1 || true
pkill -9 -f "PAM-MQ" >/dev/null 2>&1 || true
echo -e "      ${GREEN}✔ Đã dừng và xóa sạch các dịch vụ Systemd.${NC}"

# 3. Xóa Database & User PAM trong MariaDB / MySQL
echo -e "\n${CYAN}[2/5] Đang dọn dẹp Database \`pamcpg\` và User \`pamcpg\`...${NC}"
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
    echo -e "      ${GREEN}✔ Đã xóa Database \`pamcpg\` và phân quyền User liên quan.${NC}"
else
    echo -e "      ${YELLOW}⚠ Không tìm thấy MariaDB/MySQL Client, bỏ qua bước xóa DB.${NC}"
fi

# 4. Gỡ bỏ gói MariaDB Server nếu người dùng yêu cầu
if [[ "$PURGE_MARIADB" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}[3/5] Đang gỡ bỏ hoàn toàn gói MariaDB Server và dữ liệu MySQL...${NC}"
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
    echo -e "      ${GREEN}✔ Đã gỡ bỏ MariaDB Server sạch sẽ khỏi hệ điều hành.${NC}"
else
    echo -e "\n${CYAN}[3/5] Bỏ qua gỡ bỏ gói MariaDB Server (giữ nguyên CSDL hệ thống khác).${NC}"
fi

# 5. Xóa toàn bộ thư mục cài đặt & cấu hình
echo -e "\n${CYAN}[4/5] Đang xóa toàn bộ thư mục cài đặt và tệp tin liên quan...${NC}"
rm -rf "${INSTALL_DIR_CPG}"
rm -rf "${INSTALL_DIR_MQ}"
rm -rf "/root/.Tool-SSH"
rm -rf "/tmp/pam-cpg"
rm -rf "/tmp/pam-cpg-test"
echo -e "      ${GREEN}✔ Đã xóa sạch các thư mục: ${INSTALL_DIR_CPG}, ${INSTALL_DIR_MQ}, /root/.Tool-SSH${NC}"

# 6. Đóng cổng tường lửa UFW nếu đã mở
echo -e "\n${CYAN}[5/5] Kiểm tra và dọn dẹp quy tắc tường lửa (Firewall)...${NC}"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    if [ -n "$INSTALLED_PORT" ]; then
        ufw delete allow "${INSTALLED_PORT}/tcp" >/dev/null 2>&1 || true
    fi
    ufw delete allow 9000/tcp >/dev/null 2>&1 || true
    ufw delete allow 8083/tcp >/dev/null 2>&1 || true
    echo -e "      ${GREEN}✔ Đã thu hồi quyền mở cổng tường lửa.${NC}"
else
    echo -e "      ${GREEN}✔ Tường lửa UFW không bật hoặc không có quy tắc cần xóa.${NC}"
fi

echo -e "\n${GREEN}${BOLD}"
echo "=========================================================================="
echo "    🎉 HOÀN TẤT! HỆ THỐNG ĐÃ ĐƯỢC GỠ BỎ TOÀN BỘ & SẠCH SẼ 100%!          "
echo "=========================================================================="
echo -e "${NC}"
echo -e "Máy chủ hiện đã trở về trạng thái sạch sẽ ban đầu (Clean slate)."
echo -e "Bạn có thể chạy lại lệnh cài đặt mới từ Git Public bất kỳ lúc nào:"
echo -e "👉 ${CYAN}${BOLD}bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/cuongnguyen955/pam-cpg/main/auto-install.sh?t=\$(date +%s))\"${NC}\n"
