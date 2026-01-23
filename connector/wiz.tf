module "wiz" {
  source                    = "https://wizio-public.s3.amazonaws.com/deployment-v3/aws/terraform/2343/wiz-aws-native-terraform-terraform-module.zip"
  external-id               = "ea72d577-93f7-46b0-8e13-c6f259ef405c"
  data-scanning             = true
  lightsail-scanning        = true
  eks-scanning              = true
  remote-arn                = "arn:aws:iam::830522659852:role/prod-us36-AssumeRoleDelegator"
  terraform-bucket-scanning = true
  cloud-cost-scanning       = true
}

output "wiz_connector_arn" {
  value = module.wiz.role_arn
}
