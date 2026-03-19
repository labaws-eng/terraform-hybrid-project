# ============================================================
# modules/aws/variables.tf
# Biến đầu vào cho module AWS — nhận giá trị từ root module
# ============================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block cho VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR cho public subnets (list)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "db_host" {
  description = "IP của DB server Proxmox — EC2 sẽ kết nối tới đây"
  type        = string
}

variable "db_password" {
  description = "Password PostgreSQL — dùng trong web app"
  type        = string
  sensitive   = true
}
