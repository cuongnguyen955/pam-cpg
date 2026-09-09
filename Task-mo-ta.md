# TÀI LIỆU ĐẶC TẢ KIẾN TRÚC & GIẢI PHÁP KỸ THUẬT (TASK-MO-TA.MD)
## TÀI LIỆU BÀN GIAO KỸ THUẬT DỰ ÁN PAM-MQ / PAM-CPG ENTERPRISE GATEWAY

Tài liệu này đặc tả chi tiết kiến trúc hệ thống, sơ đồ khối, giải pháp kỹ thuật, thuật toán, danh mục API, hệ thống i18n đa ngôn ngữ, chuẩn hóa giao diện Lucide Icons, quy chuẩn đóng gói và **quy trình phát hành - cập nhật 4 bước bắt buộc** của hệ thống **PAM-MQ (Centralized Privileged Access Management Gateway)** nhằm phục vụ công tác phát triển, vận hành, bảo trì và bàn giao (Handover).

---

## 1. KIẾN TRÚC TỔNG THỂ (JUMP HOST GATEWAY MODEL)

Hệ thống hoạt động dưới dạng **Cổng truy cập trung gian (Jump Host Gateway)**. Người dùng cuối không bao giờ được phép kết nối trực tiếp đến các máy chủ mục tiêu. Mọi kết nối bắt buộc phải đi qua Server PAM-MQ và chịu sự giám sát tuyệt đối.

### 1.1. Sơ đồ khối các thành phần (Component Architecture)

```
        +-----------------------------------------------------------------+
        |                         Trình duyệt Web                         |
        |  (Frontend Svelte SPA - User Workspace / Admin Console Hubs)    |
        |       - Hệ thống Đa ngôn ngữ (i18n EN / VI)                     |
        |       - Vector Icon chuẩn hóa (Lucide Icons + UserAvatar)       |
        +-------------------------------+---------------------------------+
                                        | REST API (HTTPS) & WebSocket (WSS)
                                        v
        +-----------------------------------------------------------------+
        |                        PAM-MQ Server Web                        |
        |              (Backend Go Echo Framework v4 Standalone)          |
        +-------+---------------+---------------+---------------+---------+
                |               |               |               |
                v               v               v               v
        +-------+-----+  +------+-----+  +------+---------+  +--+---------+
        |  Identity   |  | Credential |  | Audit Engine   |  | Notification
        |   Engine    |  |   Vault    |  | (AST Command / |  |   Engine   |
        | (LDAP/OIDC) |  | (AES-GCM)  |  | RDP Recorder)  |  | (SMTP/Mail)|
        +-------+-----+  +------+-----+  +------+---------+  +------------+
                |               |               |
                v               v               v
        +-------+-----+  +------+-----+  +------+---------+
        | Active Srv  |  |  MariaDB   |  | Target Devices |
        |  Directory  |  |  Database  |  | (SSH/RDP/Web)  |
        +-------------+  +------------+  +----------------+
```

### 1.2. Phân tách Cổng UI: User Workspace & Hubs Quản trị Chuyên Biệt

Hệ thống phân quyền thông qua JWT Role để hiển thị giao diện phù hợp:
1.  **User Workspace (Giao diện người dùng cuối):** Thiết kế tối giản, trực quan. Chỉ hiển thị các Card Session mà User được gán quyền (không hiển thị mật khẩu/key). Người dùng click để kết nối thẳng qua Web Terminal/RDP Viewer. Khi gặp thiết bị yêu cầu JIT, giao diện chuyển hướng mở modal gửi yêu cầu phê duyệt.
2.  **Admin Console (Cấu trúc Hubs Quản trị chuyên biệt):** Dành cho Quản trị viên (Admin) và Kiểm toán viên (Auditor):
    *   **Identity Hub:** Quản lý Người dùng (`AdminUsersTab.svelte`), Quản lý Vai trò RBAC (`AdminRolesTab.svelte`), Đồng bộ Active Directory / LDAP (`AdminLdapTab.svelte`), Cấu hình SSO OIDC (`AdminSsoTab.svelte`).
    *   **Resources Hub:** Quản lý Danh sách Thiết bị kết nối (`AdminSessionsTab.svelte` - hỗ trợ Import/Export Excel), Quản lý Nhóm Thiết bị theo phân vùng (`AdminGroupsTab.svelte`).
    *   **Access & Policies Hub:** Phân quyền Trực tiếp Cá nhân (`AdminAssignmentsTab.svelte`), Phân quyền Nhóm Linh Hoạt (`AdminGroupsTab.svelte`), Trung tâm Phê duyệt JIT (`AdminApprovalDashboard.svelte`), Bộ lọc Lệnh cấm AST (`AdminBlockedCommandsTab.svelte`).
    *   **Audit & SOC Hub:** Giám sát Phiên Real-time Live (`AdminAuditTab.svelte` - Shadowing / Terminate), Lịch sử Nhật ký Kiểm toán (Audit Logs, Video MP4 player).
    *   **Settings Hub:** Kho khóa Mật khẩu Đặc quyền (`AdminVaultTab.svelte`), Cấu hình Cảnh báo Email SMTP, Chính sách Lưu trữ Storage Quota, Cấu hình Syslog SIEM ngoại vi, Cấu hình Tham số Hệ thống.

### 1.3. Ma trận Phân quyền & Vai trò (Role-Based Access Control Matrix)

Hệ thống PAM-MQ phân quyền dựa trên vai trò người dùng (RBAC). Dưới đây là ma trận phân quyền chi tiết của 3 vai trò mặc định trong hệ thống:

| Mã quyền | Tên quyền hạn | Mô tả chức năng | Administrator (`r1`) | Auditor (`r2`) | User (`r3`) |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `p1` | `user.manage` | Quản trị người dùng (Tạo/Sửa/Khóa/Gán vai trò) | ✅ | ❌ | ❌ |
| `p2` | `session.manage` | Quản trị thiết bị kết nối (Sessions/Excel Import) | ✅ | ❌ | ❌ |
| `p3` | `session.connect` | Được quyền kết nối tới thiết bị đích | ✅ | ❌ | ✅ |
| `p4` | `audit.view` | Xem danh sách nhật ký Audit Logs & Tải video | ✅ | ✅ | ❌ |
| `p5` | `audit.shadow` | Shadowing (Xem trực tiếp phiên kết nối đang hoạt động) | ✅ | ✅ | ❌ |
| `p6` | `audit.terminate` | Ngắt phiên kết nối khẩn cấp của user khác | ✅ | ✅ | ❌ |
| `p7` | `vault.manage` | Quản trị kho lưu trữ tài khoản/mật khẩu (Vault) | ✅ | ❌ | ❌ |
| `p8` | `storage.manage` | Cấu hình dung lượng lưu trữ & Chính sách dọn dẹp log | ✅ | ❌ | ❌ |

### 1.4. Mô hình Phân Quyền Hai Lớp (Dual-Layer Access Matrix RBAC & ABAC)

Hệ thống hỗ trợ song song 2 cơ chế phân quyền truy cập máy chủ:
1. **Lớp 1 - Phân quyền Trực tiếp Cá nhân (Direct Assignment):**
   - Ánh xạ trực tiếp $1:1$ giữa `User` $\to$ `Session` $\to$ `Vault Credential`.
   - Phù hợp cho các trường hợp cấp phát đặc thù cho từng cá nhân riêng lẻ.
2. **Lớp 2 - Phân quyền Theo Nhóm Linh Hoạt (Group-Based Assignment):**
   - Ánh xạ theo ma trận: **Bên A** (`User` hoặc `UserGroup`) $\to$ **Bên B** (`Session` hoặc `DeviceGroup`) $\to$ `Vault Credential` $\to$ `JIT Policy`.
   - Khi kiểm tra quyền kết nối, Gateway tự động hợp nhất (Union) quyền từ cả 2 lớp, cho phép gom nhóm quản lý hàng trăm máy chủ và người dùng theo phòng ban/dự án một cách dễ dàng.

---

## 2. THUẬT TOÁN VÀ GIẢI PHÁP KỸ THUẬT CÁC MODULE CỐT LÕI

### 2.1. Module Xác thực & MFA (Identity Auth)

