# PAM-CPG: Centralized Enterprise Privileged Access Management Gateway

<p align="center">
  <img src="https://img.shields.io/badge/Version-1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/Go-1.25.3-00ADD8.svg" alt="Go Version">
  <img src="https://img.shields.io/badge/Svelte-Vite-FF3E00.svg" alt="Frontend">
  <img src="https://img.shields.io/badge/MariaDB-10.6+-003545.svg" alt="Database">
  <img src="https://img.shields.io/badge/Security-AES--256--GCM%20%7C%20Shamir%20%7C%20TOTP%20MFA-green.svg" alt="Security">
</p>

> **PAM-CPG (Centralized Privileged Access Management Gateway)** là giải pháp Cổng Quản lý Truy cập Đặc quyền cấp Doanh nghiệp (Enterprise Jump Host Gateway), kiểm soát, bảo vệ và ghi hình toàn bộ các phiên làm việc qua giao thức **SSH, RDP (HTML5), Telnet, Web Proxy, SFTP & FTP** tới hạ tầng máy chủ và thiết bị mạng.

---

## 🌟 TÍNH NĂNG NỔI BẬT (KEY FEATURES)

* 🛡️ **Quản lý Đa Giao Thức (Multi-Protocol Gateway):**
  * **SSH Terminal:** Hỗ trợ đầy đủ máy chủ Linux hiện đại lẫn các thiết bị mạng **Cisco, Router, Switch đời cũ** (tương thích `diffie-hellman-group1-sha1`, `aes-cbc`, `3des-cbc`, `keyboard-interactive`).
  * **RDP HTML5 Web:** Truy cập máy chủ Windows trực tiếp trên trình duyệt, không cần cài đặt thêm phần mềm client, tích hợp tính năng truyền tập tin hai chiều và ghim/chuyển tab mượt mà.
  * **Telnet & Serial COM:** Quản trị các thiết bị mạng truyền thống.
  * **Web Forwarding:** Truy cập giao diện quản trị Web (iLO, iDRAC, vCenter, Router UI) an toàn qua kênh Proxy mã hóa.
  * **SFTP & FTP File Manager:** Trình duyệt file đồ họa kéo-thả, chỉnh sửa file trực tiếp từ xa (Remote File Editor).
* 🔐 **Bảo Mật Cấp Doanh Nghiệp (Zero Trust & Cryptography):**
  * **Kho khóa Credential Vault:** Mã hóa toàn bộ mật khẩu và SSH Private Key bằng thuật toán **AES-256-GCM**.
  * **Phân mảnh khóa Shamir (Shamir's Secret Sharing 2-of-3):** Master Key chỉ tồn tại trong RAM, bảo vệ hệ thống tuyệt đối khi khởi động lại máy chủ.
  * **Xác thực 2 lớp bắt buộc (TOTP MFA):** Hỗ trợ Google Authenticator, Microsoft Authenticator kèm mã khôi phục (Recovery Codes).
* 🏢 **Tích hợp Danh tính Tập trung (Enterprise IAM & SSO):**
  * **Active Directory / LDAP:** Xác thực tài khoản người dùng miền, phân quyền theo Group/OU, đồng bộ tài nguyên tự động.
  * **Microsoft 365 (Azure AD / Entra ID SSO):** Đăng nhập một chạm OAuth2/OIDC, **tìm kiếm nhóm trực tiếp trên server (Server-side Group Search)** và đồng bộ danh bạ thông minh.
* ⏱️ **Phê duyệt Truy cập Tức thời (Just-In-Time - JIT Access Approval):**
  * Luồng yêu cầu & phê duyệt quyền truy cập tạm thời có giới hạn thời gian (15 phút, 1 giờ, 8 giờ...). Tự động thu hồi quyền ngay khi hết hạn.
* 🎥 **Kiểm toán & Giám sát Phiên Thời gian Thực (Auditing & Session Recording):**
  * **Ghi hình phiên MP4 tự động:** Ghi lại toàn bộ thao tác màn hình RDP và dòng lệnh SSH dưới dạng video MP4 và nhật ký văn bản.
  * **Giám sát trực tiếp (Real-time Shadowing):** Cho phép Quản trị viên xem trực tiếp màn hình người dùng đang thao tác và ngắt phiên ngay lập tức khi phát hiện hành vi khả nghi.
  * **Cron Retention:** Tự động dọn dẹp log và video hết hạn theo chính sách lưu trữ.

---

## ⚡ 1. CÀI ĐẶT TỰ ĐỘNG 1 LỆNH DUY NHẤT (ONE-CLICK INSTALLATION)

Hệ thống được đóng gói thành file thực thi độc lập `pam-cpg`. Bạn chỉ cần chạy **1 dòng lệnh duy nhất** trên máy chủ Linux (Ubuntu 20.04/22.04/24.04, Debian 11/12, RHEL, CentOS, Rocky Linux...):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuongnguyen955/pam-cpg/main/auto-install.sh)"
```

> **Hoặc clone kho mã nguồn về và cài đặt:**
> ```bash
> git clone https://github.com/cuongnguyen955/pam-cpg.git
> cd pam-cpg
> sudo ./auto-install.sh
> ```

### 🚀 Quy trình script `auto-install.sh` tự động thực hiện:
1. Tạo thư mục chuẩn hệ thống tại `/opt/PAM-CPG/`.
2. Tự động cài đặt `ffmpeg`, `openssl`, `curl`, `jq` và các gói phụ thuộc.
3. Tự động cài đặt và cấu hình **MariaDB Server** với cơ chế bảo mật tối đa.
4. Tự động sinh chứng chỉ **SSL HTTPS 10 năm** (3650 ngày) hỗ trợ đa tên miền và IP SAN.
5. Cấu hình tài khoản Quản trị viên ban đầu `admin` / `Admin@12345`, sinh mã **MFA TOTP** và **3 Mảnh Khóa Shamir (2-of-3)**.
6. Đăng ký và kích hoạt dịch vụ Systemd `pam-cpg.service` tự khởi động cùng OS.
7. Xuất toàn bộ thông tin bàn giao ra màn hình và lưu trữ tại `/opt/PAM-CPG/CREDENTIALS.txt`.

---

## 🔄 2. NÂNG CẤP HỆ THỐNG 1-CLICK (FAST SYSTEM UPDATER)

Khi có bản phát hành mới trên GitHub, bạn chỉ cần chạy **1 lệnh duy nhất** để tự động cập nhật binary mới nhất **mà không làm gián đoạn hay mất dữ liệu CSDL**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuongnguyen955/pam-cpg/main/update.sh)"
```

