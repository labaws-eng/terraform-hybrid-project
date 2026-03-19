# ============================================================
# modules/aws/main.tf
#
# AWS Provider tự động đọc credentials từ biến môi trường:
#   AWS_ACCESS_KEY_ID     = AKIAXGIN4CQTMHKFB7FT
#   AWS_SECRET_ACCESS_KEY = 7mb1xpe/...
# Hai biến này đã được set dạng Environment Variable (Sensitive)
# trên HCP Terraform UI → không cần khai báo trong code
#
# Thứ tự tạo tài nguyên:
#   VPC → IGW → Subnets → Route Table → Security Groups
#   → EC2 instances → ALB → Target Group → Listener
# ============================================================

provider "aws" {
  region = var.aws_region
}

# ── DATA SOURCES ─────────────────────────────────────────────
# Lấy danh sách Availability Zones đang available tại region
data "aws_availability_zones" "available" {
  state = "available"
}

# Lấy AMI Amazon Linux 2023 mới nhất (64-bit x86)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── VPC ──────────────────────────────────────────────────────
# Virtual Private Cloud — mạng riêng ảo trong AWS
# enable_dns_*: cho phép EC2 dùng hostname nội bộ
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr  # 10.10.0.0/16
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name    = "hybrid-vpc"
    Project = "graduation"
  }
}

# ── INTERNET GATEWAY ─────────────────────────────────────────
# Cổng kết nối VPC ra Internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "hybrid-igw" }
}

# ── PUBLIC SUBNETS ────────────────────────────────────────────
# Tạo 2 subnet ở 2 AZ khác nhau
# ALB bắt buộc phải có ≥2 subnet ở ≥2 AZ khác nhau
# count = 2 → lặp 2 lần với index 0 và 1
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true  # EC2 trong subnet này tự nhận Public IP

  tags = { Name = "public-subnet-${count.index + 1}" }
}

# ── ROUTE TABLE ───────────────────────────────────────────────
# Bảng định tuyến: traffic ra 0.0.0.0/0 (internet) → qua IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-rt" }
}

# Gắn route table vào từng subnet
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── SECURITY GROUP: ALB ───────────────────────────────────────
# Firewall rules cho Application Load Balancer
# ALB chỉ nhận HTTP:80 từ bất kỳ IP nào (internet)
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow HTTP inbound from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP từ internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ALB cần ra ngoài để forward request đến EC2
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# ── SECURITY GROUP: EC2 WEB SERVERS ──────────────────────────
# Firewall rules cho EC2 instances
# EC2 CHỈ nhận HTTP:80 từ ALB (không expose trực tiếp ra internet)
# → Đây là mô hình Zero-Trust / Defense in Depth
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTP only from ALB Security Group — Zero-Trust"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP chỉ từ ALB security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    # Thay vì mở cho IP, chỉ mở cho traffic đến từ alb-sg
  }

  # EC2 cần ra ngoài để:
  # 1. Download packages (apt/yum)
  # 2. Kết nối PostgreSQL trên Proxmox qua VPN
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web-sg" }
}

# ── USER DATA: Script cài web app ─────────────────────────────
# templatefile() đọc file .sh và thay thế ${variable} bằng giá trị thực
# Script này chạy TỰ ĐỘNG khi EC2 boot lần đầu tiên
locals {
  web_userdata = templatefile("${path.module}/userdata/web_userdata.sh", {
    db_host     = var.db_host      # → 172.199.10.180
    db_password = var.db_password  # → HoaTranLab@DB2025! (sensitive)
    db_name     = "graduation_db"
    db_user     = "postgres"
  })
}

# ── EC2 INSTANCES ─────────────────────────────────────────────
# Tạo 2 web servers: count.index = 0 và 1
# Mỗi server ở 1 AZ khác nhau → High Availability
resource "aws_instance" "web" {
  count                  = 2
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type  # t3.micro
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = local.web_userdata  # Script chạy lúc boot

  tags = {
    Name    = "web-server-${count.index + 1}"
    Role    = "WebServer"
    Project = "graduation"
  }
}

# ── APPLICATION LOAD BALANCER ─────────────────────────────────
# ALB phân phối traffic đến 2 EC2 instances
# internal = false → public-facing (nhận traffic từ internet)
resource "aws_lb" "main" {
  name               = "hybrid-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id  # 2 subnets, 2 AZ

  tags = { Name = "hybrid-alb" }
}

# ── TARGET GROUP ──────────────────────────────────────────────
# Nhóm EC2 instances sẽ nhận traffic từ ALB
# Health check: ALB kiểm tra EC2 còn sống không bằng cách GET "/"
resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30   # Kiểm tra mỗi 30 giây
    timeout             = 5    # Timeout sau 5 giây
    healthy_threshold   = 2    # OK sau 2 lần thành công
    unhealthy_threshold = 3    # Fail sau 3 lần thất bại
  }

  tags = { Name = "web-tg" }
}

# ── ĐĂNG KÝ EC2 VÀO TARGET GROUP ────────────────────────────
# Báo cho Target Group biết EC2 nào nằm trong nhóm
resource "aws_lb_target_group_attachment" "web" {
  count            = length(aws_instance.web)
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# ── ALB LISTENER ──────────────────────────────────────────────
# Quy tắc: khi ALB nhận request HTTP:80 → forward đến Target Group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