#### A. Cấu trúc Cơ sở dữ liệu và SQLite Fallback (Database Schema)
Hệ thống sử dụng **GORM ORM** để tương tác với cơ sở dữ liệu MariaDB 11/12. Để đảm bảo khả năng chạy thử nghiệm và khả dụng cao khi mất kết nối MariaDB, backend Go tự động kích hoạt chế độ **SQLite Fallback** sang tệp cơ sở dữ liệu cục bộ `/opt/PAM-CPG/config/pam_cpg_sqlite.db`.

1.  **Bảng `users` (Thông tin người dùng):**
    *   `id` (VARCHAR(36), Primary Key): UUID định danh người dùng.
    *   `username` (VARCHAR(50), Unique Index): Tên đăng nhập.
    *   `password_hash` (VARCHAR(255)): Mã băm Bcrypt mật khẩu thô (rỗng đối với LDAP users).
    *   `email` (VARCHAR(100)): Hòm thư điện tử.
    *   `fullname` (VARCHAR(100)): Họ tên đầy đủ.
    *   `auth_source` (VARCHAR(20)): Nguồn xác thực (`local` hoặc `ldap`).
    *   `status` (TINYINT): Trạng thái tài khoản (`1` - Active, `2` - Locked, `3` - Disabled).
    *   `mfa_enabled` (BOOLEAN): Trạng thái kích hoạt bảo mật 2 lớp.
    *   `mfa_secret` (VARCHAR(100)): Mã TOTP secret được mã hóa.
    *   `mfa_recovery_code` (VARCHAR(50)): Mã khôi phục 12 chữ số (`xxxx-xxxx-xxxx`).
    *   `last_login_at` (DATETIME): Thời gian đăng nhập cuối cùng.
    *   `login_failures` (INT): Số lần đăng nhập sai liên tiếp hiện tại.

2.  **Bảng `roles` & `permissions`:**
    *   `roles`: `id` (`r1`, `r2`, `r3`), `name`, `description`.
    *   `permissions`: `id` (`p1` - `p8`), `code`, `name`.
    *   Ánh xạ qua `user_role_map` và `role_permission_map`.

3.  **Bảng `login_attempts` (Nhật ký thử đăng nhập):**
    *   `id`, `ip_address`, `username`, `attempt_time`, `status` (`success`/`failed`).

#### B. Xác thực mật khẩu Local (Bcrypt) & Cấp phát JWT Session
*   **Mã hóa:** Mật khẩu người dùng được băm bằng thuật toán **Bcrypt** với `cost = 12` (`golang.org/x/crypto/bcrypt`).
*   **JWT Token Lifecycle:** Khi đăng nhập thành công, cấp JWT Token ký bằng **HMAC-SHA256**, payload chứa `userId`, `username`, `permissions` (danh sách quyền gom từ tất cả roles). Hạn dùng **8 giờ**.

#### C. Quy trình xác thực Active Directory LDAP & Tự động khởi tạo (Auto-provisioning)
Tích hợp Active Directory qua **`github.com/go-ldap/ldap/v3`** theo thuật toán Two-Stage Bind:
1.  **Stage 1 - Bind Service:** Kết nối tới Domain Controller, bind bằng `BindDN` quản trị để lấy quyền tìm kiếm.
2.  **Stage 2 - Search DN:** Tìm kiếm `(&(objectClass=user)(sAMAccountName=username))` để lấy Distinguished Name (DN) thực tế của user.
3.  **Stage 3 - Bind User Auth:** Thực hiện bind thứ 2 bằng chính **User DN thực tế** và mật khẩu thô của user.
4.  **Auto-provisioning logic:** Tự động tạo bản ghi user trong bảng `users` với `auth_source = "ldap"`, điền `email`, `fullname` và gán vai trò mặc định **`User` (r3)**.

#### D. Brute-Force & Lockout
*   Ghi nhận log vào `login_attempts`. Đăng nhập sai làm tăng `login_failures`.
*   Khi `login_failures >= 5`, tự động khóa `status = 2` (Locked) và từ chối `403 Forbidden` đến khi Admin mở khóa.

#### E. TOTP Multi-Factor Authentication (MFA) & Self-Reset Recovery Code
*   **Thư viện:** Sử dụng `github.com/pquerna/otp` sinh Secret Base32 và QR Code PNG.
*   **Đăng nhập 2 bước:** Bước 1 đúng mật khẩu $\to$ Cấp `tempToken` (hạn 3 phút lưu trong `sync.Map`). Bước 2 nhập OTP 6 số lên `/api/auth/mfa/verify-login` $\to$ Cấp JWT chính thức.
*   **Bắt buộc MFA:** Mọi tài khoản trong hệ thống bắt buộc kích hoạt MFA. Nếu chưa có `MFASecret`, hệ thống chuyển hướng bắt buộc cấu hình tại Portal.
*   **Mã khôi phục 12 chữ số (Recovery Code):** Khi quét QR code, sinh mã ngẫu nhiên dạng `xxxx-xxxx-xxxx`. Nếu mất điện thoại, người dùng tự nhập mã này tại `/api/auth/mfa/recover` để reset MFA và quét lại mã mới.

---

### 2.2. Kho khóa bảo mật (Credential Vault) & Khôi phục Thảm họa Shamir (SSS)

*   **Mã hóa Vault:** Sử dụng **AES-256-GCM** (`crypto/cipher`). Mỗi mật khẩu/key được sinh IV (Nonce) 12 bytes ngẫu nhiên, mã hóa cùng Auth Tag 16 bytes và lưu trữ dạng `LONGBLOB`.
*   **Phân mảnh Master Key Shamir (SSS):** Sử dụng `github.com/hashicorp/vault/sdk/helper/shamir` chia Master Key thành **3 mảnh (Key Shares)** với ngưỡng `t = 2`.
*   Khi Server khởi động lại, Master Key biến mất khỏi RAM. Quản trị viên nhập 2/3 mảnh khóa qua API `/api/system/unlock` để kích hoạt lại cổng PAM.

---

### 2.3. Công cụ lọc câu lệnh SSH Terminal (PTY AST Filter)

1.  **ANSI Escape Stripping:** Lọc bỏ toàn bộ mã điều hướng/màu sắc terminal khỏi luồng bytes PTY.
2.  **Line Buffering:** Tích lũy ký tự vào Line Buffer, đóng gói khi gặp `\r` hoặc `\n`.
3.  **AST Parsing:** Dùng `github.com/mvdan/sh/v3/syntax` phân tích dòng lệnh thành Abstract Syntax Tree.
4.  **Context-Aware Analysis:** Đi bộ trên cây AST để kiểm tra `Command.Name`, các tham số và đường dẫn đích. Chặn các lệnh nguy hiểm (như `rm -rf /`, truy cập `/etc/shadow`...).

---

### 2.4. Ghi hình RDP phía Server & Chống Nghẽn Phiên (Server-side RDP Recording)

*   Chặn bắt frame hình ảnh Bitmap từ engine RDP tại Backend Go.
*   Nén video chuyển động bằng **H.264** qua FFmpeg pipe, lưu trữ thành tệp tin `.mp4` tại `shared/recordings/{AuditLog.ID}.mp4`.
*   **Tối ưu hiệu năng:** Khung hình ~6.6 FPS (150ms/frame), scale 50% độ phân giải và chất lượng JPEG 40%.
*   **Chống nghẽn:** Non-blocking channel buffer kích thước **`2048`**. Tự động drop frame video nếu CPU quá tải để giữ phiên làm việc của người dùng mượt mà, đồng thời bật cờ `recording_has_gaps = true` vào database.

---

### 2.5. Giám sát thời gian thực & Live Shadowing (One-Time Token Security)

*   **Active Session Registry:** Quản lý danh sách kết nối đang hoạt động trong `sync.Map`.
*   **WebSocket Shadowing (Pub/Sub):** Nhân bản luồng output từ phiên của user sang kênh kết nối Read-Only của Auditor với buffer size **`256`**.
*   **One-Time Token (OTT):** Auditor gọi POST để lấy OTT (hạn 10s), kết nối WebSocket qua `?ticket=OTT_TICKET`. Server tiêu thụ vé bằng **`LoadAndDelete` nguyên tử** để chống replay attack.
*   **Session Termination:** API `/api/admin/audit/active-sessions/:id/terminate` đóng cưỡng bức kết nối socket.

---

### 2.6. Quy trình Yêu cầu và Phê duyệt Truy cập JIT (Access Request Workflow)

