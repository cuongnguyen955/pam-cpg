#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG - ONE-CLICK ENTERPRISE STANDALONE AUTO INSTALLER
# Repository: https://github.com/cuongnguyen955/pam-cpg
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

INSTALL_DIR="/opt/PAM-CPG"
SERVICE_NAME="pam-cpg"
DEFAULT_WEB_PORT="8083"
DEFAULT_DB_NAME="pamcpg"
DEFAULT_DB_USER="pamcpg"
DEFAULT_DB_PORT="3306"
DEFAULT_DB_HOST="127.0.0.1"
GITHUB_REPO="cuongnguyen955/pam-cpg"

# Hàm kiểm tra xem port có đang bị ứng dụng khác chiếm dụng không
is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -qE "(:|\])${port}\b"; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -qE ":${port}\b"; then
            return 0
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; then
            return 0
        fi
    fi
    if (timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Hàm tự động quét tìm cổng trống đầu tiên trong dải cổng chỉ định
find_free_port_in_range() {
    local start_port=${1:-9000}
    local end_port=${2:-9999}
    local port
    for ((port=start_port; port<=end_port; port++)); do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    echo "9000"
}

# Hàm sinh chuỗi ngẫu nhiên an toàn
generate_random_password() {
    openssl rand -base64 16 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c 16
}

clear
echo -e "${BLUE}${BOLD}"
echo "=========================================================================="
echo "         PAM-CPG ENTERPRISE GATEWAY - ONE-CLICK AUTO INSTALLER           "
echo "                https://github.com/${GITHUB_REPO}                         "
echo "=========================================================================="
echo -e "${NC}"

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Lỗi: Bạn bắt buộc phải chạy script này với quyền root (sudo ./auto-install.sh)${NC}"
    exit 1
fi

# 2. Phát hiện OS
echo -e "${CYAN}[*] Bước 1/7: Kiểm tra môi trường hệ điều hành...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    echo -e "    -> Hệ điều hành phát hiện: ${GREEN}${NAME} (${VERSION_ID:-latest})${NC}"
else
    OS_NAME="unknown"
    echo -e "${YELLOW}[!] Sử dụng cấu hình chuẩn Linux.${NC}"
fi

# Lấy địa chỉ IP máy chủ
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="127.0.0.1"
fi

# 3. Thu thập thông tin cấu hình (Interactive Configuration)
echo -e "\n${CYAN}[*] Bước 2/7: Thiết lập tham số cấu hình hệ thống${NC}"
echo -e "    -> Đang quét dải cổng 9000 - 9999 để tìm cổng khả dụng tối ưu..."
SUGGESTED_PORT=$(find_free_port_in_range 9000 9999)
echo -e "    -> Cổng trống khả dụng gợi ý: ${GREEN}${BOLD}${SUGGESTED_PORT}${NC}"
echo -e "${YELLOW}(Nhấn Enter để tự động sử dụng giá trị gợi ý hoặc nhập cổng theo nhu cầu)${NC}\n"

# Vòng lặp nhập cổng và kiểm tra xung đột
while true; do
    read -p "1. Cổng Web Gateway PAM-CPG [Gợi ý: ${SUGGESTED_PORT}]: " INPUT_WEB_PORT
    WEB_PORT=${INPUT_WEB_PORT:-$SUGGESTED_PORT}

    # Kiểm tra tính hợp lệ (phải là số nguyên từ 1 đến 65535)
    if ! [[ "$WEB_PORT" =~ ^[0-9]+$ ]] || [ "$WEB_PORT" -lt 1 ] || [ "$WEB_PORT" -gt 65535 ]; then
        echo -e "    ${RED}[!] Lỗi: Cổng phải là số nguyên trong khoảng 1 - 65535. Vui lòng nhập lại!${NC}"
        continue
    fi

    # Kiểm tra cổng có bị chiếm dụng không
    if is_port_in_use "$WEB_PORT"; then
        echo -e "    ${RED}[!] Cảnh báo: Cổng ${WEB_PORT} hiện đang bị chiếm dụng bởi ứng dụng khác trên máy chủ!${NC}"
        echo -e "    ${YELLOW}    -> Bạn có thể nhấn Enter để dùng cổng gợi ý [${SUGGESTED_PORT}] hoặc nhập cổng khác.${NC}"
    else
        echo -e "    ${GREEN}✔ Cổng ${WEB_PORT} hợp lệ và sẵn sàng sử dụng.${NC}"
        break
    fi
done

read -p "2. Tên miền Domain sử dụng (nếu có, VD: pam.company.vn) [Mặc định: ${LOCAL_IP}]: " INPUT_DOMAIN
DOMAIN=${INPUT_DOMAIN:-$LOCAL_IP}

read -p "3. Tự động cài đặt và cấu hình MariaDB Server cục bộ? (Y/n) [Mặc định: Y]: " INPUT_INSTALL_DB
INSTALL_DB=${INPUT_INSTALL_DB:-"Y"}

if [[ "$INSTALL_DB" =~ ^[Yy]$ ]]; then
    DB_NAME="${DEFAULT_DB_NAME}"
    DB_USER="${DEFAULT_DB_USER}"
    DB_PASS="$(generate_random_password)"
    MARIADB_ROOT_PASS="$(generate_random_password)"
    DB_HOST="127.0.0.1"
    DB_PORT="3306"
else
    read -p "4. Địa chỉ máy chủ CSDL (Host) [Mặc định: 127.0.0.1]: " INPUT_DB_HOST
    DB_HOST=${INPUT_DB_HOST:-$DEFAULT_DB_HOST}

    read -p "5. Cổng CSDL (Port) [Mặc định: 3306]: " INPUT_DB_PORT
    DB_PORT=${INPUT_DB_PORT:-$DEFAULT_DB_PORT}

    read -p "6. Tên Cơ sở dữ liệu [Mặc định: ${DEFAULT_DB_NAME}]: " INPUT_DB_NAME
    DB_NAME=${INPUT_DB_NAME:-$DEFAULT_DB_NAME}

    read -p "7. Tên Người dùng Database [Mặc định: ${DEFAULT_DB_USER}]: " INPUT_DB_USER
    DB_USER=${INPUT_DB_USER:-$DEFAULT_DB_USER}

    read -p "8. Mật khẩu Database: " DB_PASS
    MARIADB_ROOT_PASS="[N/A - Database Ngoại Vi]"
fi

DB_DSN="${DB_USER}:${DB_PASS}@tcp(${DB_HOST}:${DB_PORT})/${DB_NAME}?charset=utf8mb4&parseTime=True&loc=Local"

echo -e "\n${GREEN}✔ Đã ghi nhận thông số cấu hình:${NC}"
echo -e "  • Web Gateway Port : ${BOLD}${WEB_PORT}${NC}"
echo -e "  • Domain / Host IP : ${BOLD}${DOMAIN}${NC}"
echo -e "  • Database Target  : ${BOLD}${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"

# 4. Cài đặt các gói phụ thuộc (FFmpeg, MariaDB, OpenSSL, curl, jq)
echo -e "\n${CYAN}[*] Bước 3/7: Cài đặt các gói phụ thuộc hệ thống (FFmpeg, OpenSSL, MariaDB, JQ)...${NC}"
if [ "$OS_NAME" = "ubuntu" ] || [ "$OS_NAME" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ffmpeg ca-certificates curl openssl tzdata jq >/dev/null 2>&1

    if [[ "$INSTALL_DB" =~ ^[Yy]$ ]]; then
        echo -e "    -> Đang cài đặt MariaDB Server..."
        apt-get install -y -qq mariadb-server mariadb-client >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    fi
elif [ "$OS_NAME" = "centos" ] || [ "$OS_NAME" = "rhel" ] || [ "$OS_NAME" = "rocky" ] || [ "$OS_NAME" = "almalinux" ]; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y ffmpeg ca-certificates curl openssl tzdata jq >/dev/null 2>&1
    if [[ "$INSTALL_DB" =~ ^[Yy]$ ]]; then
        yum install -y mariadb-server mariadb >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    fi
fi
echo -e "    ${GREEN}✔ Đã cài đặt xong các gói phụ thuộc.${NC}"

# 5. Khởi tạo Cơ sở dữ liệu và phân quyền User DB
if [[ "$INSTALL_DB" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}[*] Bước 4/7: Tự động khởi tạo Database \`${DB_NAME}\` và phân quyền User \`${DB_USER}\`...${NC}"
    mariadb -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MARIADB_ROOT_PASS}');
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    echo -e "    ${GREEN}✔ Database \`${DB_NAME}\` đã được tạo và thiết lập bảo mật thành công!${NC}"
fi

# 6. Tạo thư mục hệ thống và tải/sao chép file thực thi pam-cpg
echo -e "\n${CYAN}[*] Bước 5/7: Tạo cấu trúc thư mục và triển khai file thực thi vào ${INSTALL_DIR}...${NC}"
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/certs"
mkdir -p "${INSTALL_DIR}/config"
mkdir -p "${INSTALL_DIR}/shared/recordings"
mkdir -p "${INSTALL_DIR}/shared/command_logs"

# Lấy file binary: ưu tiên file cục bộ trong thư mục hiện tại, nếu không có thì tải từ GitHub Repo
if [ -f "./pam-cpg" ]; then
    cp -f "./pam-cpg" "${INSTALL_DIR}/bin/pam-cpg"
elif [ -f "./PAM-MQ" ]; then
    cp -f "./PAM-MQ" "${INSTALL_DIR}/bin/pam-cpg"
elif [ -f "./build/bin/PAM-MQ" ]; then
    cp -f "./build/bin/PAM-MQ" "${INSTALL_DIR}/bin/pam-cpg"
else
    echo -e "    -> Đang tải file thực thi \`pam-cpg\` từ GitHub (${GITHUB_REPO})..."
    curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/pam-cpg" -o "${INSTALL_DIR}/bin/pam-cpg"
fi

chmod +x "${INSTALL_DIR}/bin/pam-cpg"

# 7. Tự động sinh chứng chỉ SSL 10 năm (3650 ngày)
echo -e "\n${CYAN}[*] Bước 6/7: Tự động khởi tạo chứng chỉ bảo mật SSL (Thời hạn 10 năm)...${NC}"
CERT_FILE="${INSTALL_DIR}/certs/server.crt"
KEY_FILE="${INSTALL_DIR}/certs/server.key"

SAN_CONFIG="DNS:localhost,IP:127.0.0.1,IP:${LOCAL_IP}"
if [ "$DOMAIN" != "$LOCAL_IP" ] && [ -n "$DOMAIN" ]; then
    SAN_CONFIG="${SAN_CONFIG},DNS:${DOMAIN}"
fi

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/C=VN/ST=Hanoi/L=Hanoi/O=PAM-CPG Enterprise/OU=Security/CN=${DOMAIN}" \
    -addext "subjectAltName=${SAN_CONFIG}" >/dev/null 2>&1

chmod 600 "${KEY_FILE}"
echo -e "    ${GREEN}✔ Đã sinh chứng chỉ SSL 10 năm thành công tại ${INSTALL_DIR}/certs/${NC}"

# Tạo file .env lưu trữ cấu hình
cat <<EOF > "${INSTALL_DIR}/.env"
# PAM-CPG Enterprise Configuration
PORT=${WEB_PORT}
DOMAIN=${DOMAIN}
DB_DSN=${DB_DSN}
SSL_CERT=${CERT_FILE}
SSL_KEY=${KEY_FILE}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASS}
MARIADB_APP_PASSWORD=${DB_PASS}
EOF

chmod 600 "${INSTALL_DIR}/.env"

# 8. Chạy chế độ Setup của pam-cpg để khởi tạo CSDL, MFA Secret, Recovery Code và 3 mảnh Shamir Master Key
echo -e "\n${CYAN}[*] Bước 7/7: Khởi tạo hệ thống bảo mật (Admin, MFA TOTP & 3 Mảnh Khóa Shamir Master Key)...${NC}"
SETUP_OUTPUT=$("${INSTALL_DIR}/bin/pam-cpg" --setup --db "${DB_DSN}" 2>/dev/null)

ADMIN_USER=$(echo "$SETUP_OUTPUT" | jq -r '.admin_user // "admin"')
ADMIN_PASS=$(echo "$SETUP_OUTPUT" | jq -r '.admin_pass // "Admin@12345"')
MFA_SECRET=$(echo "$SETUP_OUTPUT" | jq -r '.mfa_secret // "Chưa khởi tạo"')
MFA_RECOVERY=$(echo "$SETUP_OUTPUT" | jq -r '.mfa_recovery_code // "Chưa khởi tạo"')
SHARE_1=$(echo "$SETUP_OUTPUT" | jq -r '.shamir_shares[0] // ""')
SHARE_2=$(echo "$SETUP_OUTPUT" | jq -r '.shamir_shares[1] // ""')
SHARE_3=$(echo "$SETUP_OUTPUT" | jq -r '.shamir_shares[2] // ""')
RAW_KEY=$(echo "$SETUP_OUTPUT" | jq -r '.master_key_raw // ""')

# Lưu các khóa bí mật vào file bàn giao an toàn
cat <<EOF > "${INSTALL_DIR}/CREDENTIALS.txt"
==========================================================================
              THÔNG TIN BÀN GIAO HỆ THỐNG PAM-CPG ENTERPRISE
==========================================================================
1. THÔNG TIN TRUY CẬP WEB PORTAL:
   • Đường dẫn HTTPS : https://${DOMAIN}:${WEB_PORT} (hoặc https://${LOCAL_IP}:${WEB_PORT})
   • Tài khoản Admin : ${ADMIN_USER}
   • Mật khẩu Admin  : ${ADMIN_PASS}

2. THÔNG TIN BẢO MẬT 2 LỚP (MFA / TOTP):
   • MFA Secret Key (Nhập vào Google Authenticator/Authy): ${MFA_SECRET}
   • MFA Recovery Code (Dùng để tự khôi phục khi mất OTP) : ${MFA_RECOVERY}

3. THÔNG TIN CƠ SỞ DỮ LIỆU MARIADB:
   • Database Name       : ${DB_NAME}
   • User Database       : ${DB_USER}
   • Password Database   : ${DB_PASS}
   • MariaDB Root Pass   : ${MARIADB_ROOT_PASS}
   • DSN Kết Nối         : ${DB_DSN}

4. 3 MẢNH KHÓA MASTER KEY SHAMIR SECRET SHARING (CẦN 2/3 MẢNH ĐỂ MỞ KHÓA):
   • Mảnh khóa 1 (Share 1) : ${SHARE_1}
   • Mảnh khóa 2 (Share 2) : ${SHARE_2}
   • Mảnh khóa 3 (Share 3) : ${SHARE_3}
   • Master Key Raw (RAM)  : ${RAW_KEY}
==========================================================================
EOF
chmod 600 "${INSTALL_DIR}/CREDENTIALS.txt"

# Đăng ký và khởi chạy Systemd Service
cat <<EOF > "/etc/systemd/system/${SERVICE_NAME}.service"
[Unit]
Description=PAM-CPG Enterprise Privileged Access Management Gateway
After=network.target mariadb.service mysql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${INSTALL_DIR}/bin/pam-cpg --web --port \${PORT} --db "\${DB_DSN}"
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
systemctl restart ${SERVICE_NAME}

# Mở cổng UFW nếu có bật
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow ${WEB_PORT}/tcp >/dev/null 2>&1 || true
fi

# Tự động nạp 2 mảnh khóa để mở khóa hệ thống ngay sau khi cài đặt
sleep 2
curl -k -s -X POST "https://127.0.0.1:${WEB_PORT}/api/system/unlock" \
    -H "Content-Type: application/json" \
    -d "{\"shares\": [\"${SHARE_1}\", \"${SHARE_2}\"]}" >/dev/null 2>&1 || true

# 9. In bảng thông tin bàn giao ra màn hình
echo -e "\n${GREEN}${BOLD}"
echo "=========================================================================="
echo "       🎉 CHÚC MỪNG! PAM-CPG ĐÃ ĐƯỢC CÀI ĐẶT & KHỞI CHẠY THÀNH CÔNG!       "
echo "=========================================================================="
echo -e "${NC}"

echo -e "🌐 ${BOLD}ĐƯỜNG DẪN TRUY CẬP WEB GATEWAY (HTTPS):${NC}"
echo -e "   • ${CYAN}${BOLD}https://${DOMAIN}:${WEB_PORT}${NC} (hoặc ${CYAN}https://${LOCAL_IP}:${WEB_PORT}${NC})"
echo ""
echo -e "👤 ${BOLD}TÀI KHOẢN QUẢN TRỊ VIÊN MẶC ĐỊNH:${NC}"
echo -e "   • Tên đăng nhập : ${BOLD}${ADMIN_USER}${NC}"
echo -e "   • Mật khẩu      : ${BOLD}${ADMIN_PASS}${NC}"
echo ""
echo -e "🔑 ${BOLD}THÔNG TIN XÁC THỰC 2 LỚP (MFA / TOTP):${NC}"
echo -e "   • ${YELLOW}MFA Secret Key (TOTP)${NC} : ${BOLD}${MFA_SECRET}${NC}"
echo -e "     *(Nhập mã Secret Key này vào ứng dụng Google Authenticator hoặc Authy để lấy mã 6 số)*"
echo -e "   • ${YELLOW}MFA Recovery Code    ${NC} : ${BOLD}${MFA_RECOVERY}${NC}"
echo -e "     *(Mã khôi phục dùng để tự reset MFA tại trang đăng nhập nếu làm mất điện thoại)*"
echo ""
echo -e "🗄️  ${BOLD}THÔNG TIN CƠ SỞ DỮ LIỆU MARIADB:${NC}"
echo -e "   • MariaDB Root Password : ${BOLD}${MARIADB_ROOT_PASS}${NC}"
echo -e "   • User Database \`${DB_USER}\`  : ${BOLD}${DB_PASS}${NC}"
echo -e "   • Database Name         : ${BOLD}${DB_NAME}${NC}"
echo ""
echo -e "🛡️  ${BOLD}3 MẢNH KHÓA SHAMIR MASTER KEY (LƯU LẠI ĐỂ MỞ KHÓA KHI REBOOT SERVER):${NC}"
echo -e "   • ${PURPLE}Mảnh khóa 1 (Share 1)${NC} : ${BOLD}${SHARE_1}${NC}"
echo -e "   • ${PURPLE}Mảnh khóa 2 (Share 2)${NC} : ${BOLD}${SHARE_2}${NC}"
echo -e "   • ${PURPLE}Mảnh khóa 3 (Share 3)${NC} : ${BOLD}${SHARE_3}${NC}"
echo -e "   *(Hệ thống yêu cầu nhập tối thiểu 2 trong 3 mảnh khóa trên để mở khóa khi khởi động)*"
echo ""
echo -e "📁 ${BOLD}FILE LƯU TOÀN BỘ THÔNG TIN BÀN GIAO BẢO MẬT:${NC}"
echo -e "   • File: ${BOLD}${INSTALL_DIR}/CREDENTIALS.txt${NC}"
echo "=========================================================================="
