# ============================================================
# main.tf — Root Module
#
# File này đóng vai trò "tổng chỉ huy":
# - Gọi module aws_infra để tạo tài nguyên AWS
# - Gọi module proxmox_infra để tạo VM trên Proxmox
# - Truyền biến từ root xuống các module con
#
# Credentials (AWS Keys, PG Token) đến tự động từ:
#   - HCP Terraform Environment Variables → provider aws {}
#   - HCP Terraform Terraform Variables   → var.proxmox_token_*
# ============================================================

# ── Module AWS ───────────────────────────────────────────────
module "aws_infra" {
  source = "./modules/aws"

  aws_region          = var.aws_region           # ap-southeast-1
  vpc_cidr            = var.vpc_cidr             # 10.10.0.0/16
  public_subnet_cidrs = var.public_subnet_cidrs  # ["10.10.1.0/24","10.10.2.0/24"]
  instance_type       = var.instance_type        # t3.micro
  db_host             = var.proxmox_db_ip        # 172.199.10.180
  db_password         = var.db_password          # Sensitive
}

# ── Module Proxmox ───────────────────────────────────────────
module "proxmox_infra" {
  source = "./modules/proxmox"

  proxmox_api_url      = var.proxmox_api_url       # https://172.199.10.165:8006
  proxmox_token_id     = var.proxmox_token_id      # Sensitive
  proxmox_token_secret = var.proxmox_token_secret  # Sensitive
  db_password          = var.db_password           # Sensitive
  ssh_public_key       = var.ssh_public_key        # Public key để SSH vào VM
}
