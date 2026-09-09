#!/usr/bin/env bash
# ==============================================================================
# PAM-CPG - ONE-CLICK ENTERPRISE STANDALONE AUTO INSTALLER
# Repository: https://github.com/cuongnguyen955/pam-cpg
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
SERVICE_NAME="pam-cpg"
DEFAULT_WEB_PORT="8083"
DEFAULT_DB_NAME="pamcpg"
DEFAULT_DB_USER="pamcpg"
DEFAULT_DB_PORT="3306"
DEFAULT_DB_HOST="127.0.0.1"
GITHUB_REPO="cuongnguyen955/pam-cpg"

# Function to check if a port is currently in use
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

# Function to check if local MariaDB/MySQL is running
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

# Function to check if MariaDB Server package is installed
is_local_db_installed() {
    if command -v mariadbd >/dev/null 2>&1 || command -v mysqld >/dev/null 2>&1; then
        return 0
    fi
    if [ -f /usr/sbin/mariadbd ] || [ -f /usr/sbin/mysqld ] || [ -f /usr/libexec/mariadbd ] || [ -f /usr/libexec/mysqld ]; then
        return 0
    fi
    return 1
}

# Function to scan and find the first available free port in range
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

# Function to generate secure random password
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

# 1. Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Error: You must run this script with root privileges (sudo ./auto-install.sh)${NC}"
    exit 1
fi

# 2. OS Detection
echo -e "${CYAN}[*] Step 1/7: Checking operating system environment...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    echo -e "    -> Detected OS: ${GREEN}${NAME} (${VERSION_ID:-latest})${NC}"
else
    OS_NAME="unknown"
    echo -e "${YELLOW}[!] Using generic Linux configuration.${NC}"
fi

# Get host server IP address
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="127.0.0.1"
fi

# Safe helper for reading TTY input (handles curl | bash piped executions)
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

# Check if PAM-CPG is ALREADY installed on this server
if [ -f "${INSTALL_DIR}/.env" ] && [ -f "${INSTALL_DIR}/bin/pam-cpg" ]; then
    echo -e "\n${YELLOW}${BOLD}⚡ DETECTED EXISTING PAM-CPG INSTALLATION ON THIS SERVER!${NC}"
    echo -e "    Please select execution mode:"
    echo -e "      [1] UPGRADE SYSTEM (In-Place Fast Update) - Preserves 100% of existing DB & Config. (Recommended)"
    echo -e "      [2] FRESH INSTALLATION / FULL RESET (Fresh Re-install)."
    read_input "    -> Your choice [1/2] [Default: 1]: " "1" RUN_MODE

    if [ "$RUN_MODE" = "1" ]; then
        echo -e "\n${CYAN}-> Switching to Safe System Update Mode...${NC}"
        if [ -f "./update.sh" ]; then
            exec bash "./update.sh"
        else
            exec bash -c "$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/update.sh?t=$(date +%s))"
        fi
        exit 0
    fi
fi

# 3. Interactive Configuration Gathering
echo -e "\n${CYAN}[*] Step 2/7: Configuring system parameters${NC}"
echo -e "    -> Scanning port range 9000 - 9999 for available free ports..."
SUGGESTED_PORT=$(find_free_port_in_range 9000 9999)
echo -e "    -> Suggested free port: ${GREEN}${BOLD}${SUGGESTED_PORT}${NC}"
echo -e "${YELLOW}(Press Enter to accept suggested port or specify your preferred port)${NC}\n"

