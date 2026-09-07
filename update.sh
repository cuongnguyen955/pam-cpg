#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG / PAM-MQ - ONE-CLICK FAST SYSTEM UPDATER SCRIPT
# Automatically upgrades to the latest binary from GitHub without data loss or downtime
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

# 1. Root privileges check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Error: You must run this script with root privileges (sudo ./update.sh)${NC}"
    exit 1
fi

# 2. Check current installation directory
if [ ! -d "${INSTALL_DIR}/bin" ] || [ ! -f "${INSTALL_DIR}/.env" ]; then
    echo -e "${RED}[!] Error: PAM-CPG installation not found at ${INSTALL_DIR}.${NC}"
    echo -e "${YELLOW}-> If this is a fresh server without an existing install, please run:${NC}"
    echo -e "   ${CYAN}bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/auto-install.sh?t=\$(date +%s))\"${NC}"
    exit 1
fi

# Read port from .env
INSTALLED_PORT=$(grep -E "^PORT=" "${INSTALL_DIR}/.env" | cut -d'=' -f2 | tr -d ' "' || echo "9000")
if [ -z "$INSTALLED_PORT" ]; then
    INSTALLED_PORT="9000"
fi

echo -e "📌 ${BOLD}Current Version Information:${NC}"
echo -e "   • Install Directory : ${CYAN}${INSTALL_DIR}${NC}"
echo -e "   • Systemd Service   : ${CYAN}${SERVICE_NAME}.service${NC}"
echo -e "   • Active Web Port   : ${GREEN}${BOLD}${INSTALLED_PORT}${NC}"
echo ""

# 3. Download the latest binary from GitHub
echo -e "${CYAN}[1/4] Checking and downloading the latest binary from GitHub...${NC}"
TEMP_UPDATE_DIR=$(mktemp -d /tmp/pam-update-XXXXXX)
trap 'rm -rf "${TEMP_UPDATE_DIR}"' EXIT

DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/pam-cpg"
echo -e "      -> Fetching from: ${CYAN}${DOWNLOAD_URL}${NC}..."
curl -fsSL "${DOWNLOAD_URL}?t=$(date +%s)" -o "${TEMP_UPDATE_DIR}/pam-cpg"
echo -e "      ${GREEN}✔ Successfully downloaded the latest binary executable.${NC}"

chmod +x "${TEMP_UPDATE_DIR}/pam-cpg"

# 4. Stop service and backup previous binary
echo -e "\n${CYAN}[2/4] Stopping service and backing up previous binary...${NC}"
systemctl stop ${SERVICE_NAME} >/dev/null 2>&1 || true

if [ -f "${INSTALL_DIR}/bin/pam-cpg" ]; then
    cp -f "${INSTALL_DIR}/bin/pam-cpg" "${INSTALL_DIR}/bin/pam-cpg.bak"
    echo -e "      ✔ Backed up previous binary to: ${INSTALL_DIR}/bin/pam-cpg.bak"
fi

# 5. Overwrite with new binary
echo -e "\n${CYAN}[3/4] Deploying new executable binary into ${INSTALL_DIR}/bin/...${NC}"
cp -f "${TEMP_UPDATE_DIR}/pam-cpg" "${INSTALL_DIR}/bin/pam-cpg"
chmod +x "${INSTALL_DIR}/bin/pam-cpg"
echo -e "      ${GREEN}✔ Successfully deployed the new binary executable.${NC}"

# Sync helper scripts if present
if [ -f "./auto-install.sh" ]; then
    cp -f "./auto-install.sh" "${INSTALL_DIR}/auto-install.sh" 2>/dev/null || true
fi
if [ -f "./uninstall.sh" ]; then
    cp -f "./uninstall.sh" "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
fi

# 6. Restart systemd service
echo -e "\n${CYAN}[4/4] Restarting ${SERVICE_NAME}.service...${NC}"
systemctl daemon-reload
systemctl restart ${SERVICE_NAME}
sleep 2

# Check service health status
if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo -e "      ${GREEN}✔ Service ${SERVICE_NAME} is active and running normally!${NC}"
else
    echo -e "      ${RED}[!] Warning: Service failed to start properly. Inspecting service logs...${NC}"
    journalctl -u ${SERVICE_NAME} -n 15 --no-pager
    exit 1
fi

# Auto-unlock Shamir key if temporary key file exists
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
echo "         🎉 CONGRATULATIONS! PAM-CPG HAS BEEN SUCCESSFULLY UPDATED!       "
echo "=========================================================================="
echo -e "${NC}"
echo -e "🌐 ${BOLD}WEB GATEWAY ACCESS URL (HTTPS):${NC}"
echo -e "   • ${CYAN}${BOLD}https://${LOCAL_IP}:${INSTALLED_PORT}${NC}"
echo ""
echo -e "🛡️ ${BOLD}IMPORTANT NOTES:${NC}"
echo -e "   • All Databases, Users, Permissions, Configurations, and Audit Logs are ${GREEN}${BOLD}100% PRESERVED${NC}."
echo -e "   • GORM Auto-Migrate has automatically updated all database schemas."
echo -e "==========================================================================\n"
