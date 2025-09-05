provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = { Project = var.project }
}

data "aws_availability_zones" "available" {}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "1.6.0"

  repository_name = "${var.project}"
  tags            = { Project = var.project }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.1"

  cluster_name    = "${var.project}-eks"
  cluster_version = var.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      min_size     = 2
      max_size     = 4
      desired_size = 2
      instance_types = ["t3.medium"]
    }
  }

  enable_irsa = true
  tags        = { Project = var.project }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Ingress NGINX
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true

  values = [file("${path.module}/../helm/ingress-nginx-values.yaml")]
}

# kube-prometheus-stack
resource "helm_release" "monitoring" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  create_namespace = true

  values = [file("${path.module}/../helm/monitoring-values.yaml")]
}

# Kubevious (optional)
resource "helm_release" "kubevious" {
  name       = "kubevious"
  repository = "https://helm.kubevious.io"
  chart      = "kubevious"
  namespace  = "kubevious"
  create_namespace = true
  values = [file("${path.module}/../helm/kubevious-values.yaml")]
}

# Grafana dashboard as ConfigMap to auto-import (sidecar picks it up in kube-prometheus-stack)
resource "kubernetes_config_map" "snake_dashboard" {
  metadata {
    name      = "snake-game-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "snake-game.json" = file("${path.module}/../grafana/dashboards/snake-game.json")
  }
  depends_on = [helm_release.monitoring]
}

# Optional S3 bucket for simple storage
resource "aws_s3_bucket" "scores" {
  count  = var.storage_backend == "s3" ? 1 : 0
  bucket = "${var.project}-${data.aws_caller_identity.current.account_id}-${var.region}"
  tags   = { Project = var.project }
}

resource "aws_s3_bucket_versioning" "scores" {
  count  = var.storage_backend == "s3" ? 1 : 0
  bucket = aws_s3_bucket.scores[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scores" {
  count  = var.storage_backend == "s3" ? 1 : 0
  bucket = aws_s3_bucket.scores[0].id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}

# Optional Aurora Serverless v2 (PostgreSQL)
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "9.9.0"
  count   = var.storage_backend == "aurora" ? 1 : 0

  name                = "${var.project}-aurora"
  engine              = "aurora-postgresql"
  engine_mode         = "provisioned"
  engine_version      = "15.3"
  master_username     = "snake"
  manage_master_user_password = true
  instances = { one = { instance_class = "db.serverless" } }
  serverlessv2_scaling_configuration = { min_capacity = 0.5, max_capacity = 2 }

  vpc_id               = module.vpc.vpc_id
  subnets              = module.vpc.private_subnets
  create_random_password = true
  storage_encrypted    = true
  enable_http_endpoint = true

  security_group_rules = {
    ingress_from_nodes = {
      type        = "ingress"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "Postgres from EKS nodes"
      source_security_group_id = module.eks.node_security_group_id
    }
  }

  tags = { Project = var.project }
}

# Kubernetes resources: namespace and app manifests
resource "kubernetes_manifest" "snake_app" {
  manifest = yamldecode(templatefile("${path.module}/../k8s/app.yaml", {
    SNAKE_IMAGE = "${module.ecr.repository_url}:${var.snake_image_tag}",
    SNAKE_HOST  = var.snake_host
  }))
  depends_on = [helm_release.ingress_nginx, helm_release.monitoring]
}


