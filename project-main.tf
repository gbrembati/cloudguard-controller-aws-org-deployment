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

resource "aws_iam_policy" "chkp-cg-controller-read-policy" {
  name        = "chkp-cg-controller-read-policy"
  path        = "/"
  description = "IAM Policy used to read datacenter objects from the master account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpnGateways",
          "ec2:DescribeVpnConnections",
          "ec2:DescribeCustomerGateways",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeLoadBalancers" ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
resource "aws_iam_policy" "chkp-cg-controller-sts-policy" {
  name        = "chkp-cg-controller-sts-policy"
  path        = "/"
  description = "IAM Policy used to Assume roles in child account to read datacenter objects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [ "sts:AssumeRole" ]
        Effect   = "Allow"
        Resource = "arn:aws:iam::*:role/CloudGuard-Controller-RO-role"
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "attach-chkp-cg-controller-read-policy" {
  user       = aws_iam_user.chkp-cg-controller-user.name
  policy_arn = aws_iam_policy.chkp-cg-controller-read-policy.arn
}
resource "aws_iam_user_policy_attachment" "attach-chkp-cg-controller-sts-policy" {
  user       = aws_iam_user.chkp-cg-controller-user.name
  policy_arn = aws_iam_policy.chkp-cg-controller-sts-policy.arn
}

resource "random_string" "sts-external-id" {
  length  = 20
  special = false
  lower = true
  upper = false
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

  depends_on = [aws_iam_user_policy_attachment.attach-chkp-cg-controller-read-policy]
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
  ignore_warnings       = true

  enable_sts_assume_role = true
  sts_role = "arn:aws:iam::${each.value.id}:role/CloudGuard-Controller-RO-role"
  sts_external_id = random_string.sts-external-id.result

  depends_on = [aws_cloudformation_stack_set_instance.cft-deploy-organization]
} 

resource "terraform_data" "aws-account-change-tracker" {
  input = data.aws_organizations_organization.aws-organization
}
resource "checkpoint_management_publish" "session-publish" { 
  lifecycle {
    replace_triggered_by = [
      terraform_data.aws-account-change-tracker
    ]
  }
  # Would be triggered if there is a change in the list of accounts
  depends_on = [checkpoint_management_aws_data_center_server.root-aws-datacenter, checkpoint_management_aws_data_center_server.child-aws-datacenters] 
}