# Loop for port input and conflict validation
while true; do
    read_input "1. PAM-CPG Web Gateway Port [Suggested: ${SUGGESTED_PORT}]: " "${SUGGESTED_PORT}" WEB_PORT

    # Validate integer range 1-65535
    if ! [[ "$WEB_PORT" =~ ^[0-9]+$ ]] || [ "$WEB_PORT" -lt 1 ] || [ "$WEB_PORT" -gt 65535 ]; then
        echo -e "    ${RED}[!] Error: Port must be an integer between 1 and 65535. Please try again!${NC}"
        continue
    fi

    # Check port collision
    if is_port_in_use "$WEB_PORT"; then
        echo -e "    ${RED}[!] Warning: Port ${WEB_PORT} is currently in use by another application!${NC}"
        echo -e "    ${YELLOW}    -> Press Enter to use suggested port [${SUGGESTED_PORT}] or specify another port.${NC}"
    else
        echo -e "    ${GREEN}✔ Port ${WEB_PORT} is valid and available.${NC}"
        break
    fi
done

read_input "2. Domain name / Hostname (optional, e.g. pam.company.com) [Default: ${LOCAL_IP}]: " "${LOCAL_IP}" DOMAIN

# Detect if active MariaDB / MySQL service is currently running on the host
HAS_ACTIVE_DB=false
if is_local_db_running; then
    # Verify if port 3306 or socket is actively responding
    if (timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/3306") >/dev/null 2>&1 || [ -S /run/mysqld/mysqld.sock ] || [ -S /var/run/mysqld/mysqld.sock ]; then
        HAS_ACTIVE_DB=true
    fi
fi

AUTO_PROVISION_DB=false
INSTALL_DB_PACKAGE=false
ADMIN_DB_USER="root"
ADMIN_DB_PASS=""

if [ "$HAS_ACTIVE_DB" = true ]; then
    echo -e "\n    ${YELLOW}⚡ Notice: Active MariaDB / MySQL service detected on this server.${NC}"
    
    # Ensure CLI client is available for testing
    if ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        echo -e "    -> Ensuring database client tools are installed..."
        if [ "$OS_NAME" = "ubuntu" ] || [ "$OS_NAME" = "debian" ]; then
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y -qq mariadb-client >/dev/null 2>&1 || true
        elif [ "$OS_NAME" = "centos" ] || [ "$OS_NAME" = "rhel" ] || [ "$OS_NAME" = "rocky" ] || [ "$OS_NAME" = "almalinux" ]; then
            yum install -y mariadb >/dev/null 2>&1 || true
        fi
    fi

    echo -e "    Please select database setup method for PAM-CPG:"
    echo -e "      [1] Automatically create Database \`${DEFAULT_DB_NAME}\` & dedicated User for PAM-CPG (Recommended)."
    echo -e "      [2] Use an existing pre-created Database & User for PAM-CPG."
    read_input "    -> Enter choice [1/2] [Default: 1]: " "1" DB_CHOICE

    if [ "$DB_CHOICE" = "1" ]; then
        ADMIN_DB_USER="root"
        ADMIN_DB_PASS=""

        # Test root socket auth first
        if mariadb -u root -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            echo -e "    ${GREEN}✔ Verified MariaDB Admin (root) permissions via unix socket (No password required).${NC}"
        else
            while true; do
                read_input "    • Enter MariaDB Admin (root) password: " "" ADMIN_DB_PASS
                
                local DB_CHECK_ERR=""
                if [ -z "$ADMIN_DB_PASS" ]; then
                    if mariadb -u root -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
                        echo -e "      ${GREEN}✔ Root permissions verified successfully via unix socket!${NC}"
                        break
                    else
                        DB_CHECK_ERR=$(mariadb -u root -e "SELECT 1;" 2>&1 || mysql -u root -e "SELECT 1;" 2>&1 || true)
                    fi
                else
                    if mariadb -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
                        echo -e "      ${GREEN}✔ Root password verified successfully!${NC}"
                        break
                    else
                        DB_CHECK_ERR=$(mariadb -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" 2>&1 || mysql -u root -p"${ADMIN_DB_PASS}" -e "SELECT 1;" 2>&1 || true)
                    fi
                fi

                echo -e "      ${RED}[!] Cannot connect to MariaDB:${NC} ${DB_CHECK_ERR}"
                read_input "      -> Would you like to retry? (Y/n) [Default: Y]: " "Y" RETRY_ROOT_PASS
                if [[ ! "$RETRY_ROOT_PASS" =~ ^[Yy]$ ]]; then
                    echo -e "      ${YELLOW}-> Switching to option [2]: Use pre-created Database & User.${NC}"
                    DB_CHOICE="2"
                    break
                fi
            done
        fi

        if [ "$DB_CHOICE" = "1" ]; then
            DB_NAME="${DEFAULT_DB_NAME}"
            DB_USER="${DEFAULT_DB_USER}"
            DB_PASS="$(generate_random_password)"
            MARIADB_ROOT_PASS="${ADMIN_DB_PASS:-[Unix Socket / Unchanged]}"
            DB_HOST="127.0.0.1"
            DB_PORT="3306"
            AUTO_PROVISION_DB=true
            INSTALL_DB_PACKAGE=false
        fi
    fi

    if [ "$DB_CHOICE" = "2" ]; then
        while true; do
            read_input "    • Database Host [Default: 127.0.0.1]: " "$DEFAULT_DB_HOST" DB_HOST
            read_input "    • Database Port [Default: 3306]: " "$DEFAULT_DB_PORT" DB_PORT
            read_input "    • Pre-created Database Name [Default: ${DEFAULT_DB_NAME}]: " "${DEFAULT_DB_NAME}" DB_NAME
            read_input "    • Database Username [Default: ${DEFAULT_DB_USER}]: " "${DEFAULT_DB_USER}" DB_USER
            read_input "    • Database Password: " "" DB_PASS

            # Test connection to provided database
            MYSQL_AUTH_TEST="-u${DB_USER} -h${DB_HOST} -P${DB_PORT}"
            if [ -n "$DB_PASS" ]; then
                MYSQL_AUTH_TEST="${MYSQL_AUTH_TEST} -p${DB_PASS}"
            fi
            if mariadb $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1 || mysql $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1; then
                echo -e "      ${GREEN}✔ Connected to Database \`${DB_NAME}\` successfully!${NC}"
                break
            else
                local USER_DB_ERR=""
                USER_DB_ERR=$(mariadb $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" 2>&1 || mysql $MYSQL_AUTH_TEST -e "USE \`${DB_NAME}\`;" 2>&1 || true)
                echo -e "      ${YELLOW}⚠ Cannot connect to Database \`${DB_NAME}\`: ${USER_DB_ERR}${NC}"
                read_input "      -> Would you like to retry? (Y/n) [Default: Y]: " "Y" RETRY_DB
                if [[ ! "$RETRY_DB" =~ ^[Yy]$ ]]; then
                    break
                fi
            fi
        done
        MARIADB_ROOT_PASS="[N/A - Pre-configured Database]"
        AUTO_PROVISION_DB=false
        INSTALL_DB_PACKAGE=false
    fi
else
    # CLEAN / FRESH SERVER: Zero questions asked. Everything automated!
    echo -e "\n    ${GREEN}✔ No active MySQL/MariaDB service detected.${NC}"
    echo -e "    -> Installer will automatically install, configure, and secure local MariaDB Server."
    INSTALL_DB_PACKAGE=true
    AUTO_PROVISION_DB=true
    ADMIN_DB_USER="root"
    ADMIN_DB_PASS=""
    DB_NAME="${DEFAULT_DB_NAME}"
    DB_USER="${DEFAULT_DB_USER}"
    DB_PASS="$(generate_random_password)"
    MARIADB_ROOT_PASS="$(generate_random_password)"
    DB_HOST="127.0.0.1"
    DB_PORT="3306"
fi

DB_DSN="${DB_USER}:${DB_PASS}@tcp(${DB_HOST}:${DB_PORT})/${DB_NAME}?charset=utf8mb4&parseTime=True&loc=Local"

echo -e "\n${GREEN}✔ Recorded configuration parameters:${NC}"
echo -e "  • Web Gateway Port : ${BOLD}${WEB_PORT}${NC}"
echo -e "  • Domain / Host IP : ${BOLD}${DOMAIN}${NC}"
echo -e "  • Database Target  : ${BOLD}${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"

# 4. Install dependencies (FFmpeg, MariaDB, OpenSSL, curl, jq, IPRoute2)
echo -e "\n${CYAN}[*] Step 3/7: Installing system dependencies (FFmpeg, OpenSSL, MariaDB, JQ, IPRoute2)...${NC}"

# If UFW is active on strict deny-outgoing policy, allow essential outbound traffic for installation first
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow out 53 >/dev/null 2>&1 || true
    ufw allow out 123/udp >/dev/null 2>&1 || true
    ufw allow out 80/tcp >/dev/null 2>&1 || true
    ufw allow out 443/tcp >/dev/null 2>&1 || true
fi

if [ "$OS_NAME" = "ubuntu" ] || [ "$OS_NAME" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    # Ensure universe repository is enabled on Ubuntu 22.04 / 24.04 / 26.04
    if [ "$OS_NAME" = "ubuntu" ]; then
        apt-get install -y -qq software-properties-common >/dev/null 2>&1 || true
        add-apt-repository -y universe >/dev/null 2>&1 || true
    fi
    apt-get update -qq
    apt-get install -y -qq ffmpeg ca-certificates curl openssl tzdata jq iproute2 >/dev/null 2>&1

    if [ "$INSTALL_DB_PACKAGE" = true ] || ( [ "$AUTO_PROVISION_DB" = true ] && ! is_local_db_installed ); then
        echo -e "    -> Installing MariaDB Server..."
        apt-get install -y -qq mariadb-server mariadb-client >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    elif ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        apt-get install -y -qq mariadb-client >/dev/null 2>&1 || true
    fi
elif [ "$OS_NAME" = "centos" ] || [ "$OS_NAME" = "rhel" ] || [ "$OS_NAME" = "rocky" ] || [ "$OS_NAME" = "almalinux" ]; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y ffmpeg ca-certificates curl openssl tzdata jq iproute >/dev/null 2>&1
    if [ "$INSTALL_DB_PACKAGE" = true ] || ( [ "$AUTO_PROVISION_DB" = true ] && ! is_local_db_installed ); then
        yum install -y mariadb-server mariadb >/dev/null 2>&1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl start mariadb >/dev/null 2>&1
    elif ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        yum install -y mariadb >/dev/null 2>&1 || true
    fi
fi
echo -e "    ${GREEN}✔ System dependencies installed successfully.${NC}"

# 5. Initialize Database and User Grants
if [ "$AUTO_PROVISION_DB" = true ]; then
    echo -e "\n${CYAN}[*] Step 4/7: Initializing Database \`${DB_NAME}\` and granting permissions to User \`${DB_USER}\`...${NC}"
    
    # Ensure MariaDB Server is active and socket is ready
    if ! is_local_db_running; then
        echo -e "    -> Starting MariaDB Server..."
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

    # Set root password for fresh local MariaDB install
    if [ "$INSTALL_DB_PACKAGE" = true ] && [ -n "$MARIADB_ROOT_PASS" ]; then
        $MYSQL_CLI $MYSQL_AUTH_FLAGS <<EOF >/dev/null 2>&1 || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF
    fi

    echo -e "    ${GREEN}✔ Database \`${DB_NAME}\` initialized and secured successfully!${NC}"
else
    echo -e "\n${CYAN}[*] Step 4/7: Using pre-configured Database \`${DB_NAME}\`...${NC}"
    echo -e "    ${GREEN}✔ Target Database: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"
fi

# 6. Create system directory structure and deploy pam-cpg binary
echo -e "\n${CYAN}[*] Step 5/7: Creating directory structure and deploying binary to ${INSTALL_DIR}...${NC}"
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/certs"
mkdir -p "${INSTALL_DIR}/config"
mkdir -p "${INSTALL_DIR}/shared/recordings"
mkdir -p "${INSTALL_DIR}/shared/command_logs"

# Deploy binary executable: prioritize local file, fallback to GitHub
if [ -f "./pam-cpg" ]; then
    cp -f "./pam-cpg" "${INSTALL_DIR}/bin/pam-cpg"
elif [ -f "./PAM-MQ" ]; then
    cp -f "./PAM-MQ" "${INSTALL_DIR}/bin/pam-cpg"
elif [ -f "./build/bin/PAM-MQ" ]; then
    cp -f "./build/bin/PAM-MQ" "${INSTALL_DIR}/bin/pam-cpg"
else
    echo -e "    -> Downloading executable \`pam-cpg\` from GitHub (${GITHUB_REPO})..."
    curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/pam-cpg" -o "${INSTALL_DIR}/bin/pam-cpg"
fi

chmod +x "${INSTALL_DIR}/bin/pam-cpg"

# Deploy update and helper scripts into installation directory
if [ -f "./update.sh" ]; then
    cp -f "./update.sh" "${INSTALL_DIR}/update.sh"
else
    curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/update.sh" -o "${INSTALL_DIR}/update.sh" 2>/dev/null || true
fi
chmod +x "${INSTALL_DIR}/update.sh" 2>/dev/null || true

if [ -f "./uninstall.sh" ]; then
    cp -f "./uninstall.sh" "${INSTALL_DIR}/uninstall.sh"
else
    curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/uninstall.sh" -o "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
fi
chmod +x "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true

# 7. Generate 10-year SSL Certificate (3650 days)
echo -e "\n${CYAN}[*] Step 6/7: Generating 10-Year SSL Certificate (3650 days)...${NC}"
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
echo -e "    ${GREEN}✔ Generated 10-Year SSL Certificate at ${INSTALL_DIR}/certs/${NC}"

# Create .env configuration file
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

# 8. Run Setup mode to initialize DB, Admin, MFA Secret, Recovery Code & 3 Shamir Master Key Shares
echo -e "\n${CYAN}[*] Step 7/7: Initializing Security Engine (Admin, MFA TOTP & 3 Shamir Master Key Shares)...${NC}"
SETUP_OUTPUT=$("${INSTALL_DIR}/bin/pam-cpg" --setup --db "${DB_DSN}" 2>/dev/null || true)
CLEAN_JSON=$(echo "$SETUP_OUTPUT" | awk '/^{/{flag=1} flag; /^}/{flag=0}')
if [ -z "$CLEAN_JSON" ] || ! echo "$CLEAN_JSON" | jq . >/dev/null 2>&1; then
    CLEAN_JSON="{}"
fi

ADMIN_USER=$(echo "$CLEAN_JSON" | jq -r '.admin_user // "admin"' 2>/dev/null || echo "admin")
ADMIN_PASS=$(echo "$CLEAN_JSON" | jq -r '.admin_pass // "Admin@12345"' 2>/dev/null || echo "Admin@12345")
MFA_SECRET=$(echo "$CLEAN_JSON" | jq -r '.mfa_secret // "Not Initialized"' 2>/dev/null || echo "Not Initialized")
MFA_RECOVERY=$(echo "$CLEAN_JSON" | jq -r '.mfa_recovery_code // "Not Initialized"' 2>/dev/null || echo "Not Initialized")
SHARE_1=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[0] // ""' 2>/dev/null || echo "")
SHARE_2=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[1] // ""' 2>/dev/null || echo "")
SHARE_3=$(echo "$CLEAN_JSON" | jq -r '.shamir_shares[2] // ""' 2>/dev/null || echo "")
RAW_KEY=$(echo "$CLEAN_JSON" | jq -r '.master_key_raw // ""' 2>/dev/null || echo "")

# Save secret credentials to secure handover file
cat <<EOF > "${INSTALL_DIR}/CREDENTIALS.txt"
==========================================================================
              PAM-CPG ENTERPRISE SYSTEM HANDOVER CREDENTIALS
==========================================================================
1. WEB PORTAL ACCESS:
   • HTTPS URL      : https://${DOMAIN}:${WEB_PORT} (or https://${LOCAL_IP}:${WEB_PORT})
   • Admin Username : ${ADMIN_USER}
   • Admin Password : ${ADMIN_PASS}

2. TWO-FACTOR AUTHENTICATION (MFA / TOTP):
   • MFA Secret Key (Add to Google Authenticator / Authy): ${MFA_SECRET}
   • MFA Recovery Code (Use to reset MFA if lost)       : ${MFA_RECOVERY}

3. MARIADB DATABASE DETAILS:
   • Database Name       : ${DB_NAME}
   • Database User       : ${DB_USER}
   • Database Password   : ${DB_PASS}
   • MariaDB Root Pass   : ${MARIADB_ROOT_PASS}
   • Connection DSN      : ${DB_DSN}

4. 3 SHAMIR MASTER KEY SHARES (REQUIRES 2-OF-3 SHARES TO UNLOCK):
   • Key Share 1 (Share 1) : ${SHARE_1}
   • Key Share 2 (Share 2) : ${SHARE_2}
   • Key Share 3 (Share 3) : ${SHARE_3}
   • Master Key Raw (RAM)  : ${RAW_KEY}
==========================================================================
EOF
chmod 600 "${INSTALL_DIR}/CREDENTIALS.txt"

# Register and start Systemd Service
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
ExecStart=${INSTALL_DIR}/bin/pam-cpg --web
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
systemctl restart ${SERVICE_NAME}

# Configure UFW firewall if enabled (supporting strict IN/OUT deny policies)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo -e "\n${CYAN}[*] Configuring UFW Firewall rules (IN & OUT for strict security policies)...${NC}"
    
    # 1. INCOMING RULES (Clients & Admins to PAM-CPG)
    ufw allow ${WEB_PORT}/tcp comment "PAM-CPG Web Portal & API (HTTPS/WSS)" >/dev/null 2>&1 || true
    ufw allow 2121/tcp comment "PAM-CPG RDP FTP Sharing Control" >/dev/null 2>&1 || true
    ufw allow 30000:30100/tcp comment "PAM-CPG RDP FTP Passive Data Ports" >/dev/null 2>&1 || true
    ufw allow 22/tcp comment "SSH Server Management" >/dev/null 2>&1 || true

    # 2. OUTGOING RULES (PAM-CPG to Target Devices & Infrastructure)
    ufw allow out 53 comment "DNS Resolution (UDP/TCP)" >/dev/null 2>&1 || true
    ufw allow out 123/udp comment "NTP Time Synchronization" >/dev/null 2>&1 || true
    ufw allow out 80,443/tcp comment "HTTP/HTTPS (Apt, GitHub, SSO Azure/Google, Web Proxy)" >/dev/null 2>&1 || true
    ufw allow out 22/tcp comment "PAM Target SSH/SFTP" >/dev/null 2>&1 || true
    ufw allow out 3389/tcp comment "PAM Target Windows RDP" >/dev/null 2>&1 || true
    ufw allow out 23/tcp comment "PAM Target Telnet" >/dev/null 2>&1 || true
    ufw allow out 5900:5910/tcp comment "PAM Target VNC" >/dev/null 2>&1 || true
    ufw allow out 20,21/tcp comment "PAM Target FTP" >/dev/null 2>&1 || true
    ufw allow out 389,636/tcp comment "PAM Target LDAP/LDAPS (Active Directory)" >/dev/null 2>&1 || true
    ufw allow out 25,465,587/tcp comment "PAM Outbound SMTP/SMTPS Mail Alerts" >/dev/null 2>&1 || true
    if [ "$DB_HOST" != "127.0.0.1" ] && [ "$DB_HOST" != "localhost" ]; then
        ufw allow out ${DB_PORT}/tcp comment "PAM External MariaDB/MySQL Database" >/dev/null 2>&1 || true
    fi

    echo -e "    ${GREEN}✔ Configured UFW rules (IN: ${WEB_PORT}, 2121, 30000-30100, 22 | OUT: DNS, NTP, HTTP/S, SSH, RDP, Telnet, VNC, FTP, LDAP, SMTP).${NC}"
fi

# Auto-unlock Shamir key immediately upon initial install
sleep 2
curl -k -s -X POST "https://127.0.0.1:${WEB_PORT}/api/system/unlock" \
    -H "Content-Type: application/json" \
    -d "{\"shares\": [\"${SHARE_1}\", \"${SHARE_2}\"]}" >/dev/null 2>&1 || true

# 9. Print formatted handover table to terminal
echo -e "\n${GREEN}${BOLD}"
echo "=========================================================================="
echo "       🎉 CONGRATULATIONS! PAM-CPG HAS BEEN INSTALLED & STARTED!          "
echo "=========================================================================="
echo -e "${NC}"

echo -e "🌐 ${BOLD}WEB GATEWAY ACCESS URL (HTTPS):${NC}"
echo -e "   • ${CYAN}${BOLD}https://${DOMAIN}:${WEB_PORT}${NC} (or ${CYAN}https://${LOCAL_IP}:${WEB_PORT}${NC})"
echo ""
echo -e "👤 ${BOLD}DEFAULT ADMINISTRATOR ACCOUNT:${NC}"
echo -e "   • Username : ${BOLD}${ADMIN_USER}${NC}"
echo -e "   • Password : ${BOLD}${ADMIN_PASS}${NC}"
echo ""
echo -e "🔑 ${BOLD}TWO-FACTOR AUTHENTICATION (MFA / TOTP):${NC}"
echo -e "   • ${YELLOW}MFA Secret Key (TOTP)${NC} : ${BOLD}${MFA_SECRET}${NC}"
echo -e "     *(Add this Secret Key to Google Authenticator or Authy to get 6-digit OTP codes)*"
echo -e "   • ${YELLOW}MFA Recovery Code    ${NC} : ${BOLD}${MFA_RECOVERY}${NC}"
echo -e "     *(Use this code on the login page to recover account if you lose your phone)*"
echo ""
echo -e "🗄️  ${BOLD}MARIADB DATABASE DETAILS:${NC}"
echo -e "   • Database Host & Port  : ${BOLD}${DB_HOST}:${DB_PORT}${NC}"
echo -e "   • Database Name         : ${BOLD}${DB_NAME}${NC}"
echo -e "   • Database User         : ${BOLD}${DB_USER}${NC}"
echo -e "   • Database Password     : ${BOLD}${DB_PASS}${NC}"
echo -e "   • MariaDB Root Password : ${BOLD}${MARIADB_ROOT_PASS}${NC}"
echo ""
echo -e "🛡️  ${BOLD}3 SHAMIR MASTER KEY SHARES (SAVE THESE TO UNLOCK UPON SERVER REBOOT):${NC}"
echo -e "   • ${PURPLE}Key Share 1 (Share 1)${NC} : ${BOLD}${SHARE_1}${NC}"
echo -e "   • ${PURPLE}Key Share 2 (Share 2)${NC} : ${BOLD}${SHARE_2}${NC}"
echo -e "   • ${PURPLE}Key Share 3 (Share 3)${NC} : ${BOLD}${SHARE_3}${NC}"
echo -e "   *(System requires at least 2 of the 3 shares to unlock on startup)*"
echo ""
echo -e "📁 ${BOLD}SECURE CREDENTIALS HANDOVER FILE:${NC}"
echo -e "   • File: ${BOLD}${INSTALL_DIR}/CREDENTIALS.txt${NC}"
echo "=========================================================================="
