variable "project" { type = string, default = "snake-game" }
variable "region" { type = string, default = "ap-southeast-1" }
variable "eks_version" { type = string, default = "1.29" }
variable "storage_backend" { type = string, default = "s3" } # s3|aurora
variable "vpc_cidr" { type = string, default = "10.20.0.0/16" }
variable "private_subnets" { type = list(string), default = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"] }
variable "public_subnets" { type = list(string), default = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"] }
variable "snake_image_tag" { type = string, default = "latest" }
variable "snake_host" { type = string, default = "" } # set DNS if using ACM/Route53


