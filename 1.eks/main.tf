terraform {
  backend "s3" {
    bucket = ""
    key    = ""
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

resource "aws_subnet" "eks-co-privatesubnet-test-1" {
  vpc_id              = var.vpc_id
  cidr_block          = var.cidr_private_1
  availability_zone   = "us-east-1${var.availability_zone_1}"

  tags = {
    "Name"                                      = "eks-${var.solg_project}-privatesubnet-${var.environment}-${var.availability_zone_1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "project"                                   = var.solg_project
  }
}

resource "aws_subnet" "eks-co-privatesubnet-test-2" {
  vpc_id              = var.vpc_id
  cidr_block          = var.cidr_private_2
  availability_zone   = "us-east-1${var.availability_zone_2}"

  tags = {
    "Name"                                       = "eks-${var.solg_project}-privatesubnet-${var.environment}-${var.availability_zone_2}"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.cluster_name}"  = "owned"
    "project"                                    = var.solg_project
  }
}

resource "aws_subnet" "eks-co-publicsubnet-test-1" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_public_1
  availability_zone       = "us-east-1${var.availability_zone_1}"
  map_public_ip_on_launch = false

  tags = {
    "Name"                                      = "eks-${var.solg_project}-publicsubnet-${var.environment}-${var.availability_zone_1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "project"                                   = var.solg_project
  }
}

resource "aws_subnet" "eks-co-publicsubnet-test-2" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_public_2
  availability_zone       = "us-east-1${var.availability_zone_2}"
  map_public_ip_on_launch = false

  tags = {
    "Name"                                      = "eks-${var.solg_project}-publicsubnet-${var.environment}-${var.availability_zone_2}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "project"                                   = var.solg_project
  }
}

resource "aws_eip" "nat" {
  domain   = "vpc"

  tags = {
    Name = "eks-${var.solg_project}-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.eks-co-publicsubnet-test-1.id

  tags = {
    Name = "eks-${var.solg_project}-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name      = "eks-${var.solg_project}-private"
    "project" = var.solg_project
  }
}

resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = {
    Name      = "eks-${var.solg_project}-public"
    "project" = var.solg_project
  }
}

resource "aws_route_table_association" "eks-co-privatesubnet-test-1" {
  subnet_id      = aws_subnet.eks-co-privatesubnet-test-1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "eks-co-privatesubnet-test-2" {
  subnet_id      = aws_subnet.eks-co-privatesubnet-test-2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "eks-co-publicsubnet-test-1" {
  subnet_id      = aws_subnet.eks-co-publicsubnet-test-1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "eks-co-publicsubnet-test-2" {
  subnet_id      = aws_subnet.eks-co-publicsubnet-test-2.id
  route_table_id = aws_route_table.public.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  vpc_id                          = var.vpc_id
  subnet_ids                      = [ aws_subnet.eks-co-privatesubnet-test-1.id, aws_subnet.eks-co-privatesubnet-test-2.id ]
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  cluster_enabled_log_types = []

  enable_irsa = true

  eks_managed_node_groups = {
    nodegroup = {
      name = "node-group-${var.solg_project}"

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      use_custom_launch_template = false
      disk_size = 30

      labels = {
        role        = "private-nodes"
        project     = var.solg_project
        environment = var.environment
      }

      desired_size = 3
      max_size     = 3
      min_size     = 1
    }
  }

  tags = {
    project     = var.solg_project
    environment = var.environment
  }
}

data "aws_iam_policy_document" "csi" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks_ebs_csi_driver" {
  assume_role_policy = data.aws_iam_policy_document.csi.json
  name               = "eks-ebs-csi-driver-${var.cluster_name}"
}

resource "aws_iam_role_policy_attachment" "amazon_ebs_csi_driver" {
  role       = aws_iam_role.eks_ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.25.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.eks_ebs_csi_driver.arn
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

resource "helm_release" "csi-driver-smb" {
  name       = "csi-driver-smb"

  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts"
  chart      = "csi-driver-smb"
  namespace  = "kube-system"
  version    = "1.11.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
}

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "aws-load-balancer-controller-${var.cluster_name}"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.5.4"

  set {
    name  = "replicaCount"
    value = 2
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller_irsa_role.iam_role_arn
  }
}