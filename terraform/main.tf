terraform {
  required_version = ">= 1.5, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── GitLab OIDC Identity Provider ────────────────────────────────────────────

data "tls_certificate" "gitlab" {
  count = var.create_oidc_provider ? 1 : 0
  url   = var.gitlab_url
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = var.gitlab_url
  client_id_list  = [var.oidc_audience]
  thumbprint_list = [data.tls_certificate.gitlab[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "gitlab_existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = var.gitlab_url
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.gitlab[0].arn : data.aws_iam_openid_connect_provider.gitlab_existing[0].arn
}

# ── IAM Role assumed by GitLab CI jobs ───────────────────────────────────────

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(trimprefix(var.gitlab_url, "https://"), "http://")}:aud"
      values   = [var.oidc_audience]
    }

    # Restrict to specific GitLab projects/branches if desired.
    # Set var.allowed_sub to a glob, e.g.:
    #   "project_path:mygroup/myproject:ref_type:branch:ref:master"
    dynamic "condition" {
      for_each = var.allowed_sub != "" ? [1] : []
      content {
        test     = "StringLike"
        variable = "${trimprefix(trimprefix(var.gitlab_url, "https://"), "http://")}:sub"
        values   = [var.allowed_sub]
      }
    }
  }
}

resource "aws_iam_role" "gitlab_ssm" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# ── IAM Policy: least-privilege SSM read access ──────────────────────────────

data "aws_iam_policy_document" "ssm_read_doc" {
  # Read individual parameters by exact path only (no recursive path fetching)
  statement {
    sid    = "SSMGetParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = var.ssm_parameter_arns
  }

  # Decrypt SecureString parameters with the specified KMS key(s)
  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      sid    = "KMSDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
      ]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_policy" "ssm_read" {
  name   = "${var.role_name}-ssm-read"
  policy = data.aws_iam_policy_document.ssm_read_doc.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_read" {
  role       = aws_iam_role.gitlab_ssm.name
  policy_arn = aws_iam_policy.ssm_read.arn
}