> **Hoặc chạy trực tiếp trên máy chủ:**
> ```bash
> cd /opt/PAM-CPG
> sudo ./update.sh
> ```

---

## 🗑️ 3. GỠ CÀI ĐẶT HỆ THỐNG (CLEAN UNINSTALL)

Nếu cần gỡ bỏ hoàn toàn hệ thống để cài đặt lại:

```bash
cd /opt/PAM-CPG
sudo ./uninstall.sh
```

---

## 🛠️ 4. QUẢN LÝ DỊCH VỤ HỆ THỐNG

```bash
# Kiểm tra trạng thái hoạt động
systemctl status pam-cpg

# Xem nhật ký hoạt động thời gian thực (Real-time Logs)
journalctl -u pam-cpg -f

# Khởi động lại dịch vụ
systemctl restart pam-cpg

# Dừng dịch vụ
systemctl stop pam-cpg
```

---

## 📁 5. CẤU TRÚC THƯ MỤC HỆ THỐNG (`/opt/PAM-CPG/`)

```text
/opt/PAM-CPG/
├── bin/
│   ├── pam-cpg                   # File thực thi nhị phân chính của Gateway
│   └── pam-cpg.bak               # Bản sao lưu tự động trước khi nâng cấp
├── certs/
│   ├── server.crt                # Chứng chỉ SSL HTTPS (10 năm)
│   └── server.key                # Khóa bí mật SSL HTTPS
├── shared/
│   ├── recordings/               # Thư mục lưu trữ video ghi hình phiên (.mp4)
│   └── command_logs/             # Thư mục lưu trữ nhật ký câu lệnh PTY (.log)
├── .env                          # File cấu hình biến môi trường và chuỗi kết nối DB
├── auto-install.sh               # Script cài đặt tự động
├── update.sh                     # Script nâng cấp tự động
├── uninstall.sh                  # Script gỡ cài đặt sạch sẽ
└── CREDENTIALS.txt               # File lưu trữ thông tin bàn giao, MFA & Shamir Shares
```

---

## 🔑 6. THÔNG TIN TRUY CẬP BAN ĐẦU (INITIAL ACCESS)

* **Địa chỉ truy cập Web:** `https://<IP_MAY_CHU>:9000`
* **Tài khoản mặc định:**
  * **Tên đăng nhập:** `admin`
  * **Mật khẩu:** `Admin@12345`
* **Xác thực 2 bước (MFA):** Mở ứng dụng Google Authenticator hoặc Microsoft Authenticator trên điện thoại, quét mã QR hiển thị trong file `/opt/PAM-CPG/CREDENTIALS.txt` hoặc nhập mã khóa bí mật (Secret Key).
* **Mở khóa Shamir:** Nhập tối thiểu **2 trong 3 mảnh khóa** được cấp trong file `CREDENTIALS.txt` để mở khóa hệ thống.

---

## 📜 7. BẢN QUYỀN & LIÊN HỆ

* **Phát triển bởi:** Đội ngũ Kỹ thuật PAM-CPG.
* **Mã nguồn phát hành:** [https://github.com/cuongnguyen955/pam-cpg](https://github.com/cuongnguyen955/pam-cpg)
* **Kho mã nguồn riêng:** [https://github.com/cuongnguyen955/PAM-MQ](https://github.com/cuongnguyen955/PAM-MQ)
