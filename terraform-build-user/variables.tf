# ------------------------------------------------------------------------------
# Required parameters
#
# You must provide a value for each of these parameters.
# ------------------------------------------------------------------------------

variable "terraform_state_bucket" {
  description = "The name of the S3 bucket where Terraform state is stored."
  nullable    = false
  type        = string
}

# ------------------------------------------------------------------------------
# Optional parameters
#
# These parameters have reasonable defaults.
# ------------------------------------------------------------------------------

variable "build_region" {
  default     = "us-east-1"
  description = "The AWS region where AMI builds run. Used to restrict the IAM policy via the aws:RequestedRegion condition key."
  nullable    = false
  type        = string
}

variable "create_oidc_role" {
  default     = false
  description = "Create an IAM role with GitHub Actions OIDC trust policy as an alternative to the long-lived IAM user access keys. Set to true and configure github_org/github_repo to enable OIDC federation."
  nullable    = false
  type        = bool
}

variable "github_org" {
  default     = ""
  description = "The GitHub organization or user that owns the repository (e.g. cisagov). Required if create_oidc_role is true."
  type        = string
}

variable "github_repo" {
  default     = ""
  description = "The GitHub repository name (e.g. egress-assess-packer). Required if create_oidc_role is true."
  type        = string
}
