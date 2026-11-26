variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type        = string
  default     = "digitalstudytools-admin"
  description = "Name of local AWS CLI profile (for static keys; SSO not used in PoC)"
}

variable "github_owner" {
  type = string
  default = "tommorgenstern"
}

variable "github_repo" {
  type = string
  default = "python-oop-study-dashboard-devops-cicd"
}