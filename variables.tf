# ============================================================
# variables.tf — Khai báo tất cả biến đầu vào
#
# QUAN TRỌNG: File này CHỈ khai báo kiểu dữ liệu và mô tả.
# GIÁ TRỊ THỰC được cung cấp từ 2 nguồn:
#   1. HCP Terraform Variables UI (cho sensitive)
#   2. default value (cho các biến không nhạy cảm)
#
# KHÔNG được hardcode password/token/key tại đây
# ============================================================

# ── Nhóm biến AWS ────────────────────────────────────────────

variable "aws_region" {
  description = "AWS Region để triển khai tài nguyên"
  type        = string
  default     = "ap-southeast-1"
  # ap-southeast-1 = Singapore — gần VN nhất, latency thấp
}

variable "vpc_cidr" {
  description = "CIDR block cho VPC chính (dải IP riêng trong AWS)"
  type        = string
  default     = "10.10.0.0/16"
  # /16 = 65,536 địa chỉ IP — đủ dùng cho lab
}

variable "public_subnet_cidrs" {
  description = "CIDR cho 2 public subnets — ALB yêu cầu tối thiểu 2 AZ khác nhau"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
  # subnet 1: AZ ap-southeast-1a
  # subnet 2: AZ ap-southeast-1b
}

variable "instance_type" {
  description = "Loại EC2 instance cho web server"
  type        = string
  default     = "t3.micro"
  # t3.micro: 2 vCPU, 1GB RAM — Free Tier eligible
}

# ── Nhóm biến Proxmox (Sensitive — lấy từ HCP Terraform UI) ──

variable "proxmox_api_url" {
  description = "URL endpoint API của Proxmox VE"
  type        = string
  # Giá trị set trên HCP UI: https://172.199.10.165:8006
  # Format: https://<IP>:<PORT> (mặc định 8006)
}

variable "proxmox_token_id" {
  description = "API Token ID theo format: user@realm!tokenname"
  type        = string
  sensitive   = true
  # Giá trị set SENSITIVE trên HCP UI: root@pam!terraform-token
  # sensitive = true → không hiển thị trong plan/apply output
}

variable "proxmox_token_secret" {
  description = "UUID Secret của Proxmox API Token"
  type        = string
  sensitive   = true
  # Giá trị set SENSITIVE trên HCP UI: 622976ef-66d2-4c67-9638-28b13dcc730f
}

variable "db_password" {
  description = "Mật khẩu PostgreSQL — TUYỆT ĐỐI không hardcode"
  type        = string
  sensitive   = true
  # Giá trị set SENSITIVE trên HCP UI: HoaTranLab@DB2025!
}

variable "ssh_public_key" {
  description = "SSH Public Key để inject vào VM qua cloud-init (cho phép SSH vào VM)"
  type        = string
  # Giá trị set trên HCP UI: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
}

variable "proxmox_db_ip" {
  description = "IP tĩnh gán cho Database VM trên Proxmox"
  type        = string
  default     = "172.199.10.180"
}
