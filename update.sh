#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG / PAM-MQ - ONE-CLICK FAST SYSTEM UPDATER SCRIPT
# Tự động nâng cấp binary mới nhất từ GitHub mà không làm gián đoạn hay mất dữ liệu CSDL
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
if [ ! -d "$INSTALL_DIR" ] && [ -d "/opt/pam-mq" ]; then
    INSTALL_DIR="/opt/pam-mq"
fi

SERVICE_NAME="pam-cpg"
if ! systemctl list-unit-files | grep -q "pam-cpg.service" && systemctl list-unit-files | grep -q "pam-mq.service"; then
    SERVICE_NAME="pam-mq"
fi

GITHUB_REPO="cuongnguyen955/pam-cpg"

clear
echo -e "${CYAN}${BOLD}"
echo "=========================================================================="
echo "          PAM-CPG ENTERPRISE GATEWAY - ONE-CLICK SYSTEM UPDATER          "
echo "                https://github.com/${GITHUB_REPO}                         "
echo "=========================================================================="
echo -e "${NC}"

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Lỗi: Bạn bắt buộc phải chạy script này với quyền root (sudo ./update.sh)${NC}"
    exit 1
fi

# 2. Kiểm tra thư mục cài đặt hiện tại
if [ ! -d "${INSTALL_DIR}/bin" ] || [ ! -f "${INSTALL_DIR}/.env" ]; then
    echo -e "${RED}[!] Lỗi: Không tìm thấy phiên bản cài đặt PAM-CPG tại ${INSTALL_DIR}.${NC}"
    echo -e "${YELLOW}-> Nếu đây là máy chủ mới chưa từng cài đặt, vui lòng chạy lệnh cài đặt mới:${NC}"
    echo -e "   ${CYAN}bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/auto-install.sh?t=\$(date +%s))\"${NC}"
    exit 1
fi

# Đọc cấu hình từ .env
INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR}/.env" | cut -d'=' -f2 | tr -d ' "' || echo "9000")
if [ -z "$INSTALLED_PORT" ]; then
    INSTALLED_PORT="9000"
fi

echo -e "📌 ${BOLD}Thông tin phiên bản hiện tại:${NC}"
echo -e "   • Thư mục cài đặt : ${CYAN}${INSTALL_DIR}${NC}"
echo -e "   • Dịch vụ Systemd : ${CYAN}${SERVICE_NAME}.service${NC}"
echo -e "   • Cổng hoạt động  : ${GREEN}${BOLD}${INSTALLED_PORT}${NC}"
echo ""

# 3. Tải file binary mới nhất từ GitHub
echo -e "${CYAN}[1/4] Đang kiểm tra và tải file thực thi nhị phân mới nhất từ GitHub...${NC}"
TEMP_UPDATE_DIR=$(mktemp -d /tmp/pam-update-XXXXXX)
trap 'rm -rf "${TEMP_UPDATE_DIR}"' EXIT

if [ -f "./pam-cpg" ]; then
    echo -e "      ✔ Sử dụng file thực thi nhị phân cục bộ có sẵn: ./pam-cpg"
    cp -f "./pam-cpg" "${TEMP_UPDATE_DIR}/pam-cpg"
else
    DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/pam-cpg"
    echo -e "      -> Đang tải từ: ${CYAN}${DOWNLOAD_URL}${NC}..."
    curl -fsSL "${DOWNLOAD_URL}?t=$(date +%s)" -o "${TEMP_UPDATE_DIR}/pam-cpg"
    echo -e "      ${GREEN}✔ Tải thành công file nhị phân mới.${NC}"
fi

chmod +x "${TEMP_UPDATE_DIR}/pam-cpg"

# 4. Dừng dịch vụ và sao lưu bản cũ
echo -e "\n${CYAN}[2/4] Đang tạm dừng dịch vụ và sao lưu bản binary trước đó...${NC}"
systemctl stop ${SERVICE_NAME} >/dev/null 2>&1 || true

