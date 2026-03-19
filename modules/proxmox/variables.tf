# ============================================================
# modules/proxmox/variables.tf
# Biến đầu vào cho module Proxmox
# Các biến sensitive nhận giá trị từ HCP Terraform UI
# ============================================================

variable "proxmox_api_url" {
  description = "URL API Proxmox: https://172.199.10.165:8006"
  type        = string
}

variable "proxmox_token_id" {
  description = "API Token ID (user@realm!tokenname)"
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "API Token Secret (UUID)"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Password PostgreSQL"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH Public Key inject vào VM để SSH được vào"
  type        = string
}

variable "node" {
  description = "Tên Proxmox node"
  type        = string
  default     = "promox02"
}

variable "storage" {
  description = "Tên storage trên Proxmox"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Tên network bridge"
  type        = string
  default     = "vmbr0"
}

variable "template_vm_id" {
  description = "VM ID của template Ubuntu để clone"
  type        = number
  default     = 100
}

variable "db_vm_id" {
  description = "VM ID cho DB VM mới"
  type        = number
  default     = 200
}

variable "db_vm_cores" {
  description = "Số vCPU cho DB VM"
  type        = number
  default     = 2
}

variable "db_vm_memory" {
  description = "RAM cho DB VM (MB)"
  type        = number
  default     = 2048
}

variable "db_vm_ip" {
  description = "IP tĩnh gán cho DB VM"
  type        = string
  default     = "172.199.10.180/24"
}

variable "db_gateway" {
  description = "Default gateway cho DB VM"
  type        = string
  default     = "172.199.10.1"
}
