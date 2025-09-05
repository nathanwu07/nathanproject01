output "cluster_name" { value = module.eks.cluster_name }
output "ecr_repository_url" { value = module.ecr.repository_url }
output "ingress_nginx_lb_hostname" { value = try(helm_release.ingress_nginx.metadata["load_balancer_hostname"], null) }
output "s3_bucket_name" { value = try(aws_s3_bucket.scores[0].bucket, null) }
output "aurora_endpoint" { value = try(module.aurora[0].cluster_endpoint, null) }


