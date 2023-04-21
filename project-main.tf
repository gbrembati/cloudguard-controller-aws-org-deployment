# Creating Check Point local 
resource "aws_iam_user" "chkp-cg-controller-user" {
  name = "chkp-cloudguard-controller"

  tags = {
    purpose = "connecting-chkp-management"
  }
}
resource "aws_iam_access_key" "chkp-cg-controller-key" {
  user = aws_iam_user.chkp-cg-controller-user.name
}
data "aws_iam_policy_document" "chkp-cg-controller-pdocument" {
  statement {
    effect    = "Allow"
    actions   = [ 
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpnGateways",
        "ec2:DescribeVpnConnections",
        "ec2:DescribeCustomerGateways",
        "elasticloadbalancing:DescribeTags",
        "elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
}
resource "aws_iam_user_policy" "chkp-cg-controller-policy" {
  name   = "chkp-cloudguard-controller-policy"
  user   = aws_iam_user.chkp-cg-controller-user.name
  policy = data.aws_iam_policy_document.chkp-cg-controller-pdocument.json
}

data "aws_iam_policy_document" "chkp-cg-controller-sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"] 
    resources = ["arn:aws:iam::*:role/CloudGuard-Controller-RO-role"]
  }
}
resource "aws_iam_user_policy" "chkp-cg-controller-sts-policy" {
  name   = "chkp-cloudguard-controller-policy"
  user   = aws_iam_user.chkp-cg-controller-user.name
  policy = data.aws_iam_policy_document.chkp-cg-controller-sts.json
}

resource "random_string" "sts-external-id" {
  length  = 20
  special = false
  lower = true
  upper = false
}

output "my-external-id" {
  value = random_string.sts-external-id.result
}

# Creating the Cross account role in all the child accounts
resource "aws_cloudformation_stack_set" "cloudguard-controller-org-permissions" {
  name = "cloudguard-controller-permissions"
  permission_model  = "SERVICE_MANAGED"
  capabilities      = ["CAPABILITY_NAMED_IAM","CAPABILITY_IAM"]

  auto_deployment { enabled = true }
  operation_preferences {
    region_order = [ var.aws-region ]
    max_concurrent_percentage = 100
    failure_tolerance_percentage = 100
  }

  template_body = file("resources/cg-controller-role.yml")
  parameters = {
    RootAwsAccountId  = data.aws_organizations_organization.aws-organization.master_account_id
    RoleExternalTrustSecret = random_string.sts-external-id.result
  }

  tags = {
    "vendor"      = "check-point"
    "application" = "cloudguard-controller"
  }
}
resource "aws_cloudformation_stack_set_instance" "cft-deploy-organization" {
  region         = var.aws-region
  stack_set_name = aws_cloudformation_stack_set.cloudguard-controller-org-permissions.name

  deployment_targets {
    organizational_unit_ids = [data.aws_organizations_organization.aws-organization.roots[0].id]
  }
}

# Creating the datacenter which represents the root account
resource "checkpoint_management_aws_data_center_server" "root-aws-datacenter" {
  name = "aws-root-account"

  authentication_method = "user-authentication"
  access_key_id         = aws_iam_access_key.chkp-cg-controller-key.id
  secret_access_key     = aws_iam_access_key.chkp-cg-controller-key.secret
  region                = var.aws-region
} 

# Pulling the list of AWS accounts from the organization
data "aws_organizations_organization" "aws-organization" {}

# Creating the datacenter which represents the root account
resource "checkpoint_management_aws_data_center_server" "child-aws-datacenters" {
  for_each    = { for account in toset(data.aws_organizations_organization.aws-organization.accounts) : account.name => account } 

  name = each.value.name

  authentication_method = "user-authentication"
  access_key_id         = aws_iam_access_key.chkp-cg-controller-key.id
  secret_access_key     = aws_iam_access_key.chkp-cg-controller-key.secret
  region                = var.aws-region

  enable_sts_assume_role = true
  sts_role = "arn:aws:iam::${each.value.id}:role/CloudGuard-Controller-RO-role"
  sts_external_id = random_string.sts-external-id.result
} 

resource "terraform_data" "aws-account-change-tracker" {
  input = data.aws_organizations_organization.aws-organization
}
resource "checkpoint_management_publish" "publish" { 
  lifecycle {
    replace_triggered_by = [
      terraform_data.aws-account-change-tracker
    ]
  }
  # Would be triggered if there is a change in the list of accounts
  depends_on = [checkpoint_management_aws_data_center_server.root-aws-datacenter, checkpoint_management_aws_data_center_server.child-aws-datacenters] 
}
