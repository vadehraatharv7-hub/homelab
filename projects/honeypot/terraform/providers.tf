terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Proxmox VE. Pinned to the newest release: 3.0.x is the only line with
    # proxmox_storage_iso (downloads the installer ISO onto Proxmox) and
    # proxmox_cloud_init_disk (builds the unattended-install seed ISO).
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc10"
    }
    # Writes the Proxmox firewall files over SSH (see firewall.tf).
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # Generates the database password and the throw-away OS password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Writes the Ansible inventory.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Credentials come from credential.auto.tfvars (never commit it):
#   terraform_user  = the full API token ID, for example "terraform@pam!homelab"
#   terraform_token = the token's secret
provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.terraform_user
  pm_api_token_secret = var.terraform_token
  pm_tls_insecure     = var.pm_tls_insecure
}
