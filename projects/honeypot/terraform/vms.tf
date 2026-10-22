resource "proxmox_vm_qemu" "vm" {
  for_each = local.vms

  name        = each.value.hostname
  vmid        = each.value.vmid
  target_node = var.pve_node
  description = "Honeypot platform (${each.key}) - managed by Terraform. Zone: ${each.value.zone}."
  tags        = each.value.tags

  # Bring the VM back after a host reboot.
  start_at_node_boot = true
  power_state        = "running"

  memory  = var.vm_sizes[each.key].memory_mb
  scsihw  = "virtio-scsi-single"
  qemu_os = "l26"

  # With the guest agent switched on the provider waits for the VM to report an address,
  # which cannot happen until the installer has finished. Switch it on afterwards
  # (enable_guest_agent = true); the installer already puts the agent into the guest.
  agent = var.enable_guest_agent ? 1 : 0

  cpu {
    cores   = var.vm_sizes[each.key].cores
    sockets = 1
    type    = "host"
  }

  # The empty disk is skipped on first boot, so the installer ISO starts; after the
  # install the VM boots from its disk.
  boot = "order=scsi0;ide2"

  disks {
    ide {
      ide2 {
        cdrom {
          iso = "${var.iso_storage}:iso/${proxmox_storage_iso.ubuntu.filename}"
        }
      }
      ide3 {
        cdrom {
          iso = proxmox_cloud_init_disk.seed[each.key].id
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          storage  = var.vm_storage
          size     = var.vm_sizes[each.key].disk
          discard  = true
          iothread = true
        }
      }
    }
  }

  # One NIC, tagged with the zone's VLAN, with the Proxmox firewall switched on.
  network {
    id       = 0
    model    = "virtio"
    bridge   = var.bridge
    tag      = local.zones[each.value.zone].vlan
    firewall = true
  }

  define_connection_info = false

  lifecycle {
    # After the install the ISOs are no longer needed; changing them must not rebuild the VM.
    ignore_changes = [boot, bootdisk, disks[0].ide]
  }
}
