# ============================================================
# modules/aws/outputs.tf — Xuất giá trị lên root module
# ============================================================

output "alb_dns_name" {
  description = "DNS name của ALB — dùng để truy cập web app"
  value       = aws_lb.main.dns_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "web_instance_ids" {
  description = "Danh sách EC2 Instance IDs"
  value       = aws_instance.web[*].id
}
