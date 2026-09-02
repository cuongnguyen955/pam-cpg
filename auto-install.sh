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
        else
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -qE ":${port}\b"; then
            return 0
        else
            return 1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
    if (timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Hàm kiểm tra dịch vụ MariaDB/MySQL cục bộ có đang hoạt động không
is_local_db_running() {
    if is_port_in_use 3306; then
        return 0
    fi
    if [ -S /run/mysqld/mysqld.sock ] || [ -S /var/run/mysqld/mysqld.sock ] || [ -S /tmp/mysql.sock ]; then
        return 0
    fi
    if pgrep -f "mariadbd|mysqld" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Hàm kiểm tra gói MariaDB Server đã được cài đặt trên máy chưa
is_local_db_installed() {
    if command -v mariadbd >/dev/null 2>&1 || command -v mysqld >/dev/null 2>&1; then
        return 0
    fi
    if [ -f /usr/sbin/mariadbd ] || [ -f /usr/sbin/mysqld ] || [ -f /usr/libexec/mariadbd ] || [ -f /usr/libexec/mysqld ]; then
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

# Helper an toàn đọc dữ liệu từ Terminal TTY (chống nuốt script khi chạy curl ... | bash)
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

# 3. Thu thập thông tin cấu hình (Interactive Configuration)
echo -e "\n${CYAN}[*] Bước 2/7: Thiết lập tham số cấu hình hệ thống${NC}"
echo -e "    -> Đang quét dải cổng 9000 - 9999 để tìm cổng khả dụng tối ưu..."
SUGGESTED_PORT=$(find_free_port_in_range 9000 9999)
echo -e "    -> Cổng trống khả dụng gợi ý: ${GREEN}${BOLD}${SUGGESTED_PORT}${NC}"
echo -e "${YELLOW}(Nhấn Enter để tự động sử dụng giá trị gợi ý hoặc nhập cổng theo nhu cầu)${NC}\n"

# Vòng lặp nhập cổng và kiểm tra xung đột
while true; do
    read_input "1. Cổng Web Gateway PAM-CPG [Gợi ý: ${SUGGESTED_PORT}]: " "${SUGGESTED_PORT}" WEB_PORT

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

read_input "2. Tên miền Domain sử dụng (nếu có, VD: pam.company.vn) [Mặc định: ${LOCAL_IP}]: " "${LOCAL_IP}" DOMAIN

# Phát hiện dịch vụ MariaDB / MySQL hiện có trên hệ thống
HAS_EXISTING_DB=false
if is_local_db_running || is_local_db_installed; then
    HAS_EXISTING_DB=true
fi

AUTO_PROVISION_DB=false
INSTALL_DB_PACKAGE=false
ADMIN_DB_USER="root"
ADMIN_DB_PASS=""

if [ "$HAS_EXISTING_DB" = true ]; then
    echo -e "\n    ${YELLOW}⚡ Phát hiện: Máy chủ ĐÃ CÓ sẵn dịch vụ MariaDB / MySQL.${NC}"
    echo -e "    Vui lòng chọn phương thức thiết lập Cơ sở dữ liệu cho PAM-CPG:"
    echo -e "      [1] Tự động tạo Database \`${DEFAULT_DB_NAME}\` & User cho PAM-CPG (Khuyến nghị)."
    echo -e "      [2] Bạn tự cung cấp Database & User đã tạo sẵn từ trước cho PAM-CPG."
    read_input "    -> Nhập lựa chọn [1/2] [Mặc định: 1]: " "1" DB_CHOICE

    if [ "$DB_CHOICE" = "1" ]; then
        ADMIN_DB_USER="root"
        ADMIN_DB_PASS=""

        # Tự động kiểm tra quyền quản trị root qua socket
        if mariadb -u root -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            echo -e "    ${GREEN}✔ Tự động xác thực quyền Quản trị MariaDB (root) qua socket thành công.${NC}"
        else
            while true; do
                read_input "    • Nhập Mật khẩu tài khoản Quản trị MariaDB (root): " "" ADMIN_DB_PASS
                if mariadb -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
                    echo -e "      ${GREEN}✔ Xác thực mật khẩu root thành công!${NC}"
                    break
                else
                    echo -e "      ${RED}[!] Mật khẩu root không chính xác hoặc không thể kết nối. Vui lòng nhập lại!${NC}"
                fi
            done
        fi

        read_input "    • Tên Database muốn tạo [Mặc định: ${DEFAULT_DB_NAME}]: " "${DEFAULT_DB_NAME}" DB_NAME
        read_input "    • Tên User Database muốn tạo [Mặc định: ${DEFAULT_DB_USER}]: " "${DEFAULT_DB_USER}" DB_USER
        DB_PASS="$(generate_random_password)"
        MARIADB_ROOT_PASS="${ADMIN_DB_PASS}"
        DB_HOST="127.0.0.1"
        DB_PORT="3306"
        AUTO_PROVISION_DB=true
        INSTALL_DB_PACKAGE=false
    else
        while true; do
            read_input "    • Địa chỉ máy chủ CSDL (Host) [Mặc định: 127.0.0.1]: " "$DEFAULT_DB_HOST" DB_HOST
            read_input "    • Cổng CSDL (Port) [Mặc định: 3306]: " "$DEFAULT_DB_PORT" DB_PORT
            read_input "    • Tên Cơ sở dữ liệu đã tạo sẵn [Mặc định: ${DEFAULT_DB_NAME}]: " "$DEFAULT_DB_NAME" DB_NAME
            read_input "    • Tên Người dùng Database [Mặc định: ${DEFAULT_DB_USER}]: " "$DEFAULT_DB_USER" DB_USER
            read_input "    • Mật khẩu Database: " "" DB_PASS

            # Kiểm tra kết nối thử tới database đã cung cấp
            MYSQL_AUTH_TEST="-u${DB_USER} -h${DB_HOST} -P${DB_PORT}"
            if [ -n "$DB_PASS" ]; then
                MYSQL_AUTH_TEST="${MYSQL_AUTH_TEST} -p${DB_PASS}"
            fi
            if mariadb $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1 || mysql $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1; then
                echo -e "      ${GREEN}✔ Kết nối tới Database \`${DB_NAME}\` thành công!${NC}"
                break
            else
                echo -e "      ${YELLOW}⚠ Không thể kết nối thử tới Database \`${DB_NAME}\` với thông tin vừa nhập.${NC}"
                read_input "      -> Bạn có muốn thử nhập lại không? (Y/n) [Mặc định: Y]: " "Y" RETRY_DB
                if [[ ! "$RETRY_DB" =~ ^[Yy]$ ]]; then
                    break
                fi
            fi
        done
        MARIADB_ROOT_PASS="[N/A - Database Đã Cấu Hình Sẵn]"
        AUTO_PROVISION_DB=false
        INSTALL_DB_PACKAGE=false
    fi
else
    echo -e "\n    ${CYAN}⚡ Thông báo: Máy chủ CHƯA CÓ dịch vụ MariaDB / MySQL cục bộ.${NC}"
    read_input "3. Tự động cài đặt & cấu hình mới MariaDB Server cục bộ? (Y/n) [Mặc định: Y]: " "Y" INSTALL_LOCAL_DB

    if [[ "$INSTALL_LOCAL_DB" =~ ^[Yy]$ ]]; then
        INSTALL_DB_PACKAGE=true
        AUTO_PROVISION_DB=true
        DB_NAME="${DEFAULT_DB_NAME}"
        DB_USER="${DEFAULT_DB_USER}"
        DB_PASS="$(generate_random_password)"
        MARIADB_ROOT_PASS="$(generate_random_password)"
        DB_HOST="127.0.0.1"
        DB_PORT="3306"
    else
        INSTALL_DB_PACKAGE=false
        AUTO_PROVISION_DB=false
        read_input "    • Địa chỉ máy chủ CSDL Ngoại vi (Host) [Mặc định: 127.0.0.1]: " "$DEFAULT_DB_HOST" DB_HOST
        read_input "    • Cổng CSDL (Port) [Mặc định: 3306]: " "$DEFAULT_DB_PORT" DB_PORT
        read_input "    • Tên Cơ sở dữ liệu [Mặc định: ${DEFAULT_DB_NAME}]: " "$DEFAULT_DB_NAME" DB_NAME
        read_input "    • Tên Người dùng Database [Mặc định: ${DEFAULT_DB_USER}]: " "$DEFAULT_DB_USER" DB_USER
        read_input "    • Mật khẩu Database: " "" DB_PASS
        MARIADB_ROOT_PASS="[N/A - Database Ngoại Vi]"
    fi
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

    if [ "$INSTALL_DB_PACKAGE" = true ] || ( [ "$AUTO_PROVISION_DB" = true ] && ! is_local_db_installed ); then
        echo -e "    -> Đang cài đặt MariaDB Server..."
        apt-get install -y -qq mariadb-server mariadb-client >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    elif ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        apt-get install -y -qq mariadb-client >/dev/null 2>&1 || true
    fi
elif [ "$OS_NAME" = "centos" ] || [ "$OS_NAME" = "rhel" ] || [ "$OS_NAME" = "rocky" ] || [ "$OS_NAME" = "almalinux" ]; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y ffmpeg ca-certificates curl openssl tzdata jq >/dev/null 2>&1
    if [ "$INSTALL_DB_PACKAGE" = true ] || ( [ "$AUTO_PROVISION_DB" = true ] && ! is_local_db_installed ); then
        yum install -y mariadb-server mariadb >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    elif ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        yum install -y mariadb >/dev/null 2>&1 || true
    fi
fi
echo -e "    ${GREEN}✔ Đã cài đặt xong các gói phụ thuộc.${NC}"

# 5. Khởi tạo Cơ sở dữ liệu và phân quyền User DB
if [ "$AUTO_PROVISION_DB" = true ]; then
    echo -e "\n${CYAN}[*] Bước 4/7: Tự động khởi tạo Database \`${DB_NAME}\` và phân quyền User \`${DB_USER}\`...${NC}"
    
    # Đảm bảo MariaDB Server đang chạy và socket sẵn sàng
    if ! is_local_db_running; then
        echo -e "    -> Đang khởi động MariaDB Server..."
        systemctl enable mariadb >/dev/null 2>&1 || systemctl enable mysql >/dev/null 2>&1 || true
        systemctl start mariadb >/dev/null 2>&1 || systemctl start mysql >/dev/null 2>&1 || true
        for i in {1..10}; do
            if is_local_db_running || [ -S /run/mysqld/mysqld.sock ] || [ -S /var/run/mysqld/mysqld.sock ]; then
                break
            fi
            sleep 1
        done
    fi

    MYSQL_CLI="mariadb"
    if ! command -v mariadb >/dev/null 2>&1; then
        MYSQL_CLI="mysql"
    fi

    MYSQL_AUTH_FLAGS="-u${ADMIN_DB_USER}"
    if [ -n "$ADMIN_DB_PASS" ]; then
        MYSQL_AUTH_FLAGS="${MYSQL_AUTH_FLAGS} -p${ADMIN_DB_PASS}"
    fi

    $MYSQL_CLI $MYSQL_AUTH_FLAGS <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    echo -e "    ${GREEN}✔ Database \`${DB_NAME}\` đã được tạo và thiết lập bảo mật thành công!${NC}"
else
    echo -e "\n${CYAN}[*] Bước 4/7: Sử dụng Cơ sở dữ liệu cấu hình sẵn \`${DB_NAME}\`...${NC}"
    echo -e "    ${GREEN}✔ Ghi nhận CSDL Target: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"
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
SETUP_OUTPUT=$("${INSTALL_DIR}/bin/pam-cpg" --setup --db "${DB_DSN}" 2>/dev/null || true)
CLEAN_JSON=$(echo "$SETUP_OUTPUT" | awk '/^{/{flag=1} flag; /^}/{flag=0}')
if [ -z "$CLEAN_JSON" ] || ! echo "$CLEAN_JSON" | jq . >/dev/null 2>&1; then
    CLEAN_JSON="{}"
fi

ADMIN_USER=$(echo "$CLEAN_JSON" | jq -r '.admin_user // "admin"' 2>/dev/null || echo "admin")
ADMIN_PASS=$(echo "$CLEAN_JSON" | jq -r '.admin_pass // "Admin@12345"' 2>/dev/null || echo "Admin@12345")
MFA_SECRET=$(echo "$CLEAN_JSON" | jq -r '.mfa_secret // "Chưa khởi tạo"' 2>/dev/null || echo "Chưa khởi tạo")
MFA_RECOVERY=$(echo "$CLEAN_JSON" | jq -r '.mfa_recovery_code // "Chưa khởi tạo"' 2>/dev/null || echo "Chưa khởi tạo")
SHARE_1=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[0] // ""' 2>/dev/null || echo "")
SHARE_2=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[1] // ""' 2>/dev/null || echo "")
SHARE_3=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[2] // ""' 2>/dev/null || echo "")
RAW_KEY=$(echo "$CLEAN_JSON" | jq -r '.master_key_raw // ""' 2>/dev/null || echo "")

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