if [ -f "${INSTALL_DIR}/bin/pam-cpg" ]; then
    cp -f "${INSTALL_DIR}/bin/pam-cpg" "${INSTALL_DIR}/bin/pam-cpg.bak"
    echo -e "      ✔ Đã sao lưu bản binary cũ vào: ${INSTALL_DIR}/bin/pam-cpg.bak"
fi

# 5. Ghi đè file binary mới
echo -e "\n${CYAN}[3/4] Đang cập nhật file thực thi mới vào ${INSTALL_DIR}/bin/...${NC}"
cp -f "${TEMP_UPDATE_DIR}/pam-cpg" "${INSTALL_DIR}/bin/pam-cpg"
chmod +x "${INSTALL_DIR}/bin/pam-cpg"
echo -e "      ${GREEN}✔ Đã cập nhật xong file binary mới.${NC}"

# Đồng bộ lại auto-install và uninstall scripts nếu có
if [ -f "./auto-install.sh" ]; then
    cp -f "./auto-install.sh" "${INSTALL_DIR}/auto-install.sh" 2>/dev/null || true
fi
if [ -f "./uninstall.sh" ]; then
    cp -f "./uninstall.sh" "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
fi

# 6. Khởi động lại dịch vụ
echo -e "\n${CYAN}[4/4] Đang khởi động lại dịch vụ ${SERVICE_NAME}.service...${NC}"
systemctl daemon-reload
systemctl restart ${SERVICE_NAME}
sleep 2

# Kiểm tra trạng thái hoạt động
if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo -e "      ${GREEN}✔ Dịch vụ ${SERVICE_NAME} đã khởi động lại và hoạt động bình thường!${NC}"
else
    echo -e "      ${RED}[!] Cảnh báo: Dịch vụ khởi động chưa thành công, đang kiểm tra log...${NC}"
    journalctl -u ${SERVICE_NAME} -n 15 --no-pager
    exit 1
fi

# Tự động nạp Shamir key nếu có file lưu tạm
if [ -f "${INSTALL_DIR}/config/shamir_keys.json" ]; then
    SHAMIR_1=$(jq -r '.shares[0]' "${INSTALL_DIR}/config/shamir_keys.json" 2>/dev/null || true)
    SHAMIR_2=$(jq -r '.shares[1]' "${INSTALL_DIR}/config/shamir_keys.json" 2>/dev/null || true)
    if [ -n "$SHAMIR_1" ] && [ "$SHAMIR_1" != "null" ]; then
        curl -k -s -X POST "https://127.0.0.1:${INSTALLED_PORT}/api/system/unlock" \
            -H "Content-Type: application/json" \
            -d "{\"shares\": [\"${SHAMIR_1}\", \"${SHAMIR_2}\"]}" >/dev/null 2>&1 || true
    fi
fi

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

echo -e "\n${GREEN}${BOLD}"
echo "=========================================================================="
echo "         🎉 CHÚC MỪNG! HỆ THỐNG PAM-CPG ĐÃ ĐƯỢC NÂNG CẤP THÀNH CÔNG!     "
echo "=========================================================================="
echo -e "${NC}"
echo -e "🌐 ${BOLD}ĐƯỜNG DẪN TRUY CẬP WEB GATEWAY (HTTPS):${NC}"
echo -e "   • ${CYAN}${BOLD}https://${LOCAL_IP}:${INSTALLED_PORT}${NC}"
echo ""
echo -e "🛡️ ${BOLD}GHI CHÚ QUAN TRỌNG:${NC}"
echo -e "   • Toàn bộ Cơ sở dữ liệu, User, Nhóm quyền, Cấu hình và Nhật ký đều được ${GREEN}${BOLD}BẢO TOÀN 100%${NC}."
echo -e "   • GORM Auto-Migrate đã tự động cập nhật các bảng dữ liệu mới nhất."
echo -e "==========================================================================\n"
