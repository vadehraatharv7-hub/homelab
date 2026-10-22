# One small "cidata" ISO per VM carries the unattended-install answers. The Ubuntu
# installer finds it on its own and installs without asking questions (it asks once
# for confirmation: see README, "Confirm the installs").
locals {
  user_data = {
    for name, vm in local.vms : name => join("\n", [
      "#cloud-config",
      yamlencode({
        autoinstall = {
          version  = 1
          locale   = "en_US.UTF-8"
          keyboard = { layout = var.keyboard_layout }
          identity = {
            hostname = vm.hostname
            username = var.admin_username
            password = random_password.os_admin.bcrypt_hash
          }
          ssh = {
            install-server  = true
            allow-pw        = false
            authorized-keys = [local.ssh_public_key]
          }
          # Static address; the router (.1) provides the way out and the port forwards.
          network = {
            version = 2
            ethernets = {
              lan = {
                match       = { driver = "virtio_net" }
                set-name    = "eth0" # the Ansible roles and xdp-shield expect eth0, as on Azure
                dhcp4       = false
                dhcp6       = false
                addresses   = ["${vm.ip}/${local.zones[vm.zone].prefix}"]
                routes      = [{ to = "default", via = local.zones[vm.zone].gateway }]
                nameservers = { addresses = [var.dns_server] }
              }
            }
          }
          storage  = { layout = { name = "direct" } }
          packages = ["qemu-guest-agent", "python3", "sudo", "curl", "ca-certificates"]
          updates  = "security"
          late-commands = [
            # The honeypot decoys use port 22, so the real SSH moves to 22222 (as in the Azure setup).
            "curtin in-target --target=/target -- sed -i 's/^#\\?Port .*/Port 22222/' /etc/ssh/sshd_config",
            "curtin in-target --target=/target -- systemctl enable qemu-guest-agent",
            "echo '${var.admin_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-${var.admin_username}",
            "chmod 440 /target/etc/sudoers.d/90-${var.admin_username}",
          ]
          shutdown = "reboot"
        }
      })
    ])
  }
}

resource "proxmox_cloud_init_disk" "seed" {
  for_each = local.vms

  name      = "seed-${each.value.hostname}"
  pve_node  = var.pve_node
  storage   = var.iso_storage
  user_data = local.user_data[each.key]
  meta_data = yamlencode({
    "instance-id"    = "${each.value.hostname}-${each.value.vmid}"
    "local-hostname" = each.value.hostname
  })
}
