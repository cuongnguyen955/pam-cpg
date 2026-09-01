# PAM-CPG: Centralized Enterprise Privileged Access Management Gateway

> **PAM-CPG** là hệ thống Cổng Quản lý Truy cập Đặc quyền (Jump Host Gateway) cấp doanh nghiệp, kiểm soát và bảo vệ toàn bộ kết nối SSH, RDP, Telnet, Web, SFTP/FTP tới hệ thống máy chủ và thiết bị mạng.

---

## ⚡ CÀI ĐẶT TỰ ĐỘNG 1-CLICK (ONE-CLICK INSTALLATION)

Hệ thống được đóng gói thành file thực thi duy nhất `pam-cpg`. Bạn chỉ cần chạy **1 dòng lệnh duy nhất** trên máy chủ Linux (Ubuntu, Debian, RHEL, CentOS, Rocky Linux...):

```bash
curl -sSL https://raw.githubusercontent.com/cuongnguyen955/pam-cpg/main/auto-install.sh | sudo bash
```

Hoặc tải repository về và chạy:

```bash
git clone https://github.com/cuongnguyen955/pam-cpg.git
cd pam-cpg
sudo ./auto-install.sh
```

---

## 🚀 QUY TRÌNH TỰ ĐỘNG CỦA SCRIPT `auto-install.sh`

1. **Khởi tạo thư mục chuẩn:** Tạo `/opt/PAM-CPG/` và các thư mục con (`bin`, `certs`, `config`, `shared/recordings`, `shared/command_logs`).
2. **Cài đặt các gói phụ thuộc:** Tự động cài đặt `ffmpeg`, `ca-certificates`, `openssl`, `curl`, `tzdata`, `jq`.
3. **Cài đặt & Thiết lập CSDL MariaDB:**
   - Tự động cài đặt `mariadb-server`.
   - Sinh mật khẩu ngẫu nhiên độ an toàn cao cho tài khoản `root` và user `pamcpg`.
   - Khởi tạo Database `pamcpg` chuẩn mã hóa `utf8mb4` và cấp quyền toàn diện.
4. **Tự Động Sinh Chứng Chỉ SSL 10 Năm:**
   - Sử dụng OpenSSL tạo chứng chỉ tự ký (`server.crt`, `server.key`) thời hạn 3650 ngày có hỗ trợ đầy đủ SAN cho Localhost, IP máy chủ và Tên miền Domain.
5. **Khởi Tạo Hệ Thống Bảo Mật & Thông Tin Xác Thực:**
   - Tự động cấu hình tài khoản Quản trị viên mặc định `admin` / `Admin@12345`.
   - Tự động tạo mã bí mật **MFA Secret Key (TOTP)** và mã khôi phục **MFA Recovery Code**.
   - Tự động sinh **3 Mảnh Khóa Master Key Shamir (2-of-3 Threshold)** để bảo vệ kho khóa đặc quyền AES-256-GCM.
6. **Đăng ký Dịch Vụ Systemd (`pam-cpg.service`):** Tự động kích hoạt dịch vụ chạy ngầm cùng hệ điều hành.
7. **In Toàn Bộ Thông Tin Bàn Giao:** In nổi bật ra màn hình và lưu trữ bảo mật tại `/opt/PAM-CPG/CREDENTIALS.txt`.

---

## 🛠️ QUẢN LÝ DỊCH VỤ SAU KHI CÀI ĐẶT

```bash
# Kiểm tra trạng thái
systemctl status pam-cpg

# Xem nhật ký hoạt động (Real-time logs)
journalctl -u pam-cpg -f

# Khởi động lại dịch vụ
systemctl restart pam-cpg

# Dừng dịch vụ
systemctl stop pam-cpg
```

---

## 📄 CẤU TRÚC THƯ MỤC CÀI ĐẶT (`/opt/PAM-CPG/`)

```text
/opt/PAM-CPG/
├── bin/
│   └── pam-cpg                   # File thực thi duy nhất của hệ thống
├── certs/
│   ├── server.crt                # Chứng chỉ SSL HTTPS (10 năm)
│   └── server.key                # Khóa bí mật SSL HTTPS
├── shared/
│   ├── recordings/               # Nơi lưu trữ tệp video ghi hình (.mp4)
│   └── command_logs/             # Nơi lưu trữ nhật ký câu lệnh PTY (.log)
├── .env                          # File cấu hình biến môi trường
└── CREDENTIALS.txt               # File lưu trữ thông tin bàn giao, MFA & Shamir Shares
```
