output "region" {
  description = "AWS region"
  value       = var.region
}

output "lb" {
  value = data.aws_lb.ingress_load_balancer.dns_name
}
