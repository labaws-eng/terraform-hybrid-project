# ============================================================
# modules/proxmox/main.tf
#
# Dùng Telmate Proxmox Provider để:
#   1. Kết nối Proxmox API tại 172.199.10.165:8006
#   2. Clone VM từ template ID=100 → VM mới ID=200
#   3. Cấu hình IP tĩnh qua cloud-init
#   4. SSH vào VM và cài PostgreSQL
#
# KHÔNG dùng username/password → dùng API Token
# Token được lưu dạng Sensitive Variable trên HCP Terraform
# ============================================================

provider "proxmox" {
  # URL Proxmox API — từ HCP Terraform Variable
  pm_api_url = var.proxmox_api_url
  # → https://172.199.10.165:8006/api2/json

  # Token ID — Sensitive, không hiển thị trong output
  pm_api_token_id = var.proxmox_token_id
  # → root@pam!terraform-token

  # Token Secret — Sensitive UUID
  pm_api_token_secret = var.proxmox_token_secret
  # → 622976ef-66d2-4c67-9638-28b13dcc730f

  # Bỏ qua lỗi TLS certificate (Proxmox dùng self-signed cert)
  # Trong production nên dùng cert hợp lệ
  pm_tls_insecure = true

  # Bật debug log để dễ troubleshoot
  pm_log_enable = true
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}

