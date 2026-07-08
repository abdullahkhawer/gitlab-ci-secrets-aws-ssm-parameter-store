variable "create_oidc_provider" {
  description = "Set to false when the GitLab OIDC provider already exists in the account. The existing provider will be looked up by URL instead of created."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region to create resources in."
  type        = string
  default     = "eu-west-1"
}

variable "gitlab_url" {
  description = "Base URL of your GitLab instance."
  type        = string
  default     = "https://gitlab.com"
}

variable "oidc_audience" {
  description = "Audience value for the OIDC token (must match SSM_OIDC_AUDIENCE in the CI template)."
  type        = string
  default     = "https://gitlab.com"
}

variable "role_name" {
  description = "Name of the IAM role GitLab CI jobs will assume."
  type        = string
  default     = "gitlab-ci-ssm-reader"
}

variable "allowed_sub" {
  description = <<-EOT
    Optional GitLab JWT sub claim to restrict which projects/branches can assume
    the role. Use AWS StringLike wildcards (* matches any sequence, ? matches one
    character), e.g.:
      project_path:mygroup/myproject:ref_type:branch:ref:master
    Leave empty to allow any GitLab project that presents a valid OIDC token.
  EOT
  type        = string
  default     = ""
}

variable "ssm_parameter_arns" {
  description = <<-EOT
    List of SSM Parameter ARNs (or ARN prefixes with wildcard) the role is
    allowed to read. Example:
      ["arn:aws:ssm:eu-west-1:123456789012:parameter/myapp/prod/*"]
  EOT
  type        = list(string)
}

variable "kms_key_arns" {
  description = <<-EOT
    Optional list of KMS key ARNs used to encrypt SecureString parameters.
    Required when parameters use a customer-managed key (CMK).
    Leave empty to rely on the AWS-managed SSM key (no extra KMS policy needed).
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
