variable "github_org_repo" {
  description = "GitHub org/repo (e.g. myorg/tf-aws). Used for OIDC trust policy."
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to assume the role (e.g. main). Use '*' to allow any ref."
  type        = string
  default     = "main"
}

variable "github_environment" {
  description = "Optional. GitHub environment name. If set, trust is restricted to that environment."
  type        = string
  default     = null
}
