variable "ssh_public_key" { type = string }
variable "domain"         { type = string }
variable "acme_email"     { type = string }
variable "repo_url"       { type = string }
variable "size"           { default = "s-2vcpu-4gb" } # 2 vCPU, 4 GB
variable "region"         { default = "nyc1" }