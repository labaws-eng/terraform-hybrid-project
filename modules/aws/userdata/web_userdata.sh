#!/bin/bash
# ============================================================
# web_userdata.sh
#
# Script này chạy TỰ ĐỘNG khi EC2 khởi động lần đầu tiên.
# Terraform nhúng script này vào EC2 qua user_data argument.
# Biến ${db_host}, ${db_password}, etc. được templatefile()
# thay thế trước khi gửi lên EC2.
#
# Thứ tự cài đặt:
#   [1] Update hệ thống
#   [2] Cài Apache + PHP + PHP-PgSQL (PostgreSQL client)
#   [3] Khởi động Apache
#   [4] Tạo web application PHP (form + DB query)
#   [5] Phân quyền file
# ============================================================
set -e
# Ghi toàn bộ log vào file để debug
exec > /var/log/userdata.log 2>&1

echo "=================================================="
echo ">>> [USERDATA START] $(date)"
echo ">>> Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')"
echo "=================================================="

# ── [1/5] UPDATE ──────────────────────────────────────────────
echo ""
echo ">>> [1/5] Đang update hệ thống..."
yum update -y
echo "✅ [1/5] System updated"

# ── [2/5] CÀI PACKAGES ────────────────────────────────────────
echo ""
echo ">>> [2/5] Đang cài Apache + PHP + PHP-PgSQL..."
yum install -y httpd php php-pgsql php-json
echo "✅ [2/5] Apache + PHP + PHP-PgSQL installed"

# ── [3/5] KHỞI ĐỘNG APACHE ────────────────────────────────────
echo ""
echo ">>> [3/5] Đang khởi động Apache..."
systemctl enable httpd
systemctl start httpd
systemctl status httpd --no-pager | head -5
echo "✅ [3/5] Apache running on port 80"

# ── [4/5] TẠO WEB APP ─────────────────────────────────────────
echo ""
echo ">>> [4/5] Đang tạo web application..."

# Tạo file cấu hình database (tách riêng để bảo mật)
cat > /var/www/html/db_config.php << 'CONFEOF'
<?php
/**
 * db_config.php — Cấu hình kết nối database
 * Giá trị được inject bởi Terraform templatefile()
 * File này có permission 640 — chỉ Apache đọc được
 */
define('DB_HOST',     '${db_host}');      // 172.199.10.180
define('DB_NAME',     '${db_name}');      // graduation_db
define('DB_USER',     '${db_user}');      // postgres
define('DB_PASSWORD', '${db_password}');  // HoaTranLab@DB2025!
define('DB_PORT',     '5432');

/**
 * Hàm kết nối database — trả về PDO object
 * Dùng PDO để tránh SQL injection
 */
function getDB() {
    $dsn = "pgsql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME;
    return new PDO($dsn, DB_USER, DB_PASSWORD, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_TIMEOUT            => 5,
    ]);
}
CONFEOF

# Tạo trang web chính
cat > /var/www/html/index.php << 'PHPEOF'
<?php
/**
 * index.php — Web Form + Database
 *
 * Chức năng:
 *   1. Hiển thị thông tin hạ tầng (EC2 ID, AZ, DB host)
 *   2. Form nhập tên nhóm + ngày nộp
 *   3. Lưu xuống PostgreSQL trên Proxmox
 *   4. Hiển thị dữ liệu đã lưu real-time
 */
require_once 'db_config.php';

$message   = '';
$msg_class = '';
$records   = [];

// ── Xử lý form submit (POST request) ──────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $group_name = trim(htmlspecialchars($_POST['group_name'] ?? ''));
    $sub_date   = trim($_POST['submission_date'] ?? date('Y-m-d'));

    if (empty($group_name)) {
        $message   = '⚠️ Vui lòng nhập tên nhóm!';
        $msg_class = 'warning';
    } else {
        try {
            $pdo  = getDB();
            // Prepared statement — chống SQL Injection
            $stmt = $pdo->prepare(
                "INSERT INTO submissions (group_name, submission_date) VALUES (:gn, :sd)"
            );
            $stmt->execute([':gn' => $group_name, ':sd' => $sub_date]);

            $message   = "✅ Lưu thành công! Nhóm: <strong>$group_name</strong> | Ngày: $sub_date";
            $msg_class = 'success';
        } catch (PDOException $e) {
            $message   = "❌ Lỗi kết nối Database Proxmox: " . $e->getMessage();
            $msg_class = 'error';
        }
    }
}