*   **Database Schema:** Bảng `access_requests` ghi nhận `requested_start`, `requested_end`, `granted_start`, `granted_end`.
*   **Server-Side Time Enforcement:** `RequestedStart` và `GrantedStart` luôn lấy theo giờ thực tế tại máy chủ ở thời điểm gửi/duyệt.
*   **Real-time Revocation Timer:** Sử dụng `time.AfterFunc` kết hợp database transaction khóa dòng **`FOR UPDATE`** (`Where("id = ? AND status = 2", reqID)`) làm Idempotency Guard để tự động thu hồi quyền chính xác đến từng giây.
*   **Cron & Restart Recovery:** Cron scheduler quét mỗi phút và hàm `RecoverJITTimersAfterRestart` khôi phục lại các timer khi server khởi động lại.

---

### 2.7. Cơ chế Nhập / Xuất Danh Sách Thiết Bị Qua Excel (Excel Batch Processing & Auto Vault Linking)

1. **Xuất Excel:** Chuyển đổi toàn bộ danh sách `Session` từ DB sang định dạng bảng tính `.xlsx` qua thư viện `xlsx` (SheetJS), bao gồm thông tin `Credential Vault` đang liên kết với từng thiết bị.
2. **Tải File Mẫu:** Cung cấp file mẫu `.xlsx` chuẩn có sẵn các cột thuộc tính: `Tên thiết bị`, `Địa chỉ IP / Host`, `Cổng (Port)`, `Giao thức (SSH/RDP/TELNET/WEB/FTP/SFTP)`, `Tài khoản mặc định`, `Mật khẩu`, và cột **`Credential Vault`**.
3. **Nhập Excel, Tự Động Tạo Kho Khóa & Liên Kết Thiết Bị (Auto Vault Creation & Mapping):**
   - Người dùng tải file `.xlsx` lên $\to$ Frontend hiển thị **Preview Modal** để kiểm tra tính hợp lệ và danh sách `Credential Vault` trước khi xác nhận.
   - Gửi payload lên API `POST /api/admin/sessions/batch-import`.
   - **Tự động xử lý Credential Vault:**
     - Nếu dòng dữ liệu có khai báo cột **`Credential Vault`**, Backend sẽ tra cứu trong DB:
       - **Nếu Vault chưa tồn tại:** Tự động tạo mới bản ghi `CredentialVault` với tên Vault tương ứng, lưu tài khoản/mật khẩu được mã hóa an toàn **AES-256-GCM** và gán ID của Vault vào `s.CredentialIDs` của thiết bị.
       - **Nếu Vault đã tồn tại:** Tự động lấy ID của Vault đó gán vào thiết bị (và cập nhật mật khẩu Vault nếu người dùng chọn tùy chọn Ghi đè - `overwrite`).
     - Khi lưu cấu hình `config.SaveConfig(cfg)`, bảng quan hệ `SessionCredentialMap` tự động đồng bộ liên kết thiết bị với Credential Vault.
   - **Bảo mật:** Toàn bộ mật khẩu thiết bị và mật khẩu trong Kho khóa Vault đều được mã hóa bằng thuật toán **AES-256-GCM** sử dụng Master Key của hệ thống.

---

### 2.8. Hệ Thống Đa Ngôn Ngữ Song Ngữ Toàn Diện (i18n Engine - EN & VI)

Toàn bộ hệ thống giao diện được chuẩn hóa song ngữ **Tiếng Anh (English)** và **Tiếng Việt (Vietnamese)**:
1. **Kiến trúc Module i18n:**
   - Đặt tại `frontend/src/lib/i18n/index.ts` kết hợp hai từ điển `locales/en.json` và `locales/vi.json`.
   - Cung cấp Svelte Store `$t(key, params)` hỗ trợ tìm kiếm key lồng nhau (`nav.dashboard`, `users.modal.title`) và nội suy biến động `{name}`, `{count}`, `{seconds}`.
2. **Quản lý Cấu hình Ngôn ngữ:**
   - Ngôn ngữ được lưu bền vững trong `localStorage.getItem('pam_language')`.
   - Thiết lập chọn ngôn ngữ được tích hợp vào Modal Cài đặt Người dùng (`UserProfileModal.svelte`).
3. **Script Kiểm tra Tự động (`scripts/check-i18n.sh`):**
   - Tự động đối soát và phát hiện các key bị thiếu (missing keys) hoặc lệch cấu trúc giữa `en.json` và `vi.json` trước khi build.

---

### 2.9. Hệ Thống Icon Chuẩn Hóa Lucide Icons & Component Avatar (`UserAvatar.svelte`)

1. **Chuẩn hóa Bộ Icon Vector:**
   - Thay thế toàn bộ các emoji và icon legacy bằng thư viện vector chuyên nghiệp **`lucide-svelte`**.
   - Phục vụ đồng nhất các chức năng: Bảo mật (`Shield`, `Lock`, `Key`), Quản trị (`Users`, `Server`, `Settings`, `Terminal`), Trạng thái (`CheckCircle`, `AlertTriangle`, `XCircle`), Phân trang & Điều hướng.
2. **Component Avatar Người Dùng Chuẩn Hóa (`UserAvatar.svelte`):**
   - Đặt tại `frontend/src/components/common/UserAvatar.svelte`.
   - Thay thế cơ chế tạo avatar từ 2 chữ cái viết tắt bằng biểu tượng vector `User` mặc định hiện đại.
   - Hỗ trợ các kích cỡ chuẩn (`xs`, `sm`, `md`, `lg`, `xl`) và tích hợp badge hiển thị vai trò người dùng (Admin, Auditor, User).

---

### 2.10. Quy Chuẩn Đóng Gói Component Bảng Dùng Chung (`DataTable.svelte`)

