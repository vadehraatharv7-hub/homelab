# ---------------------------------------------------------------- Proxmox access

variable "pm_api_url" {
  type        = string
  description = "Proxmox API endpoint, for example https://pve.lan:8006/api2/json"

  validation {
    condition     = can(regex("^https://[^/]+/api2/json$", var.pm_api_url))
    error_message = "pm_api_url must look like https://HOST:8006/api2/json."
  }
}

variable "terraform_user" {
  type        = string
  sensitive   = true
  description = "Full API token ID: user@realm!tokenname (from credential.auto.tfvars)."
}

variable "terraform_token" {
  type        = string
  sensitive   = true
  description = "API token secret (from credential.auto.tfvars)."
}

variable "pm_tls_insecure" {
  type        = bool
  default     = false
  description = "Accept the self-signed certificate Proxmox ships with. Prefer installing a real certificate."
}

variable "pve_node" {
  type        = string
  description = "Name of the Proxmox node the VMs are created on."
}

variable "iso_storage" {
  type        = string
  default     = "local"
  description = "Proxmox storage that holds ISO images (must have the ISO content type enabled)."
}

variable "vm_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage for VM disks."
}

# ---------------------------------------------------------------- Operating system

variable "ubuntu_iso_url" {
  type        = string
  default     = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
  description = "Ubuntu 22.04 live-server ISO. The Ansible roles target 22.04."
}

variable "ubuntu_iso_filename" {
  type        = string
  default     = "ubuntu-22.04.5-live-server-amd64.iso"
  description = "File name the ISO gets on the Proxmox storage."
}

variable "ubuntu_iso_sha256" {
  type        = string
  default     = "9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
  description = "SHA-256 of the ISO, from https://releases.ubuntu.com/22.04/SHA256SUMS."
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Administrator account on every VM. The Ansible roles use /home/azureuser, so keep the default unless you change them."
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Public key to authorise for the administrator. Leave empty to read ssh_public_key_path."
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa_azure.pub"
  description = "File holding the public key, used when ssh_public_key is empty."
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa_azure"
  description = "Private key Ansible uses to log in (written to the inventory)."
}

variable "keyboard_layout" {
  type        = string
  default     = "us"
  description = "Keyboard layout configured by the installer."
}

# ---------------------------------------------------------------- Network

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox bridge to attach the VMs to. It must be VLAN-aware (Node > Network > edit the bridge > VLAN aware)."
}

variable "dmz_vlan" {
  type        = number
  default     = 66
  description = "VLAN ID of the honeypot zone: the sensors that attackers can and will compromise."

  validation {
    condition     = var.dmz_vlan >= 2 && var.dmz_vlan <= 4094
    error_message = "dmz_vlan must be between 2 and 4094."
  }
}

variable "core_vlan" {
  type        = number
  default     = 67
  description = "VLAN ID of the core zone: the dashboard and the database. Must differ from dmz_vlan."

  validation {
    condition     = var.core_vlan >= 2 && var.core_vlan <= 4094
    error_message = "core_vlan must be between 2 and 4094."
  }
}

variable "dmz_cidr" {
  type        = string
  default     = "10.66.0.0/24"
  description = "Subnet of the honeypot zone. Your router needs the .1 address of this subnet."
}

variable "core_cidr" {
  type        = string
  default     = "10.67.0.0/24"
  description = "Subnet of the core zone. Your router needs the .1 address of this subnet."
}

variable "dns_server" {
  type        = string
  default     = "1.1.1.1"
  description = "DNS server the VMs use. It is the only DNS server they are allowed to talk to."
}

variable "admin_cidr" {
  type        = string
  description = "Network your admin workstation is on, for example 192.168.1.0/24. Only this network may reach SSH (22222) and the dashboard."

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a CIDR such as 192.168.1.0/24."
  }
}

# ---------------------------------------------------------------- VMs

variable "vmid_base" {
  type        = number
  default     = 9100
  description = "VM IDs are vmid_base+1 .. +4 (honeypot, snare, monitoring, database)."
}

variable "vm_sizes" {
  type = map(object({
    cores     = number
    memory_mb = number
    disk      = string
  }))
  default = {
    honeypot   = { cores = 2, memory_mb = 2048, disk = "20G" }
    snare      = { cores = 2, memory_mb = 2048, disk = "20G" }
    monitoring = { cores = 2, memory_mb = 2048, disk = "20G" }
    database   = { cores = 2, memory_mb = 2048, disk = "40G" }
  }
  description = "CPU, memory and disk per VM."
}

variable "enable_guest_agent" {
  type        = bool
  default     = false
  description = "Tell Proxmox to use the QEMU guest agent. Leave false for the first apply (the agent only exists after the install), then set true and apply again."
}

# ---------------------------------------------------------------- Firewall (written over SSH)

variable "manage_firewall_rules" {
  type        = bool
  default     = true
  description = "Write per-VM Proxmox firewall rules over SSH. The provider cannot manage firewall rules, so this is how the zone isolation is enforced. Leave on."
}

variable "pve_ssh_host" {
  type        = string
  default     = ""
  description = "Host to SSH to for the firewall files. Empty = the host in pm_api_url."
}

variable "pve_ssh_user" {
  type        = string
  default     = "root"
  description = "User that may write /etc/pve/firewall."
}

variable "pve_ssh_private_key_path" {
  type        = string
  default     = ""
  description = "Private key for the Proxmox host. Empty = use your ssh-agent."
}

# ---------------------------------------------------------------- Output

variable "inventory_path" {
  type        = string
  default     = "inventory.ini"
  description = "Where the Ansible inventory is written (relative paths are relative to this directory)."
}
