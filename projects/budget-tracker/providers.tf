terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Same provider and pin as ../honeypot/terraform, so one plugin download serves both stacks.
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc10"
    }
    # Downloads the container template on the Proxmox host and bootstraps the app inside the container (SSH).
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # Generates the web UI password when you do not set one.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Asks the Proxmox host which Debian 12 template is currently published (see template.tf).
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# Credentials come from credential.auto.tfvars (never commit it). This folder symlinks the shared one in ../../shared/proxmox:
#   terraform_user  = the full API token ID, for example "terraform@pam!homelab"
#   terraform_token = the token's secret
provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.terraform_user
  pm_api_token_secret = var.terraform_token
  pm_tls_insecure     = var.pm_tls_insecure
}
