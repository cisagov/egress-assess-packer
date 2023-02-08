module "iam_user" {
  source = "github.com/cisagov/ami-build-iam-user-tf-module"

  providers = {
    aws                       = aws
    aws.images-production-ami = aws.images-production-ami
    aws.images-staging-ami    = aws.images-staging-ami
    aws.images-production-ssm = aws.images-production-ssm
    aws.images-staging-ssm    = aws.images-staging-ssm
  }

  ssm_parameters = [
    "/vnc/password",
    "/vnc/username",
    "/vnc/ssh/rsa_private_key",
    "/vnc/ssh/rsa_public_key",
  ]
  user_name = "build-egress-assess-packer"
}
