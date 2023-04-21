// --- AWS Provider ---
variable "aws-region" {
  description = "AWS preferred region"
  default     = "eu-west-1"
  type        = string
}
variable "aws-access-key" {
  description = "AWS access key"
  sensitive   = true
  type        = string
}
variable "aws-secret-key" {
  description = "AWS secret key"
  sensitive   = true
  type        = string
}

// --- Check Point Management Provider ---
variable "chkp-management" {
  description = "The management that we would like to configure"
  type = object({
    name    = string
    server  = string
    domain  = optional(string)
    smart1cloud-id  = optional(string)
  })
}

variable "chkp-management-api-key" {
  description = "The credentials to connect as terraform to the management"
  sensitive   = true
  type        = string
}