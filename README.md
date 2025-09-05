# Snake Game on AWS EKS with Observability & CI/CD

This repo provisions AWS infra with Terraform, deploys a containerized Snake Game to EKS, and installs monitoring (Prometheus/Grafana) and ingress-nginx. Includes GitHub Actions for CI/CD.

## Quick Start

- Prereqs: Terraform >= 1.5, AWS account, GitHub OIDC role with `AWS_OIDC_ROLE_ARN` secret, kubectl.
- Build/push via GitHub Actions on push to main. Or locally:

```bash
# Build & push (replace account id/region/repo)
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin <acct>.dkr.ecr.ap-southeast-1.amazonaws.com
IMAGE_TAG=local
docker build -t <acct>.dkr.ecr.ap-southeast-1.amazonaws.com/snake-game:$IMAGE_TAG .
docker push <acct>.dkr.ecr.ap-southeast-1.amazonaws.com/snake-game:$IMAGE_TAG

# Terraform deploy
cd terraform
terraform init
terraform apply -auto-approve -var "snake_image_tag=$IMAGE_TAG"
```

- Access: find ingress LB DNS from ingress-nginx service; set `var.snake_host` and DNS if desired.

## Storage Backend

- `var.storage_backend = "s3"` (default) stores JSON score objects under `scores/YYYY/MM/DD/`.
- `var.storage_backend = "aurora"` provisions Aurora Serverless v2 PG. Create tables:

```sql
create table if not exists scores(
  id uuid primary key,
  user_id text,
  points int not null,
  created_at timestamptz default now()
);
```

## Observability

- Prometheus scrapes `/metrics` from app via `ServiceMonitor`.
- Grafana LB: admin/admin123 (change in `helm/monitoring-values.yaml`).
- Dashboard JSON: `grafana/dashboards/snake-game.json`.

## Architecture

See `docs/architecture.mmd`.

## Notes

- Defaults to region ap-southeast-1. Update `var.region` as needed.
- Update `var.eks_version` to a supported version for your account.
- TLS/ACM may be added to ingress-nginx annotations and certificate management.