# ============================================================
# TẠO VM DATABASE BẰNG CÁCH CLONE TỪ TEMPLATE
#
# Flow:
#   [1] Clone VM 100 (Ubuntu template) → VM 200 (ubuntu-db-vm)
#   [2] Cloud-init set IP tĩnh 172.199.10.180/24
#   [3] Cloud-init inject SSH public key
#   [4] VM boot → SSH sẵn sàng
#   [5] Provisioner SSH vào VM → chạy commands
#   [6] Cài PostgreSQL → Tạo DB → Cấu hình remote access
# ============================================================
resource "proxmox_vm_qemu" "db_vm" {

  # ── Thông tin cơ bản ──────────────────────────────────────
  name        = "ubuntu-db-vm"      # Tên hiển thị trong Proxmox UI
  vmid        = var.db_vm_id        # ID = 200
  target_node = var.node            # promox02

  # Clone từ template VM ID=100 (Ubuntu đã cài sẵn cloud-init)
  clone       = var.template_vm_id  # 100

  # ── Tài nguyên phần cứng ─────────────────────────────────
  cores   = var.db_vm_cores    # 2 vCPU
  memory  = var.db_vm_memory   # 2048 MB RAM
  scsihw  = "virtio-scsi-pci"  # SCSI controller tốt hơn cho Linux
  os_type = "cloud-init"       # Bật cloud-init support

  # QEMU Guest Agent — cho phép Proxmox giao tiếp với VM
  # (Phải đã cài qemu-guest-agent trong template)
  agent   = 1

  # Tự động bật VM sau khi tạo và sau mỗi lần Proxmox reboot
  oncreate = true
  onboot   = true

  # Thời gian chờ VM hoàn thành boot (giây)
  timeout = 600  # 10 phút

  # ── Disk ─────────────────────────────────────────────────
  disk {
    slot     = "scsi0"          # Khe cắm SCSI đầu tiên
    size     = "40G"            # Kích thước ổ cứng
    type     = "scsi"
    storage  = var.storage      # local-lvm
    iothread = 1                # Tăng hiệu năng I/O
  }

  # ── Network ──────────────────────────────────────────────
  network {
    model  = "virtio"     # Driver mạng hiệu năng cao
    bridge = var.bridge   # vmbr0
  }

  # ── Cloud-Init Configuration ──────────────────────────────
  # IP tĩnh: ip=172.199.10.180/24,gw=172.199.10.1
  ipconfig0  = "ip=${var.db_vm_ip},gw=${var.db_gateway}"

  # DNS servers
  nameserver = "8.8.8.8"

  # Username mặc định của Ubuntu cloud image
  ciuser = "ubuntu"

  # Public key → VM sẽ cho phép SSH bằng private key tương ứng
  sshkeys = var.ssh_public_key
  # → ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2zlQI4k2H...

  # ── Lifecycle ─────────────────────────────────────────────
  lifecycle {
    # Bỏ qua thay đổi network và disk sau khi VM đã tạo
    # (tránh Terraform cố destroy-recreate VM)
    ignore_changes = [network, disk]
  }

  # ============================================================
  # PROVISIONER: remote-exec
  #
  # Sau khi VM boot xong, Terraform SSH vào VM và chạy
  # danh sách commands dưới đây theo thứ tự.
  #
  # Kết nối SSH dùng private key tương ứng với public key
  # đã inject qua cloud-init (ssh_public_key variable)
  # ============================================================
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_ed25519")  # Private key local
      host        = "172.199.10.180"            # IP tĩnh đã set
      timeout     = "15m"                       # Chờ tối đa 15 phút
    }

    inline = [
      # ── Banner ──────────────────────────────────────────────
      "echo ''",
      "echo '===================================================='",
      "echo '>>> [PROVISIONER] SSH kết nối VM thành công! ✅'",
      "echo '>>> Host: ubuntu@172.199.10.180'",
      "echo '>>> Time: '$(date)",
      "echo '===================================================='",
      "echo ''",

      # ── [1/6] Update system ─────────────────────────────────
      "echo '>>> [1/6] Đang update hệ thống...'",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "echo '✅ [1/6] System updated'",
      "echo ''",

      # ── [2/6] Cài PostgreSQL ────────────────────────────────
      "echo '>>> [2/6] Đang cài đặt PostgreSQL 14...'",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib",
      "echo '✅ [2/6] PostgreSQL installed'",
      "echo ''",

      # ── [3/6] Enable & Start ────────────────────────────────
      "echo '>>> [3/6] Enable và start PostgreSQL service...'",
      "sudo systemctl enable postgresql",
      "sudo systemctl start postgresql",
      "sudo systemctl status postgresql --no-pager | head -8",
      "echo '✅ [3/6] PostgreSQL is running'",
      "echo ''",

      # ── [4/6] Tạo Database & Table ──────────────────────────
      "echo '>>> [4/6] Đang tạo database và table...'",

      # Đổi password user postgres
      "sudo -u postgres psql -c \"ALTER USER postgres WITH PASSWORD '${var.db_password}';\"",

      # Tạo database
      "sudo -u postgres psql -c \"CREATE DATABASE graduation_db;\"",

      # Tạo bảng submissions
      "sudo -u postgres psql -d graduation_db -c \"\nCREATE TABLE IF NOT EXISTS submissions (\n  id              SERIAL PRIMARY KEY,\n  group_name      VARCHAR(100) NOT NULL,\n  submission_date DATE NOT NULL,\n  submitted_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP\n);\n\"",

      "echo '✅ [4/6] Database graduation_db và table submissions đã tạo'",
      "echo ''",

      # ── [5/6] Cấu hình Remote Access ────────────────────────
      "echo '>>> [5/6] Cấu hình PostgreSQL cho phép kết nối từ xa...'",

      # Sửa postgresql.conf: listen_addresses = '*' (lắng nghe tất cả interfaces)
      "sudo sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/\" /etc/postgresql/*/main/postgresql.conf",

      # Thêm rule vào pg_hba.conf: cho phép kết nối từ EC2 (10.10.0.0/16)
      "echo \"# Allow EC2 subnet (AWS)\" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf",
      "echo \"host graduation_db postgres 10.10.0.0/16 md5\" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf",

      # Cho phép kết nối từ mọi IP (lab only — trong production giới hạn IP)
      "echo \"host graduation_db postgres 0.0.0.0/0 md5\" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf",

      # Restart để apply cấu hình mới
      "sudo systemctl restart postgresql",
      "sudo systemctl status postgresql --no-pager | head -5",
      "echo '✅ [5/6] Remote access đã cấu hình'",
      "echo ''",

      # ── [6/6] Xác nhận ──────────────────────────────────────
      "echo '>>> [6/6] Kiểm tra xác nhận...'",
      "sudo -u postgres psql -d graduation_db -c '\\dt'",
      "sudo -u postgres psql -d graduation_db -c 'SELECT version();'",
      "sudo -u postgres psql -d graduation_db -c 'SELECT COUNT(*) FROM submissions;'",
      "echo ''",

      # ── Done Banner ─────────────────────────────────────────
      "echo '===================================================='",
      "echo '🎉 PROVISIONER HOÀN THÀNH THÀNH CÔNG!'",
      "echo ''",
      "echo '   📍 VM IP    : 172.199.10.180'",
      "echo '   🐘 Database : graduation_db'",
      "echo '   👤 User     : postgres'",
      "echo '   🔌 Port     : 5432'",
      "echo '   📋 Table    : submissions'",
      "echo '===================================================='",
    ]
  }
}
