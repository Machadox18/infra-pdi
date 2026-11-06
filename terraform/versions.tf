terraform {
  cloud {
    organization = "gabriel-pdi"

    workspaces {
      name = "infra-pdi"
    }
  }

  required_version = ">= 1.6"
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean", version = "~> 2.0" }
    random       = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "digitalocean" {}