# CloudGuard Controller AWS Organization Deployment
This Terraform project is intended to create all the configuration for a deployment of CloudGuard Controller in an entire AWS organization. The project takes care of configure both the AWS components as well as creating the AWS Datacenters in the Check Point management.      

## Get API credentials for your user in the management 
First you would need to have access to the Check Point management to create the objects, this is how you create an user:

![Architectural Design](/resources/chkp-api-user-creation.jpg)

Remember to copy these two values, you will need to enter them in the *.tfvars* file later on.

## How to use it
The only thing that you need to do is changing the __*terraform.tfvars*__ file located in this directory.

```hcl
# Set in this file your deployment variables
aws-access-key  = "xxxxxxxxxxxxxx"
aws-secret-key  = "xxxxxxxxxxxxxx"

chkp-management-api-key = "xxxxxxxxxxxxxx"
chkp-management = {
    server  = "xx.xx.xx.xx/24"
  }
```
If you want (or need) to further customize other project details, you can change defaults in the different __*name-variables.tf*__ files. Here you will also able to find the descriptions that explains what each variable is used for.