// ── Lấy dữ liệu đã lưu để hiển thị ───────────────────────────
$db_status = '';
try {
    $pdo     = getDB();
    $records = $pdo->query(
        "SELECT * FROM submissions ORDER BY submitted_at DESC LIMIT 10"
    )->fetchAll();
    $db_status = '🟢 Kết nối PostgreSQL @ Proxmox thành công';
} catch (PDOException $e) {
    $db_status = '🔴 Lỗi: ' . $e->getMessage();
}

// ── Lấy thông tin EC2 metadata ────────────────────────────────
$meta_base  = 'http://169.254.169.254/latest/meta-data/';
$instance_id = @file_get_contents($meta_base . 'instance-id') ?: 'N/A';
$az          = @file_get_contents($meta_base . 'placement/availability-zone') ?: 'N/A';
$local_ip    = @file_get_contents($meta_base . 'local-ipv4') ?: 'N/A';
?>
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🚀 Hybrid Cloud — Graduation Project</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #f0f2f5; color: #333; }

        /* Header */
        .header {
            background: linear-gradient(135deg, #232f3e 0%, #ff9900 100%);
            color: white; padding: 30px 20px; text-align: center;
        }
        .header h1 { font-size: 26px; margin-bottom: 8px; }
        .header p  { font-size: 14px; opacity: 0.9; }

        /* Main container */
        .container { max-width: 900px; margin: 30px auto; padding: 0 16px; }

        /* Cards */
        .card {
            background: white; border-radius: 12px;
            padding: 24px; margin-bottom: 22px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
        }
        .card h2 {
            font-size: 18px; color: #232f3e;
            border-bottom: 3px solid #ff9900;
            padding-bottom: 10px; margin-bottom: 18px;
        }

        /* Info grid */
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 14px; }
        .info-item {
            background: #f8f9fa; border-left: 4px solid #ff9900;
            padding: 10px 14px; border-radius: 6px; font-size: 13px;
        }
        .info-item strong { display: block; color: #888; font-size: 10px; text-transform: uppercase; margin-bottom: 4px; }

        /* DB status badge */
        .badge {
            display: inline-block; padding: 5px 14px;
            border-radius: 20px; font-size: 13px; font-weight: 600;
        }
        .badge-ok    { background: #e8f5e9; color: #2e7d32; border: 1px solid #81c784; }
        .badge-error { background: #ffebee; color: #c62828; border: 1px solid #e57373; }

        /* Form elements */
        label { display: block; font-weight: 600; font-size: 13px; color: #555; margin-bottom: 6px; }
        input[type=text], input[type=date] {
            width: 100%; padding: 11px 14px;
            border: 1.5px solid #ddd; border-radius: 8px;
            font-size: 14px; margin-bottom: 14px; transition: border-color 0.2s;
        }
        input:focus { outline: none; border-color: #ff9900; box-shadow: 0 0 0 3px rgba(255,153,0,0.15); }

        /* Submit button */
        .btn {
            width: 100%; padding: 13px; background: #ff9900;
            color: white; border: none; border-radius: 8px;
            font-size: 15px; font-weight: 700; cursor: pointer;
            transition: background 0.2s;
        }
        .btn:hover { background: #e68a00; }

        /* Messages */
        .msg { padding: 12px 16px; border-radius: 8px; margin-bottom: 14px; font-size: 14px; }
        .success { background: #e8f5e9; border: 1px solid #a5d6a7; color: #2e7d32; }
        .error   { background: #ffebee; border: 1px solid #ef9a9a; color: #c62828; }
        .warning { background: #fff3e0; border: 1px solid #ffcc02; color: #e65100; }

        /* Table */
        table { width: 100%; border-collapse: collapse; font-size: 13px; }
        thead th { background: #232f3e; color: white; padding: 11px 14px; text-align: left; }
        tbody td { padding: 10px 14px; border-bottom: 1px solid #eee; }
        tbody tr:hover td { background: #fffde7; }
        .empty-state { text-align: center; color: #aaa; padding: 40px 0; font-size: 15px; }

        /* Footer */
        .footer { text-align: center; color: #aaa; font-size: 12px; padding: 20px 0; }
    </style>
</head>
<body>

<div class="header">
    <h1>🚀 Hybrid Cloud Infrastructure Demo</h1>
    <p>AWS EC2 (ap-southeast-1) ↔ PostgreSQL @ Proxmox On-Premise (172.199.10.180)</p>
</div>

<div class="container">

    <!-- Card 1: Thông tin hạ tầng -->
    <div class="card">
        <h2>📡 Thông Tin Hạ Tầng</h2>
        <div class="info-grid">
            <div class="info-item">
                <strong>EC2 Instance ID</strong>
                <?= htmlspecialchars($instance_id) ?>
            </div>
            <div class="info-item">
                <strong>Availability Zone</strong>
                <?= htmlspecialchars($az) ?>
            </div>
            <div class="info-item">
                <strong>EC2 Private IP</strong>
                <?= htmlspecialchars($local_ip) ?>
            </div>
            <div class="info-item">
                <strong>DB Host (Proxmox)</strong>
                <?= DB_HOST ?>:<?= DB_PORT ?>
            </div>
        </div>
        <span class="badge <?= strpos($db_status,'🟢') !== false ? 'badge-ok' : 'badge-error' ?>">
            <?= $db_status ?>
        </span>
    </div>

    <!-- Card 2: Form nhập liệu -->
    <div class="card">
        <h2>📝 Nhập Thông Tin Nhóm</h2>

        <?php if ($message): ?>
            <div class="msg <?= $msg_class ?>">
                <?= $message ?>
            </div>
        <?php endif; ?>

        <form method="POST" action="">
            abel for="group_name">Tên Nhóm: <span style="color:red">*</span></label>
            <input type="text" id="group_name" name="group_name"
                   placeholder="VD: Nhóm DevOps Tốt Nghiệp K2025"
                   maxlength="100" required>

            abel for="submission_date">Ngày Nộp:</label>
            <input type="date" id="submission_date" name="submission_date"
                   value="<?= date('Y-m-d') ?>" required>

            <button type="submit" class="btn">
                💾 Lưu Vào Database Proxmox
            </button>
        </form>
    </div>

    <!-- Card 3: Dữ liệu đã lưu -->
    <div class="card">
        <h2>📊 Dữ Liệu Real-time từ PostgreSQL @ Proxmox</h2>

        <?php if (!empty($records)): ?>
        <table>
            <thead>
                <tr>
                    <th>#</th>
                    <th>Tên Nhóm</th>
                    <th>Ngày Nộp</th>
                    <th>Thời Gian Lưu</th>
                </tr>
            </thead>
            <tbody>
            <?php foreach ($records as $i => $row): ?>
                <tr>
                    <td><?= $i + 1 ?></td>
                    <td><?= htmlspecialchars($row['group_name']) ?></td>
                    <td><?= $row['submission_date'] ?></td>
                    <td><?= $row['submitted_at'] ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        <?php else: ?>
            <p class="empty-state">
                📭 Chưa có dữ liệu.<br>Hãy nhập thông tin nhóm ở form trên và nhấn Submit!
            </p>
        <?php endif; ?>
    </div>

</div>

<div class="footer">
    Hybrid Cloud Demo | AWS + Proxmox + HCP Terraform | Graduation Project 2025
</div>

</body>
</html>
PHPEOF

echo "✅ [4/5] Web application created"

# ── [5/5] PHÂN QUYỀN FILE ─────────────────────────────────────
echo ""
echo ">>> [5/5] Đang set permissions..."
chown -R apache:apache /var/www/html
chmod 640 /var/www/html/db_config.php   # Chỉ apache đọc được — bảo vệ DB credentials
chmod 644 /var/www/html/index.php
restorecon -R /var/www/html 2>/dev/null || true  # SELinux context (nếu có)
echo "✅ [5/5] Permissions set"

echo ""
echo "=================================================="
echo "🎉 USERDATA HOÀN THÀNH: $(date)"
echo "   Web App: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)"
echo "   DB Host: ${db_host}:5432"
echo "   DB Name: ${db_name}"
echo "=================================================="
