output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider."
  value       = local.oidc_provider_arn
}

output "role_arn" {
  description = "ARN of the IAM role GitLab CI jobs should assume (set as SSM_ROLE_ARN)."
  value       = aws_iam_role.gitlab_ssm.arn
}

output "role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.gitlab_ssm.name
}
