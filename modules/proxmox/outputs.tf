# ============================================================
# modules/proxmox/outputs.tf
# Xuất thông tin VM lên root module
# ============================================================

output "db_vm_ip" {
  description = "IP tĩnh của Database VM — EC2 kết nối tới đây"
  value       = "172.199.10.180"
  # IP tĩnh cố định, không dùng biến tránh dependency cycle
}

output "db_vm_id" {
  description = "VM ID trên Proxmox"
  value       = proxmox_vm_qemu.db_vm.vmid
}

output "db_vm_name" {
  description = "Tên VM trên Proxmox"
  value       = proxmox_vm_qemu.db_vm.name
}
