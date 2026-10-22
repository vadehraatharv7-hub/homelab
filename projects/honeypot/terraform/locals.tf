locals {
  pve_host = var.pve_ssh_host != "" ? var.pve_ssh_host : regex("^https://([^:/]+)", var.pm_api_url)[0]

  ssh_public_key = trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path)))

  zones = {
    dmz = {
      vlan    = var.dmz_vlan
      cidr    = var.dmz_cidr
      gateway = cidrhost(var.dmz_cidr, 1)
      prefix  = split("/", var.dmz_cidr)[1]
    }
    core = {
      vlan    = var.core_vlan
      cidr    = var.core_cidr
      gateway = cidrhost(var.core_cidr, 1)
      prefix  = split("/", var.core_cidr)[1]
    }
  }

  # Host names match the Azure deployment: the dashboard names sensors after them.
  vms = {
    honeypot = {
      hostname = "vm-honeypot"
      vmid     = var.vmid_base + 1
      zone     = "dmz"
      ip       = cidrhost(var.dmz_cidr, 10)
      tags     = "honeypot;dmz"
    }
    snare = {
      hostname = "vm-snare"
      vmid     = var.vmid_base + 2
      zone     = "dmz"
      ip       = cidrhost(var.dmz_cidr, 11)
      tags     = "honeypot;dmz"
    }
    monitoring = {
      hostname = "vm-monitoring"
      vmid     = var.vmid_base + 3
      zone     = "core"
      ip       = cidrhost(var.core_cidr, 10)
      tags     = "dashboard;core"
    }
    database = {
      hostname = "vm-database"
      vmid     = var.vmid_base + 4
      zone     = "core"
      ip       = cidrhost(var.core_cidr, 11)
      tags     = "database;core"
    }
  }

  monitoring_ip = local.vms.monitoring.ip
  database_ip   = local.vms.database.ip

  mongo_uri = "mongodb://secdash:${random_password.mongo_app.result}@${local.database_ip}:27017/honeypot_db?authSource=honeypot_db"
}

# Password of the application account the dashboard uses on MongoDB.
# Letters and digits only, so it needs no URL escaping in the connection string.
resource "random_password" "mongo_app" {
  length  = 32
  special = false
}

# Password of the MongoDB administrator (used by Ansible to bootstrap and back up the database).
resource "random_password" "mongo_admin" {
  length  = 32
  special = false
}

# The installer insists on a password for the administrator. Nobody ever uses it:
# SSH password login is off and sudo needs no password. It is random and kept in state only.
resource "random_password" "os_admin" {
  length  = 32
  special = false
}

# The whole point of the layout is that the zones are separate.
check "zones_are_separate" {
  assert {
    condition     = var.dmz_vlan != var.core_vlan
    error_message = "dmz_vlan and core_vlan must be different VLANs."
  }
  assert {
    condition     = var.dmz_cidr != var.core_cidr
    error_message = "dmz_cidr and core_cidr must be different subnets."
  }
  assert {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must not be 0.0.0.0/0: that would open SSH and the dashboard to everything that can reach the VMs."
  }
}
