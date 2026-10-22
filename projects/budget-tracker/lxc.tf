resource "proxmox_lxc" "budget" {
  target_node = var.pve_node
  vmid        = var.ct_id == 0 ? null : var.ct_id # null = next free VMID
  hostname    = var.ct_hostname
  description = "Budget Tracker PWA (managed by Terraform: Homelab/projects/budget-tracker)"
  tags        = "budget-tracker;terraform"

  ostemplate      = local.ostemplate
  ostype          = "debian"
  unprivileged    = true # root in the container is an unprivileged user on the host
  password        = local.root_pw
  ssh_public_keys = local.ssh_public_key

  cores  = var.ct_cores
  memory = var.ct_memory_mb
  swap   = var.ct_swap_mb

  onboot = var.ct_start_on_boot
  start  = true

  rootfs {
    storage = var.ct_storage
    size    = "${var.ct_disk_gb}G"
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = var.ip_cidr
    gw     = var.gateway
    tag    = var.vlan_id == 0 ? null : var.vlan_id # null = untagged
  }

  nameserver = var.dns_server

  # systemd's service sandboxing (ProtectSystem, PrivateTmp) needs nesting inside an unprivileged container.
  features {
    nesting = true
  }

  depends_on = [null_resource.template]

  lifecycle {
    # The template is only used at creation; a newer one must not rebuild the container.
    ignore_changes = [ostemplate, ssh_public_keys, password, description] # description: Proxmox returns it with a trailing newline
  }
}