Tất cả các màn hình bảng danh sách trong PAM-MQ **bắt buộc sử dụng component dùng chung** [`frontend/src/components/common/DataTable.svelte`](file:///root/PAM-MQ/frontend/src/components/common/DataTable.svelte).

#### A. Bảng Thông Số Thuộc Tính (Props Specification)

| Tên Prop | Kiểu dữ liệu | Mặc định | Ý nghĩa & Mô tả |
| :--- | :--- | :--- | :--- |
| `items` | `T[]` | `[]` | Mảng dữ liệu nguồn cần hiển thị trên bảng. |
| `columns` | `Column[]` | `[]` | Mảng định nghĩa các cột hiển thị (Xem chi tiết interface `Column`). |
| `itemKey` | `string` | `'id'` | Tên trường khóa chính duy nhất của từng dòng (dùng cho checkbox selection). |
| `searchFields` | `string[]` | `[]` | Danh sách các trường dữ liệu dùng để tìm kiếm realtime. |
| `searchPlaceholder` | `string` | `'Tìm kiếm...'` | Gợi ý văn bản trong ô tìm kiếm. |
| `pageSize` | `number` | `20` | Số dòng hiển thị trên một trang (Mặc định chuẩn: **20 dòng**). |
| `pageSizeOptions` | `number[]` | `[10, 20, 50, 100]` | Danh sách tùy chọn số dòng hiển thị trên một trang trong dropdown. |
| `selectable` | `boolean` | `false` | Bật/tắt tính năng chọn checkbox nhiều dòng. |
| `selectedIds` | `string[]` | `[]` | Danh sách ID các dòng đang được chọn (Hỗ trợ `bind:selectedIds`). |
| `loading` | `boolean` | `false` | Trạng thái hiển thị hiệu ứng xoay tải dữ liệu (Loading skeleton/spinner). |
| `customFilterFn` | `(item: T) => boolean` | `null` | Hàm lọc dữ liệu tùy chỉnh kết hợp cùng các dropdown bên ngoài. |
| `title` | `string` | `''` | Tiêu đề khối bảng. |
| `subtitle` | `string` | `''` | Mô tả phụ bên dưới tiêu đề. |
| `badge` | `string` | `''` | Huy hiệu nhỏ hiển thị cạnh tiêu đề (VD: `AES-256 Vault`, `Real-time SOC`). |
| `emptyText` | `string` | `'Không có dữ liệu'` | Văn bản hiển thị khi danh sách trống. |
| `emptySubText` | `string` | `''` | Hướng dẫn thao tác khi danh sách trống. |

#### B. Định Nghĩa Cấu Trúc Cột (`interface Column`)

```typescript
export interface Column {
  key: string;              // Tên trường định danh cột
  label: string;            // Tiêu đề hiển thị trên thanh Header
  sortable?: boolean;       // Cho phép sắp xếp tăng/giảm theo cột này (true/false)
  width?: string;           // Độ rộng cố định của cột (VD: '120px', '200px')
  align?: 'left' | 'center' | 'right'; // Căn lề nội dung (Mặc định 'left')
  headerClass?: string;     // Class CSS bổ sung cho thẻ <th>
}
```

#### C. Quy Chuẩn Nghiệp Vụ Bắt Buộc
1. **Phân trang (Pagination):** Mặc định **20 dòng / trang**, có dropdown tùy chọn `[10, 20, 50, 100]` và thanh điều hướng đầy đủ `<< < 1 2 3 > >>`.
2. **Tìm kiếm realtime:** Tìm kiếm không dấu / không phân biệt hoa thường trên toàn bộ mảng `searchFields`.
3. **Thao tác hàng loạt (Batch Actions):** Checkbox Header hỗ trợ chọn toàn bộ trang hoặc toàn bộ kết quả lọc, tự động mở rộng Batch Actions Bar.

---

## 3. QUY TRÌNH PHÁT HÀNH & CẬP NHẬT 4 BƯỚC BẮT BUỘC (RELEASE & DEPLOYMENT WORKFLOW)

Để đảm bảo chất lượng, tính toàn vẹn của mã nguồn và sự thông suốt của hệ thống máy chủ thật, **mọi phiên bản phát triển đều phải tuân thủ nghiêm ngặt theo quy trình 4 bước tuần tự**:

```
+---------------------------------------------------------------------------------+
| BƯỚC 1: Build ứng dụng thành 1 file nhị phân duy nhất (Standalone Binary)       |
| cd /root/PAM-MQ && bash build-package.sh  ->  /root/PAM-MQ/build/bin/PAM-MQ     |
+---------------------------------------+-----------------------------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
| BƯỚC 2: Đồng bộ file nhị phân và script qua Git Public (pam-cpg)                |
| cp -f build/bin/PAM-MQ /root/PAM-CPG/pam-cpg && cp scripts /root/PAM-CPG/      |
+---------------------------------------+-----------------------------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
| BƯỚC 3: Push lên cả 2 kho Git (Private PAM-MQ & Public pam-cpg)                |
| - Git Private: cd /root/PAM-MQ && git add . && git commit && git push          |
| - Git Public:  cd /root/PAM-CPG && git add . && git commit && git push         |
+---------------------------------------+-----------------------------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
| BƯỚC 4: Chạy lệnh Update ở Git Public để cập nhật dịch vụ máy chủ hiện tại     |
| cd /root/PAM-CPG && ./update.sh  -> Tải binary, backup .bak, restart service    |
+---------------------------------------------------------------------------------+
```

### Chi tiết các bước thực hiện:

1. **Bước 1 (Build Standalone Binary):**
   ```bash
   cd /root/PAM-MQ
   bash build-package.sh
   ```
   *Script tự động biên dịch Svelte SPA thành static assets, nhúng vào Go binary qua `embed.FS` và build ra file thực thi duy nhất tại `build/bin/PAM-MQ`.*

2. **Bước 2 (Sync Public Repository):**
   ```bash
   cp -f /root/PAM-MQ/build/bin/PAM-MQ /root/PAM-CPG/pam-cpg
   chmod +x /root/PAM-CPG/pam-cpg
   cp -f /root/PAM-MQ/auto-install.sh /root/PAM-CPG/auto-install.sh
   cp -f /root/PAM-MQ/update.sh /root/PAM-CPG/update.sh
   cp -f /root/PAM-MQ/uninstall.sh /root/PAM-CPG/uninstall.sh
   cp -f /root/PAM-MQ/README.md /root/PAM-CPG/README.md
   ```

3. **Bước 3 (Git Push Dual Repositories):**
   * **Kho Private (`PAM-MQ` - Chứa toàn bộ source code):**
     ```bash
     cd /root/PAM-MQ
     git add .
     git commit -m "feat/fix: mô tả nội dung cập nhật"
     git push origin main
     ```
   * **Kho Public (`pam-cpg` - Phân phối bản phát hành & scripts):**
     ```bash
     cd /root/PAM-CPG
     git add .
     git commit -m "release: cập nhật binary pam-cpg mới"
     git push origin main
     ```

4. **Bước 4 (Live Update Service):**
   ```bash
   cd /root/PAM-CPG
   ./update.sh
   ```
   *Script `update.sh` tự động nạp binary mới vào `/opt/PAM-CPG/bin/pam-cpg`, sao lưu bản cũ thành `.bak`, khởi động lại dịch vụ `pam-cpg.service`, bảo toàn 100% CSDL MariaDB và cấu hình `.env`.*

---

## 4. TỔNG HỢP CÁC SCRIPT VẬN HÀNH TRONG DỰ ÁN

| Tên Script | Thư mục | Quyền | Mục đích và Hành vi chi tiết |
| :--- | :--- | :---: | :--- |
| **`build-package.sh`** | `PAM-MQ` | `+x` | Biên dịch toàn diện Frontend Svelte + Backend Go ra file nhị phân duy nhất `PAM-MQ` và đóng gói bộ cài tự giải nén `dist_release/pam-mq-installer.bin`. |
| **`update.sh`** | `PAM-CPG` / `PAM-MQ` | `+x` | Nâng cấp tức thời binary mới nhất từ GitHub, backup `.bak`, khởi động lại service systemd, bảo toàn dữ liệu 100%. |
| **`auto-install.sh`** | `PAM-CPG` / `PAM-MQ` | `+x` | Kịch bản cài đặt tự động One-Click qua `curl`: Dò OS, cài MariaDB/FFmpeg, quét port trống (9000-9999), sinh cert SSL, Shamir keys và đăng ký Systemd. |
| **`install.sh`** | `PAM-MQ` | `+x` | Script cài đặt offline từ gói phân phối `.tar.gz`. |
| **`uninstall.sh`** | `PAM-CPG` / `PAM-MQ` | `+x` | Gỡ bỏ sạch sẽ toàn bộ dịch vụ PAM-CPG/PAM-MQ, dọn thư mục `/opt/`, systemd service và hỗ trợ lựa chọn xóa hoặc giữ CSDL. |
| **`git-helper.sh`** | `PAM-MQ` / `PAM-CPG` | `+x` | Menu tương tác Push/Pull Git thông minh; tự động lọc bỏ video recording và file log lớn trước khi commit. |
| **`deploy.sh`** | `PAM-MQ` | `+x` | Thực thi migration cơ sở dữ liệu MariaDB thông qua script `deploy_mariadb.go`. |
| **`install-mariadb-server.sh`** | `PAM-MQ` | `+x` | Cài đặt MariaDB Server chính thức từ MariaDB.org (các bản 10.x/11.x) trên Ubuntu. |
| **`scripts/check-i18n.sh`** | `PAM-MQ` | `+x` | Quét đối chiếu toàn bộ key bản dịch giữa `en.json` và `vi.json` để ngăn ngừa thiếu sót i18n. |

---

## 5. DANH SÁCH REST API ĐẦY ĐỦ (REST API SPECIFICATION)

### 5.1. Nhóm Xác thực & Đăng nhập (Authentication APIs)
* `POST /api/auth/login`: Đăng nhập bước 1 (Local Bcrypt hoặc LDAP Active Directory Two-Stage Bind).
* `POST /api/auth/mfa/verify-login`: Xác thực bước 2 qua OTP TOTP 6 số.
* `GET /api/auth/mfa/setup`: Sinh Secret Base32 và QR Code SVG/PNG.
* `POST /api/auth/mfa/activate`: Kích hoạt chính thức bảo mật 2 lớp cho tài khoản.
* `POST /api/auth/mfa/recover`: Tự khôi phục và reset MFA bằng mã Recovery Code 12 chữ số.

### 5.2. Nhóm Quản trị Khóa Hệ thống & Shamir (System & Master Key)
* `POST /api/system/unlock`: Nạp 2/3 mảnh Shamir khôi phục Master Key AES-256 vào RAM.
* `GET /api/system/status`: Kiểm tra trạng thái hệ thống (Khóa/Mở khóa, Database status).

### 5.3. Nhóm Quản trị Người Dùng & Phân Quyền (Identity & Roles)
* `GET /api/admin/users`, `POST /api/admin/users`: Lấy danh sách và tạo người dùng.
* `PUT /api/admin/users/:id`, `DELETE /api/admin/users/:id`: Cập nhật/Khóa/Mở khóa/Xóa người dùng.
* `GET /api/admin/roles`, `GET /api/admin/permissions`: Danh sách vai trò và ma trận quyền hạn RBAC.
* `PUT /api/admin/roles/:id/permissions`: Gán quyền hạn cho từng vai trò.

### 5.4. Nhóm Quản trị Thiết Bị & Import Excel (Sessions & Resources)
* `GET /api/admin/sessions`, `POST /api/admin/sessions`: Quản lý danh sách thiết bị kết nối.
* `PUT /api/admin/sessions/:id`, `DELETE /api/admin/sessions/:id`: Cập nhật và xóa thiết bị.
* `POST /api/admin/sessions/batch-import`: Nhập hàng loạt từ Excel, tự động mã hóa AES-256 mật khẩu.

### 5.5. Nhóm Quản trị Nhóm & Ma Trận Phân Quyền Hai Lớp (Groups & Access Matrix)
* `GET /api/admin/user-groups`, `POST /api/admin/user-groups`: Quản lý Nhóm Người Dùng.
* `POST /api/admin/user-groups/:id/members`: Gán thành viên người dùng vào nhóm.
* `GET /api/admin/device-groups`, `POST /api/admin/device-groups`: Quản lý Nhóm Thiết Bị.
* `POST /api/admin/device-groups/:id/members`: Gán thiết bị máy chủ vào nhóm.
* `GET /api/admin/group-assignments`, `POST /api/admin/group-assignments`: Thiết lập chính sách phân quyền nhóm (UserGroup $\to$ DeviceGroup $\to$ Vault $\to$ JIT).

### 5.6. Nhóm Yêu cầu Truy cập Just-In-Time (JIT Approval)
* `POST /api/access-requests`: Gửi yêu cầu xin cấp quyền JIT.
* `GET /api/admin/access-requests`: Lấy danh sách yêu cầu chờ duyệt.
* `POST /api/admin/access-requests/:id/approve`: Phê duyệt cấp quyền JIT.
* `POST /api/admin/access-requests/:id/reject`: Từ chối yêu cầu kèm lý do.

### 5.7. Nhóm Kiểm toán & Giám sát Phiên (Audit & SOC Hub)
* `GET /api/admin/audit/active-sessions`: Danh sách các phiên SSH/RDP/Web đang chạy real-time.
* `POST /api/admin/audit/shadow/ticket`: Cấp vé One-Time Token (OTT) phục vụ Live Shadowing.
* `POST /api/admin/audit/active-sessions/:id/terminate`: Ngắt cưỡng bức phiên kết nối.
* `GET /api/admin/audit/logs`: Lấy danh sách nhật ký kiểm toán hệ thống.

### 5.8. Nhóm Cấu hình Thông báo Email & Hệ thống (Settings & Email)
* `GET /api/admin/settings/email`, `POST /api/admin/settings/email`: Cấu hình thông số SMTP Server.
* `POST /api/admin/settings/email/test`: Gửi email kiểm tra kết nối SMTP.

### 5.9. Nhóm Quản lý Phiên bản & Kế hoạch Nâng cấp (Version & System Updates)
* `GET /api/system/version`: Lấy thông tin phiên bản hiện tại và đối soát tự động với kho Git Public (public endpoint / whitelist).
* `POST /api/admin/system/check-update`: Kiểm tra phiên bản mới nhất từ kho GitHub Public (bỏ qua cache, yêu cầu quyền Admin).

---

## 6. CƠ CHẾ ĐỐI SOÁT PHIÊN BẢN (VERSION CHECKER ENGINE)

Hệ thống tích hợp module kiểm tra phiên bản tự động (`backend/version/version.go`):
1. **Semver Comparison Algorithm (`CompareSemver`):** So sánh `v_remote` với `v_current`:
   * `> 0`: `outdated` (Đã có bản cập nhật mới trên GitHub).
   * `== 0`: `latest` (Hệ thống đang chạy phiên bản mới nhất).
   * `< 0`: `dev` (Bản build thử nghiệm nội bộ).
2. **Metadata `version.json` trên Git Public:** Cung cấp số phiên bản, ngày phát hành, changelog song ngữ EN/VI và link tải.
3. **Cơ chế Cache TTL 5 phút:** Tránh rate-limit từ GitHub API/Raw content khi có nhiều người dùng truy cập.
4. **Giao diện Tương tác:**
   * Badge hiển thị phiên bản và chấm trạng thái (Xanh lá = mới nhất, Cam nhấp nháy = có bản cập nhật) trên Sidebar, Login Portal và System Unlock.
   * Subtab "Phiên bản & Cập nhật" trong Admin Settings Console với bảng so sánh, nhật ký thay đổi và hướng dẫn nâng cấp từng bước.

---

## 7. DANH MỤC THƯ VIỆN & CÔNG NGHỆ CHÍNH

### 7.1. Backend (Go 1.22+)
* **Web Framework:** `github.com/labstack/echo/v4`
* **ORM Database:** `gorm.io/gorm` & `gorm.io/driver/mysql` & `gorm.io/driver/sqlite`
* **Xác thực LDAP:** `github.com/go-ldap/ldap/v3`
* **TOTP MFA Engine:** `github.com/pquerna/otp`
* **Shamir's Secret Sharing:** `github.com/hashicorp/vault/sdk/helper/shamir`
* **PTY AST Parser:** `github.com/mvdan/sh/v3/syntax`
* **Prometheus Metrics:** `github.com/prometheus/client_golang/prometheus`

### 7.2. Frontend (Svelte & TypeScript)
* **Core UI:** `Svelte 4` & `Vite`
* **Styling Engine:** `TailwindCSS` & Custom CSS Variables Theme System
* **Bộ Icon Vector:** `lucide-svelte`
* **Bảng dữ liệu dùng chung:** `DataTable.svelte`
* **Xử lý Excel:** `xlsx` (SheetJS)
* **Terminal Engine:** `xterm.js` & `xterm-addon-fit`
* **State Store:** `svelte/store`

---

## 8. CẤU HÌNH MÔI TRƯỜNG & HƯỚNG DẪN ĐỔI CỔNG (.ENV & SYSTEMD)

### 8.1. Cấu trúc tệp `/opt/PAM-CPG/.env`
```ini
PORT=9000
DOMAIN=192.168.1.130
DB_DSN=pamcpg:MinhQuyen@2026@tcp(127.0.0.1:3306)/pamcpg?charset=utf8mb4&parseTime=True&loc=Local
SSL_CERT=/opt/PAM-CPG/certs/server.crt
SSL_KEY=/opt/PAM-CPG/certs/server.key
```

### 8.2. Quy trình 2 bước đổi Port dịch vụ
1. Mở file `.env` và sửa giá trị `PORT`:
   ```bash
   sudo nano /opt/PAM-CPG/.env
   # Sửa PORT=9000 thành PORT=9555
   ```
2. Khởi động lại dịch vụ:
   ```bash
   sudo systemctl restart pam-cpg
   ```
   *(Mở firewall nếu có: `sudo ufw allow 9555/tcp`)*

---

## 9. QUY TRÌNH 4 BƯỚC BẮT BUỘC KHI BUILD & PHÁT HÀNH

Mỗi khi phát triển tính năng mới hoặc sửa lỗi, bắt buộc thực thi đầy đủ chu trình 4 bước:
1. **Bước 1 - Build Standalone Binary:** Chạy `bash build-package.sh` trong repo `PAM-MQ`.
2. **Bước 2 - Đồng bộ:** Copy binary `build/bin/PAM-MQ` sang `/root/PAM-CPG/pam-cpg` và các script cập nhật sang `/root/PAM-CPG/`.
3. **Bước 3 - Git Commit & Push:** Commit và Push lên cả 2 repository (Private `PAM-MQ` và Public `pam-cpg`).
4. **Bước 4 - Cập nhật Live Service:** Chạy `sudo ./update.sh` tại `/root/PAM-CPG` để dịch vụ hệ thống trên máy chủ live được nạp bản mới nhất.

---

## 10. KIẾN TRÚC SẴN SÀNG CAO (HIGH AVAILABILITY - HA ARCHITECTURE)

### 10.1. Sơ đồ khối Mô hình Active - Standby (Hot Standby Failover)

Hệ thống hỗ trợ mô hình triển khai sẵn sàng cao **Hot Standby 2-Node** đảm bảo chuyển đổi dự phòng tức thì khi có sự cố phần cứng:

```
                                      +-------------------------------+
                                      |   Users / Auditors (Browser)  |
                                      +---------------+---------------+
                                                      | HTTPS / WSS
                                                      v
                                      +-------------------------------+
                                      |      Virtual IP (VIP)         |
                                      |    (Keepalived VRRP Engine)   |
                                      +---------------+---------------+
                                                      |
                                      +---------------+---------------+
                                      |  HAProxy / NGINX LoadBalancer |
                                      |  (Sticky Session & SSL Term)  |
                                      +-------+---------------+-------+
                                              |               |
                       +----------------------+               +----------------------+
                       | Health Check /healthz                        | Health Check /healthz
                       v                                              v
      +--------------------------------+             +--------------------------------+
      |      PAM-CPG Node 01 (Master)   |             |      PAM-CPG Node 02 (Standby) |
      |   - Backend Go Standalone      |             |   - Backend Go Standalone      |
      |   - Port 9000 (HTTPS/WSS)      |             |   - Port 9000 (HTTPS/WSS)      |
      |   - Shamir Master Key in RAM   |             |   - Shamir Master Key in RAM   |
      +-------+----------------+-------+             +-------+----------------+-------+
              |                |                             |                |
              |                +--------------+ +------------+                |
              |                               | |                             |
              v                               v v                             v
      +------------------+           +--------------------+          +------------------+
      |   Redis Cluster  |           | Shared Storage     |          |  MariaDB Dual    |
      | - OTT 10s Token  |           | (NFS / MinIO S3)   |          |  Master GTID     |
      | - Live Shadowing |           | - recordings/*.mp4 |          | (Real-time Sync) |
      | - Active Sess DB |           | - certs & env      |          | Zero-Downtime    |
      +------------------+           +--------------------+          +------------------+
```

### 10.2. Cơ chế Đồng bộ Dữ liệu MariaDB (Dual-Master GTID Replication)
* **Replication Mode:** Thiết lập sao chép nhị phân 2 chiều (Master - Master) sử dụng **Global Transaction ID (GTID)** với định dạng `binlog_format = ROW`.
* **Cấu hình Server ID:**
  * **Node 01 (Master):** `server-id = 1`, `auto_increment_increment = 2`, `auto_increment_offset = 1`.
  * **Node 02 (Standby):** `server-id = 2`, `auto_increment_increment = 2`, `auto_increment_offset = 2`.
* **Bảo toàn tính toàn vẹn:** Mọi thay đổi dữ liệu (tạo user, thêm session, gán quyền, nhật ký JIT) được sao chép sang Node 2 tức thời từng miligiây. Khi Node 1 gặp sự cố, Node 2 đã có sẵn 100% dữ liệu để tiếp quản ngay lập tức. Khi Node 1 hoạt động trở lại, dữ liệu phát sinh từ Node 2 sẽ tự động đồng bộ ngược lại Node 1 mà không xảy ra xung đột khóa chính.

### 10.3. Cơ chế Chia Sẻ Master Key Giữa Các Node (Key Governance)
* **Bản chất an ninh:** Dữ liệu mật khẩu và SSH Key trong Database được mã hóa bằng thuật toán **AES-256-GCM**. MariaDB sao chép nguyên vẹn luồng byte mã hóa (Ciphertext).
* **Điều kiện tiên quyết:** Node 02 **bắt buộc phải sử dụng cùng một Master Key 256-bit** với Node 01.
* **Phương pháp triển khai:**
  * **Phương án 1 (Clone máy ảo - Khuyến nghị):** Clone trực tiếp máy ảo từ Node 01 sang Node 02. Toàn bộ file `/opt/PAM-CPG/config/config.json`, chứng chỉ `/opt/PAM-CPG/certs/` và bộ 3 mảnh Shamir trong `/opt/PAM-CPG/CREDENTIALS.txt` được sao chép $1:1$. Cả 2 Node cùng sở hữu chung bộ Master Key.
  * **Phương án 2 (Cài mới):** Sao chép file `config.json`, `certs/` và bộ 3 mảnh Shamir từ Node 01 sang Node 02 trước khi khởi động dịch vụ. Mở khóa Node 02 bằng 2/3 mảnh Shamir của Node 01.

---

## 11. MÔ HÌNH ĐE DỌA & BẢO VỆ CỨNG HÓA HỆ THỐNG (THREAT MODELING & HOST HARDENING)

### 11.1. Phân Tích Bán Kính Thiệt Hại Khi Kẻ Tấn Công Chiếm Quyền Root OS (Host Compromise)

Nếu kẻ tấn công chiếm được quyền quản trị cao nhất (`root`) trên máy chủ lưu trữ dịch vụ PAM-CPG:

1. **Trích xuất Master Key từ bộ nhớ RAM (Memory Dump):**
   * Nếu dịch vụ `pam-cpg` đang ở trạng thái **UNLOCKED**, Master Key 256-bit đang nạp trong RAM của tiến trình Go.
   * Kẻ tấn công có thể sử dụng các công cụ can thiệp bộ nhớ (`/proc/<pid>/mem`, `gcore`, `gdb`) để đọc Master Key, kết hợp với mật khẩu DB trong `.env` để giải mã $100\%$ mật khẩu và Private Key trong `credential_vault`.
2. **Khai thác file bàn giao `CREDENTIALS.txt` (Nếu chưa dọn dẹp):**
   * Nếu file `CREDENTIALS.txt` còn lưu trên đĩa, kẻ tấn công lập tức có được: Mật khẩu Admin Web, MFA Recovery Code, Mật khẩu MariaDB Root và **toàn bộ 3 mảnh Shamir Master Key**.
3. **Nghe lén & Chiếm đoạt phiên trực tiếp (Session Sniffing & Hijacking):**
   * Bằng quyền root, kẻ tấn công có thể can thiệp vào luồng PTY Terminal hoặc WebSocket nội bộ để đọc thông tin bảo mật mà kỹ sư đang thao tác hoặc gửi lệnh trái phép sang server đích.
4. **Tấn công leo thang sang toàn bộ hạ tầng doanh nghiệp (Lateral Movement):**
   * Sử dụng danh sách tài khoản đã giải mã từ Vault để SSH / RDP trực tiếp sang các máy chủ Core, Database, Router trong mạng nội bộ.
5. **Xóa dấu vết kiểm toán (Anti-Forensics / Wipe Logs):**
   * Xóa hoặc chỉnh sửa các file video ghi hình `.mp4`, file text log và bảng `audit_logs` trong MariaDB.

### 11.2. Các Giới Hạn & Phòng Tuyến Kẻ Tấn Công Không Thể Vượt Qua
* **Khi máy chủ PAM tắt (Cold Shutdown) hoặc bị khóa (LOCKED):** Master Key biến mất khỏi RAM. Toàn bộ dữ liệu trên đĩa cứng và Database là các khối nhị phân **AES-256-GCM không thể phá mã**. Dù kẻ tấn công có dump toàn bộ đĩa cứng cũng không thể đọc được mật khẩu.
* **Không thể xóa nhật ký đã gửi ra SIEM ngoại vi:** Các bản ghi đã chuyển qua **Syslog TLS** về máy chủ SIEM/SOC độc lập (Wazuh, Splunk, Elastic) nằm ngoài tầm kiểm soát của máy PAM.

### 11.3. Danh Mục Cứng Hóa An Ninh Bắt Buộc (Host Hardening Checklist)

| STT | Hạng mục an ninh | Thao tác thực thi bắt buộc |
| :---: | :--- | :--- |
| **1** | **Xóa sạch file bàn giao `CREDENTIALS.txt`** | Lưu trữ 3 mảnh Shamir và mật khẩu vào phần mềm quản lý mật khẩu an toàn offline (KeePass / 1Password), sau đó xóa vĩnh viễn trên server: `shred -u /opt/PAM-CPG/CREDENTIALS.txt`. |
| **2** | **Chặn Dump bộ nhớ RAM của tiến trình PAM** | Thiết lập tham số nhân Linux Kernel để ngăn chặn tiến trình khác đọc RAM: `echo 2 > /proc/sys/kernel/yama/ptrace_scope` (và cấu hình bền vững trong `/etc/sysctl.d/10-ptrace.conf`). |
| **3** | **Cứng hóa truy cập SSH vào máy chủ PAM** | Tắt đăng nhập SSH bằng mật khẩu thô (`PasswordAuthentication no`), cấm root SSH trực tiếp (`PermitRootLogin no`), đổi cổng SSH mặc định và chỉ cho phép kết nối từ dải IP Quản trị (Admin Management Subnet). |
| **4** | **Phân vùng mạng cô lập (Network Isolation & Firewall)** | Đặt máy chủ PAM vào phân vùng mạng DMZ/VLAN riêng biệt; chỉ mở các cổng dịch vụ thiết yếu qua Firewall (Port `9000` HTTPS WebUI và `3306` cho Replication nội bộ). |
| **5** | **Bật đẩy log ngoại vi (Syslog TLS to SIEM)** | Luôn cấu hình đẩy log tức thời qua giao thức Syslog TLS tới trung tâm giám sát an ninh SOC độc lập. |
| **6** | **Cài đặt HIDS / EDR (Wazuh / OSSEC)** | Kích hoạt bộ phát hiện xâm nhập Host-based IDS với tính năng giám sát toàn vẹn tệp tin (FIM) trên các thư mục `/opt/PAM-CPG/bin`, `/opt/PAM-CPG/certs` và `/etc/systemd/system/`. |

### 11.4. Đánh Giá Khả Năng Phòng Ngự Chống Nghe Lén & Chiếm Đoạt Phiên Qua Mạng (Network Sniffing & Session Hijacking Resilience)

Trong tình huống kẻ tấn công **chiếm quyền điều khiển một máy tính khác trong cùng mạng LAN / VLAN** và tiến hành bắt gói tin (Sniffing qua Promiscuous mode, ARP Poisoning, SPAN port):

#### A. Kiến Trúc 2 Chặng Mã Hóa Độc Lập (Dual Encrypted Segments)

```
[ KỸ SƯ / USER ]  ═══════ (Chặng 1: HTTPS & WSS) ═══════>  [ PAM-CPG GATEWAY ]  ═══════ (Chặng 2: SSHv2 / RDP TLS) ═══════>  [ SERVER ĐÍCH ]
(Trình duyệt Web)    • Mã hóa TLS 1.2 / 1.3 (Port 9000)      • Cầu nối trung chuyển     • Mã hóa SSHv2 AES-256 / ChaCha20      (Linux/Windows)
                     • Chống nghe lén 100%                   • Kiểm toán & Lọc AST      • Mật khẩu được Inject tự động
```

1. **Chặng 1: Trình duyệt của User $\longleftrightarrow$ PAM Gateway (HTTPS & WSS):**
   * **Bảo vệ chống nghe lén:** Hoạt động $100\%$ qua **HTTPS** (REST API) và **Secure WebSocket (`wss://`)** (Terminal/RDP). Mã hóa TLS 1.3 với thuật toán trao đổi khóa **Perfect Forward Secrecy (ECDHE)**. Kẻ nghe lén chỉ thu được các chuỗi nhị phân mã hóa vô nghĩa (Ciphertext), hoàn toàn không thể đọc trộm mật khẩu, lệnh phím gõ hay xem màn hình.
   * **Bảo vệ chống chèn mã độc (Packet Injection):** TLS tích hợp mã kiểm tra tính toàn vẹn (HMAC / AES-GCM Auth Tag) kèm bộ đếm số thứ tự gói tin (Sequence Number). Mọi hành vi sửa đổi hoặc chèn thêm dù chỉ 1 byte vào luồng mạng sẽ khiến gói tin bị từ chối và kết nối lập tức bị hủy bỏ (Abort).
   * **Bảo vệ vé kết nối phiên (One-Time Token - OTT Security):** Vé kết nối WebSocket (OTT) chỉ có hạn **10 giây** và được tiêu thụ nguyên tử qua hàm `LoadAndDelete` trong Go Backend. Vé chỉ dùng được duy nhất 1 lần, triệt tiêu nguy cơ tấn công phát lại (Replay Attack).

2. **Chặng 2: PAM Gateway $\longleftrightarrow$ Máy chủ đích (SSHv2 / RDP NLA TLS):**
   * **Giao thức:** **SSHv2** (`AES-256-CTR`, `ChaCha20-Poly1305`) cho Linux/Network và **RDP NLA / TLS** cho Windows Server.
   * **Bảo vệ đầu-cuối:** Mỗi phiên sinh một cặp khóa đối xứng tạm thời ngẫu nhiên (Ephemeral Keys). Kẻ đứng giữa nghe lén luồng mạng giữa PAM và máy chủ đích hoàn toàn không thể giải mã được phiên làm việc.

#### B. Phân Tích 3 Tình Huống Ngoại Lệ Cần Lưu Ý

| Tình huống rủi ro | Mức độ nguy cơ | Giải pháp và Khuyến nghị kỹ thuật |
| :--- | :---: | :--- |
| **① Dùng giao thức cổ không mã hóa (Telnet / Plain FTP)** | **Trung bình** | Nếu quản trị viên thiết lập Session loại **Telnet** (Port 23) hoặc **FTP** (Port 21), luồng dữ liệu ở Chặng 2 (từ PAM $\to$ Thiết bị đích) là văn bản rõ (Plaintext). Nếu hacker sniff ở phân vùng mạng máy chủ đích, họ có thể đọc được dữ liệu này. <br>👉 **Khuyến nghị:** Luôn ưu tiên chuẩn hóa dùng **SSH** thay cho Telnet, và **SFTP/FTPS** thay cho FTP thường. |
| **② Tấn công giả mạo Man-in-the-Middle (MitM) bằng Chứng chỉ giả** | **Thấp** | Kẻ tấn công đầu độc ARP/DNS để đóng giả PAM Gateway và cấp chứng chỉ SSL giả. Tuy nhiên, trình duyệt của kỹ sư sẽ lập tức bật cảnh báo bảo mật màu đỏ (`NET::ERR_CERT_AUTHORITY_INVALID`). <br>👉 **Khuyến nghị:** Nghiêm cấm người dùng bấm bỏ qua cảnh báo SSL đỏ lạ; triển khai chứng chỉ SSL hợp lệ (Let's Encrypt hoặc CA nội bộ doanh nghiệp). |
| **③ Hacker chiếm quyền chính máy tính của Kỹ sư (Client Endpoint Compromise)** | **Cao** | Nếu máy tính của kỹ sư bị cài mã độc Keylogger hoặc Trojan/RAT, hacker sẽ chụp màn hình và ghi lại phím bấm trực tiếp từ bàn phím của User trước khi dữ liệu được mã hóa gửi đi. <br>👉 **Khuyến nghị:** Cài đặt phần mềm diệt virus / EDR trên máy tính trạm của kỹ sư và bắt buộc xác thực 2 lớp (TOTP MFA). |

---

## 12. QUY CHUẨN MÔI TRƯỜNG HỆ ĐIỀU HÀNH & MA TRẬN CỔNG TƯỜNG LỬA (OS REQUIREMENTS & FIREWALL MATRIX)

Để đảm bảo hệ thống PAM-MQ / PAM-CPG được triển khai thông suốt, ổn định trên mọi môi trường máy chủ khách hàng (đặc biệt là các môi trường hạ tầng doanh nghiệp áp dụng chính sách Tường lửa chặn 2 chiều nghiêm ngặt: **`Default: deny incoming, deny outgoing`**), tài liệu này chuẩn hóa toàn bộ các gói phần mềm cần thiết và ma trận cổng mạng.

### 12.1. Yêu Cầu Gói Phần Mềm & Khả Năng Tương Thích Hệ Điều Hành (Ubuntu 22.04, 24.04, 26.04)

Tất cả các thành phần phụ thuộc của hệ thống đã được kiểm tra và đảm bảo tương thích 100% trên các phiên bản **Ubuntu 22.04 LTS (Jammy)**, **Ubuntu 24.04 LTS (Noble)** và **Ubuntu 26.04**:

| Tên Gói Phần Mềm | Kho Repository (APT) | Mục Đích Sử Dụng Trong PAM-CPG | Giải Pháp Tương Thích Kỹ Thuật |
| :--- | :--- | :--- | :--- |
| **`ffmpeg`** | `universe` | Mã hóa và xuất video MP4 tự động cho các phiên RDP & SSH Terminal. | Tự động kích hoạt kho `universe` qua `add-apt-repository -y universe` nếu chạy trên các bản cài đặt Ubuntu Minimal / Cloud Image trắng. |
| **`ca-certificates`** | `main` | Xác thực chứng chỉ SSL/TLS gốc của hệ điều hành. | Đảm bảo tính toàn vẹn khi kết nối ra ngoài (GitHub, Azure AD, Google OAuth, NTP, LDAPS). |
| **`curl`** & **`openssl`** | `main` | Tải binary từ kho GitHub Public và sinh chứng chỉ SSL HTTPS nội bộ 10 năm (3650 ngày). | Tương thích hoàn hảo với OpenSSL 3.0+ trên U22, U24 và U26. |
| **`tzdata`** | `main` | Đồng bộ múi giờ chuẩn cho nhật ký kiểm toán Audit Log. | Tự động cấu hình múi giờ hệ thống không cần tương tác thủ công. |
| **`jq`** | `main` / `universe` | Phân tích cú pháp JSON cấu hình bảo mật ban đầu. | Sử dụng để trích xuất 3 mảnh Shamir Keys và Secret TOTP từ lệnh `--setup`. |
| **`iproute2`** | `main` | Cung cấp lệnh `ss` để kiểm tra cổng lắng nghe và phát hiện xung đột port. | Chuẩn hóa hiện đại thay thế cho gói `net-tools` (`netstat`) đã cũ. |
| **`mariadb-server` & `mariadb-client`** | `main` / `universe` | Hệ quản trị cơ sở dữ liệu quan hệ chính của Gateway. | Script tự động nhận diện cả 2 lệnh CLI `mariadb` và `mysql`, daemon `mariadbd` và `mysqld`, tương thích MariaDB 10.6+ đến 11.x+. |

> ⚙️ **Quy chuẩn chạy Unattended:** Toàn bộ lệnh APT trong script cài đặt bắt buộc gán `export DEBIAN_FRONTEND=noninteractive` để loại bỏ hoàn toàn các hộp thoại hỏi đáp chặn tiến trình tự động.

---

### 12.2. Ma Trận Cổng Tường Lửa Chiều Vào & Chiều Ra (Firewall IN & OUT Matrix)

Khi triển khai trên các máy chủ có Tường lửa UFW hoặc Firewall mạng phần cứng (Fortinet, pfSense, Cisco ASA, Sophos, iptables) áp dụng chính sách **`deny (incoming)`** và **`deny (outgoing)`**, Quản trị viên bắt buộc phải mở các cổng sau:

```
                               +---------------------------------------+
                               |     MÁY CHỦ GATEWAY (PAM-CPG SERVER)  |
                               +---------------------------------------+
               📥 INBOUND PORTS                                                📤 OUTBOUND PORTS
  (Client / Admin kết nối vào PAM)                                (PAM kết nối ra Thiết bị & Hạ tầng)
  ---------------------------------                               -------------------------------------
  • 9000/tcp   : Web Portal & WSS                                 • 53/udp,tcp : DNS Resolution
  • 2121/tcp   : RDP FTP Control                                  • 123/udp    : NTP Time Sync
  • 30000:30100: RDP FTP Data Range                               • 80,443/tcp : HTTP/S (Apt, SSO, Proxy)
  • 22/tcp     : SSH Admin Server                                 • 22/tcp     : Target SSH / SFTP
                                                                  • 3389/tcp   : Target Windows RDP
                                                                  • 23/tcp     : Target Telnet
                                                                  • 5900:5910  : Target VNC
                                                                  • 20,21/tcp  : Target FTP
                                                                  • 389,636/tcp: Target LDAP / LDAPS
                                                                  • 25,465,587 : Outbound Mail SMTP
                                                                  • 3306/tcp   : External MariaDB (nếu có)
```

#### A. Danh mục Cổng Chiều VÀO (INBOUND):
| Port / Protocol | Giao Thức | Ý Nghĩa Chức Năng | Câu Lệnh Mở Trên UFW |
| :--- | :--- | :--- | :--- |
| **`9000/tcp`** *(hoặc `$PORT`)* | TCP | Cổng giao diện Web Portal HTTPS & kênh truyền WebSocket Terminal / RDP. | `ufw allow 9000/tcp comment "PAM-CPG Web Portal & API"` |
| **`2121/tcp`** | TCP | Cổng điều khiển FTP Server chia sẻ file trong phiên kết nối Windows RDP. | `ufw allow 2121/tcp comment "PAM-CPG RDP FTP Sharing Control"` |
| **`30000:30100/tcp`** | TCP | Dải cổng dữ liệu Passive FTP truyền file hai chiều với Windows Explorer. | `ufw allow 30000:30100/tcp comment "PAM-CPG RDP FTP Passive Data"` |
| **`22/tcp`** | TCP | Cổng quản trị từ xa qua SSH vào chính máy chủ Linux chạy PAM. | `ufw allow 22/tcp comment "SSH Server Management"` |

#### B. Danh mục Cổng Chiều RA (OUTBOUND):
| Port / Protocol | Giao Thức | Ý Nghĩa Chức Năng | Câu Lệnh Mở Trên UFW |
| :--- | :--- | :--- | :--- |
| **`53`** | UDP / TCP | Phân giải tên miền (DNS) cho các thiết bị máy chủ đích. | `ufw allow out 53 comment "DNS Resolution"` |
| **`123/udp`** | UDP | Đồng bộ thời gian thực (NTP) cho chứng chỉ SSL và mã TOTP 2FA. | `ufw allow out 123/udp comment "NTP Time Sync"` |
| **`80, 443/tcp`** | TCP | Cập nhật hệ thống qua `apt`, tải GitHub release, xác thực SSO Azure AD / Google và Web Forwarding Proxy. | `ufw allow out 80,443/tcp comment "HTTP/HTTPS Outbound"` |
| **`22/tcp`** | TCP | Kết nối quản trị máy chủ đích Linux và thiết bị mạng Cisco/Switch qua SSH/SFTP. | `ufw allow out 22/tcp comment "PAM Target SSH/SFTP"` |
| **`3389/tcp`** | TCP | Kết nối quản trị máy chủ đích Windows Server / Desktop qua giao thức RDP. | `ufw allow out 3389/tcp comment "PAM Target Windows RDP"` |
| **`23/tcp`** | TCP | Kết nối quản trị thiết bị mạng đời cũ qua giao thức Telnet. | `ufw allow out 23/tcp comment "PAM Target Telnet"` |
| **`5900:5910/tcp`** | TCP | Kết nối điều khiển máy chủ đồ họa qua giao thức VNC. | `ufw allow out 5900:5910/tcp comment "PAM Target VNC"` |
| **`20, 21/tcp`** | TCP | Kết nối truyền tập tin tới máy chủ FTP lưu trữ bên ngoài. | `ufw allow out 20,21/tcp comment "PAM Target FTP"` |
| **`389, 636/tcp`** | TCP | Kết nối máy chủ Active Directory / OpenLDAP để xác thực người dùng miền (LDAP / LDAPS). | `ufw allow out 389,636/tcp comment "PAM Target LDAP/LDAPS"` |
| **`25, 465, 587/tcp`** | TCP | Kết nối máy chủ Email SMTP để gửi mã xác thực 2FA, OTP khôi phục và thông báo cảnh báo. | `ufw allow out 25,465,587/tcp comment "PAM Outbound SMTP Mail"` |
| **`3306/tcp`** *(nếu có)* | TCP | Kết nối CSDL MariaDB / MySQL bên ngoài (nếu không dùng CSDL cục bộ `127.0.0.1`). | `ufw allow out 3306/tcp comment "PAM External MariaDB"` |

---

### 12.3. Cơ Chế Tự Động Hóa Trong Bộ Script Cài Đặt

1. **Giai đoạn tiền cài đặt (Pre-Installation):** Script `auto-install.sh` tự động kiểm tra trạng thái UFW. Nếu phát hiện tường lửa đang bật ở chế độ `deny (outgoing)`, script tự động mở trước cổng `53` (DNS), `123` (NTP), `80/443` (HTTP/S) chiều OUT để các lệnh `apt-get` và `curl` tải binary diễn ra thông suốt.
2. **Giai đoạn hoàn thiện:** Tự động thiết lập đầy đủ toàn bộ bảng ma trận rule IN/OUT ở trên kèm nhãn `comment` rõ ràng trên `ufw`.
3. **Giai đoạn gỡ bỏ (Uninstallation):** Script `uninstall.sh` tự động thu hồi và xóa sạch các rule cổng mạng đã mở cho PAM, trả máy chủ về trạng thái tường lửa ban đầu.




