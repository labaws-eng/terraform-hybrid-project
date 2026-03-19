# ============================================================
# outputs.tf — Kết quả xuất ra sau khi terraform apply xong
#
# Terraform sẽ in 3 giá trị này ra màn hình:
#   1. DNS ALB → dùng để truy cập web app qua trình duyệt
#   2. DB IP   → IP của VM PostgreSQL trên Proxmox
#   3. EC2 IDs → Danh sách instance ID để debug nếu cần
# ============================================================

output "RESULT_alb_dns_name" {
  description = "✅ DNS của AWS Application Load Balancer — Dán vào trình duyệt để test web app"
  value       = module.aws_infra.alb_dns_name
}

output "RESULT_db_vm_ip" {
  description = "✅ IP nội bộ của VM Database trên Proxmox On-Premise"
  value       = module.proxmox_infra.db_vm_ip
}

output "RESULT_web_instance_ids" {
  description = "✅ Danh sách EC2 Instance IDs của web servers"
  value       = module.aws_infra.web_instance_ids
}
