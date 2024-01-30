terraform {
  backend "s3" {
    bucket = ""
    key    = "-prometheus"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "eks" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  token                  = data.aws_eks_cluster_auth.eks.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

resource "helm_release" "prometheus" {
  depends_on = [ kubernetes_namespace.monitoring ]
  name             = "prometheus"

  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  version          = "48.3.3"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  values = [
    file("${path.module}/new-values.yaml")
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  depends_on = [ helm_release.prometheus ]
  wait_for_load_balancer = true
  metadata {
    name      = "ingress-grafana"
    namespace = "monitoring"
    annotations = {
      "alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:us-east-1:088707152208:certificate/257a9de5-9561-41ea-85d5-a4095ac61fa2"
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/ssl-policy" = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      "alb.ingress.kubernetes.io/group.name" = var.cluster_name
      "alb.ingress.kubernetes.io/group.order" = "2"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = "${var.grafanaurl}.${var.host_zone}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "ssl-redirect"
              port {
                name = "use-annotation"
              }
            }
          }
        }
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "prometheus-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts = [ "${var.grafanaurl}.${var.host_zone}" ]
    }
  }
}

data "aws_lb" "ingress_load_balancer" {
  depends_on = [ kubernetes_ingress_v1.grafana ]
  tags = {
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = var.cluster_name
    "elbv2.k8s.aws/cluster"    = var.cluster_name
  }
}

data "aws_route53_zone" "selected" {
  name = var.host_zone
}

resource "aws_route53_record" "root_domain" {
  depends_on = [ kubernetes_ingress_v1.grafana ]
  zone_id    = data.aws_route53_zone.selected.zone_id
  name       = "${var.grafanaurl}.${var.host_zone}"
  type       = "CNAME"
  ttl        = "300"
  records    = [data.aws_lb.ingress_load_balancer.dns_name]
}

