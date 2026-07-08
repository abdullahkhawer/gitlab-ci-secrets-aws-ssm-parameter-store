# GitLab CI Secrets: Enable AWS SSM Parameter Store as External Secrets Store

![GitLab](https://img.shields.io/badge/GitLab-%23330F63.svg?style=for-the-badge&logo=gitlab&logoColor=white) ![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazonwebservices&logoColor=white)

- Author: [Abdullah Khawer - LinkedIn](https://www.linkedin.com/in/abdullah-khawer)

## ℹ️ Introduction

🔭 Overview: A reusable GitLab CI template that fetches secrets from **AWS SSM Parameter Store** using short-lived OIDC credentials instead of long-lived AWS keys stored in GitLab. Easy to use: create AWS IAM resources, include the template, and define required variables to get started.

💡 Motivation: GitLab only supports AWS Secrets Manager. This template fills the gap for teams that use AWS SSM Parameter Store. AWS SSM Parameter Store is preferred over Secrets Manager when:
- **Cost matters** — standard parameters have no storage cost and API calls cost $0.05 per 10,000, while Secrets Manager charges $0.40 per secret per month for storage plus the same $0.05 per 10,000 API calls.
- **Scale amplifies savings** — 500 secrets accessed by 1,000 pipelines daily (~15 M API calls/month) costs ~$75/month on SSM Parameter Store vs. ~$275/month on Secrets Manager ($200 storage + $75 API), a 72% saving driven entirely by the per-secret storage fee.
- **Hierarchical paths with IAM-scoped policies** — SSM supports path-based IAM policies for fine-grained access control.
- **Unified config and secrets store** — when your infrastructure already uses SSM for configuration, you avoid paying the Secrets Manager premium just to keep secrets in the same place.

🔐 Security: Because each secret is a separate CI/CD variable, you can individually mask and protect every one of them directly in GitLab Settings, giving you fine-grained control over which branches and jobs can access each secret.

---

## ❔ How it works

```
GitLab CI job
  │
  ├─ 1. GitLab issues a short-lived OIDC JWT (id_tokens).
  │
  ├─ 2. Job assumes an IAM role via sts:AssumeRoleWithWebIdentity call with the JWT.
  │       → AWS validates the JWT against the registered OIDC IdP.
  │       → AWS returns temporary credentials (15-min lifetime).
  │
  ├─ 3. For each "AWS_SSM_PARAM_<NAME>" variable defined in the job template or in GitLab CI/CD Settings,
  │       → it fetches that SSM path.
  │       → SecureString parameters are decrypted automatically
  │
  ├─ 4. Each parameter value is exported as "<NAME>".
  │
  └─ 5. Temp credentials are deleted immediately after.
```

No static credentials ever touch GitLab. Jobs that define no `AWS_SSM_PARAM_*` variables make no AWS calls at all.

---

## ✅ Prerequisites

| Requirement | Notes |
|---|---|
| GitLab 15.7+ | Minimum version with `id_tokens` support |
| bash | Runner shell must be bash (the script uses pipefail and process substitution) |
| AWS CLI v2 | Auto-installed if not present in the runner image (Alpine < 3.17 receives v1 via apk; all other paths install v2) |
| AWS account | OIDC IdP + IAM role deployed (see [terraform/](terraform/)) |

---

## 🚀 Quick start

### Step 1 — Deploy the AWS IAM resources

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

The output emits the `role_arn` you need for the next step.

### Step 2 — Set required variables in GitLab project

In your GitLab project go to **Settings → CI/CD → Variables** and add:

| Variable | Value (example) | Protected | Masked |
|---|---|---|---|
| `SSM_ROLE_ARN` | `arn:aws:iam::123456789012:role/gitlab-ci-ssm-reader` | ✓ | ✓ |
| `SSM_AWS_REGION` | `eu-west-1` | | |
| `SSM_OIDC_AUDIENCE` | `https://gitlab.com` | | |
| `AWS_SSM_PARAM_<NAME>` | `/myapp/prod/<NAME>` | ✓ | ✓ |

### Step 3 — Include the template

Add the following in your `.gitlab-ci.yml`:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/abdullahkhawer/gitlab-ci-secrets-aws-ssm-parameter-store/master/templates/ssm-secrets.gitlab-ci.yml'
```

### Step 4 — Declare secrets per job

You have 3 options to define `AWS_SSM_PARAM_*` variables.

Let's assume, Parameter Key from AWS SSM Parameter Store is `/myapp/prod/db_password` and desired Variable is `$DB_PASSWORD`.

#### Option 1 — via GitLab Settings (Settings -> CI/CD -> Variables)

Add `AWS_SSM_PARAM_DB_PASSWORD=/myapp/prod/db_password` in Settings.

— **No YAML changes needed - `$DB_PASSWORD` variable will be available automatically in all pipeline jobs**

#### Option 2 — inline variables
```yaml
job:
  variables:
    AWS_SSM_PARAM_DB_PASSWORD: "/myapp/prod/db_password"
```

#### Option 3 — composing with an existing before_script via !reference:
```yaml
job:
  variables:
    AWS_SSM_PARAM_DB_PASSWORD: "/myapp/prod/db_password"
  before_script:
    - !reference [.fetch-ssm-secrets, before_script]
```

That's it. No `extends:`, no anchors in your own pipeline config, no boilerplate.

---

## ⚙️ Template variables

| Variable | Scope | Required | Description |
|---|---|---|---|
| `SSM_ROLE_ARN` | CI/CD Settings | Yes | ARN of the IAM role to assume |
| `SSM_AWS_REGION` | CI/CD Settings | Yes | AWS region where parameters live |
| `SSM_OIDC_AUDIENCE` | CI/CD Settings | Yes | OIDC audience; must match the IAM IdP |
| `AWS_SSM_PARAM_<NAME>` | Per-job `variables:`, or CI/CD Settings at project or group level | No (omit to skip all AWS calls) | Set to the SSM parameter path to fetch. The parameter value is exported as `<NAME>`. Define as many as needed. |

---

## 🏷️ Env var naming

The exported variable name is the suffix after `AWS_SSM_PARAM_`, exactly as written. GitLab enforces that CI/CD variable names contain only letters, numbers, and underscores, so the suffix is always a valid shell identifier:

| Variable defined | SSM path fetched | Exported as |
|---|---|---|
| `AWS_SSM_PARAM_DB_PASSWORD` | `/myapp/prod/DB_PASSWORD` | `DB_PASSWORD` |
| `AWS_SSM_PARAM_API_KEY` | `/myapp/prod/api/KEY` | `API_KEY` |
| `AWS_SSM_PARAM_JWT_SECRET` | `/myapp/prod/JWT_SECRET` | `JWT_SECRET` |
| `AWS_SSM_PARAM_APP_DB_PASS` | `/myapp/prod/db.password` | `APP_DB_PASS` |

---

## 🔑 OIDC token injection

The template declares `id_tokens: GITLAB_OIDC_TOKEN` under `default:`, so GitLab automatically injects the token into **every job** — including jobs with no `variables:` block in YAML (Option 1) and jobs that define their own `before_script` (Option 3). You do not need to add `id_tokens:` to your own job definition; it is already inherited.

---

## 🔒 IAM policy — least privilege

The Terraform module creates a policy scoped to the exact parameter paths you specify. Only individual parameter reads are permitted — no recursive path fetching. The minimum required actions are:

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameter"
  ],
  "Resource": "arn:aws:ssm:REGION:ACCOUNT:parameter/myapp/prod/DB_PASSWORD"
}
```

For SecureString parameters encrypted with a customer-managed KMS key, add:

```json
{
  "Effect": "Allow",
  "Action": ["kms:Decrypt"],
  "Resource": "arn:aws:kms:REGION:ACCOUNT:key/KEY_ID"
}
```

**Avoid `Resource: "*"`** — always scope to the exact parameter ARNs your pipeline needs.

---

## 🚫 Restricting which GitLab projects can assume the role

Set `allowed_sub` in `terraform.tfvars` to a sub claim pattern:

```
project_path:mygroup/myproject:ref_type:branch:ref:master
```

Wildcards are supported:

```
project_path:mygroup/*:ref_type:branch:ref:*    # any branch in any project under mygroup
```

Leaving this as `""` (empty) omits the `sub` condition entirely, allowing any GitLab project that presents a valid OIDC token — acceptable for a private GitLab instance but too permissive for gitlab.com.

---

## 🛡️ Security notes

- Temporary credentials are written to isolated temp files (created with `mktemp`, mode `600`). The AWS CLI is pointed at them via `AWS_SHARED_CREDENTIALS_FILE` and `AWS_CONFIG_FILE` environment variables, so pre-existing `~/.aws/` credentials on shared runners are never touched or overwritten. The temp files and env vars are cleaned up immediately after parameters are fetched.
- Parameter values are written to a private temporary file (created with `mktemp`, mode `600`) and deleted immediately after sourcing.
- The OIDC token (`GITLAB_OIDC_TOKEN`) is never logged.
- Protected variables (`SSM_ROLE_ARN`, `AWS_SSM_PARAM_*`) ensure only protected branches/tags can trigger role assumption.
- Each `AWS_SSM_PARAM_*` variable can be individually masked and protected in GitLab Settings, giving fine-grained control over which jobs and branches can access each secret path.

---

## 📝 License

Apache License 2.0 — see [LICENSE](LICENSE).

---

###### Any contributions, improvements and suggestions will be highly appreciated. 😊
