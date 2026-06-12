# ---------------------------------------------------------------------------
# IAM build user via cisagov/ami-build-iam-user-tf-module
#
# SECURITY FIX: The module's default ec2amicreate_policy_name ("EC2AMICreate")
# references a broadly-permissioned policy in the Images account.  This
# configuration overrides it with the AMIBuildLeastPrivilege policy defined
# below, which grants only the specific EC2 and KMS actions the Packer build
# pipeline uses.  SSM Parameter Store read access is already scoped by the
# ssm_parameters variable via the module's parameterstorereadonly_role.
# ---------------------------------------------------------------------------

module "iam_user" {
  source = "github.com/cisagov/ami-build-iam-user-tf-module"

  providers = {
    aws            = aws
    aws.images-ami = aws.images-ami
    aws.images-ssm = aws.images-ssm
  }

  # Replace the default EC2AMICreate policy (which grants ec2:* on *)
  # with the least-privilege policy defined below.
  ec2amicreate_policy_name = aws_iam_policy.ami_build_least_privilege.name

  ssm_parameters = [
    "/vnc/password",
    "/vnc/ssh/ed25519_private_key",
    "/vnc/ssh/ed25519_public_key",
    "/vnc/username",
    # Necessary when building any instances that run the Wazuh agent
    "/wazuh_agent/manager",
  ]
  user_name = "build-egress-assess-packer"
}

# ---------------------------------------------------------------------------
# Least-privilege policy for the AMI build pipeline
#
# Grants only the actions the Packer build needs:
#   - EC2: create/describe/deregister/register images, run/stop/terminate
#     instances, describe VPCs and subnets (for AMI Build VPC filtering)
#   - KMS: encrypt/decrypt/generate data keys for the cool-amis key alias
#
# Replaces the old EC2AMICreate policy that granted ec2:* on Resource: "*"
# with no conditions, allowing termination of any instance, deregistration
# of any AMI, or modification of any EC2 resource in the Images account.
#
# SSM Parameter Store read access is handled separately by the module's
# parameterstorereadonly_role (scoped to the specific paths in
# ssm_parameters), so it is not included here.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ami_build_least_privilege" {
  statement {
    sid    = "AMIManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateImage",
      "ec2:CreateTags",
      "ec2:DeregisterImage",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:RegisterImage",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.build_region]
    }
  }

  statement {
    sid    = "RunInstances"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    resources = [
      "arn:aws:ec2:${var.build_region}::image/*",
      "arn:aws:ec2:${var.build_region}:*:instance/*",
      "arn:aws:ec2:${var.build_region}:*:volume/*",
      "arn:aws:ec2:${var.build_region}:*:network-interface/*",
      "arn:aws:ec2:${var.build_region}:*:security-group/*",
      "arn:aws:ec2:${var.build_region}:*:subnet/*",
      "arn:aws:ec2:${var.build_region}::key-pair/*",
    ]
  }

  statement {
    sid    = "KMSForAMIEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    resources = ["*"]
    # TODO: Replace "*" with the specific KMS key ARN for the cool-amis
    # alias once the key ARN is available as a Terraform output or
    # variable.  The KMS key policy provides defense in depth, but
    # resource-level IAM scoping is best practice.
  }
}

resource "aws_iam_policy" "ami_build_least_privilege" {
  provider = aws.images-ami

  name        = "AMIBuildLeastPrivilege"
  description = "Least-privilege policy for the egress-assess-packer AMI build pipeline. Replaces the overly broad EC2AMICreate policy."
  policy      = data.aws_iam_policy_document.ami_build_least_privilege.json
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider and role
#
# Replaces the IAM user + long-lived access keys with a role that GitHub
# Actions can assume via OIDC federation.  The trust policy is scoped to
# the specific repository, so only workflows in that repo can assume the
# role.
#
# Migration steps:
# 1. Set create_oidc_role = true and configure github_org/github_repo
# 2. Add the OIDC role ARN as a GitHub secret (e.g. ACTIONS_ROLE_ARN)
# 3. Update the GitHub Actions workflow to use
#    aws-actions/configure-aws-credentials with role-to-assume
# 4. Remove the IAM user access key secrets
# 5. Once verified, remove the IAM user module entirely
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_role ? 1 : 0

  provider = aws.images-ami

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faaad9734211c7c3cfc77e9e0",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  count = var.create_oidc_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_build" {
  count = var.create_oidc_role ? 1 : 0

  provider = aws.images-ami

  name                 = "GitHubActions-AMIBuild"
  assume_role_policy   = data.aws_iam_policy_document.github_oidc_trust[0].json
  max_session_duration = 3600

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_build_policy" {
  count = var.create_oidc_role ? 1 : 0

  provider = aws.images-ami

  policy_arn = aws_iam_policy.ami_build_least_privilege.arn
  role       = aws_iam_role.github_actions_build[0].name
}
