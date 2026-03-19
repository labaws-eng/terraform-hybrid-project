# ============================================================
# versions.tf
# Khai báo phiên bản Terraform, providers và kết nối HCP Cloud
#
# GIẢI THÍCH BLOCK cloud {}:
#   - organization: tên org trên app.terraform.io
#   - workspaces.name: tên workspace đã tạo
#   - Khi chạy terraform init, TF sẽ kết nối và lưu state
#     tại HCP Terraform thay vì local
#   - Execution Mode = LOCAL → plan/apply chạy trên MÁY MÌNH
#     HCP chỉ đóng vai trò lưu state và cung cấp biến
# ============================================================

terraform {
  required_version = ">= 1.7.0"

  cloud {
    organization = "hoatranlab-org"

    workspaces {
      name = "hybrid-infrastructure"
    }
  }

  required_providers {
    # Provider chính thức của HashiCorp cho AWS
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    # Provider Telmate cho Proxmox VE
    proxmox = {
      source  = "Telmate/proxmox"
      version = "2.9.14"
    }
  }
}
