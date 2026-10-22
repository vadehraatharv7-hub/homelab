output "vms" {
  description = "Name, VM ID, zone and address of every VM."
  value = {
    for name, vm in local.vms : name => {
      hostname = vm.hostname
      vmid     = vm.vmid
      zone     = vm.zone
      vlan     = local.zones[vm.zone].vlan
      ip       = vm.ip
    }
  }
}

output "router_requirements" {
  description = "What your router/firewall has to provide for the VMs to work."
  value = [
    "VLAN ${var.dmz_vlan} (honeypots): interface ${local.zones.dmz.gateway}/${local.zones.dmz.prefix}",
    "VLAN ${var.core_vlan} (dashboard + database): interface ${local.zones.core.gateway}/${local.zones.core.prefix}",
    "Allow ${local.zones.dmz.cidr} -> ${local.monitoring_ip} tcp/8081 and nothing else towards the core zone",
    "Allow ${var.admin_cidr} -> both zones on tcp/22222, and -> ${local.monitoring_ip} on tcp/80,443",
    "Block both zones from reaching your LAN and any other internal network",
    "Port-forward WAN tcp/22 and tcp/23 -> ${local.vms.honeypot.ip}, WAN tcp/80 and tcp/443 -> ${local.vms.snare.ip}",
    "Allow both zones out to the internet (web, DNS to ${var.dns_server}, NTP)",
  ]
}

output "confirm_installs_command" {
  description = "Run on the Proxmox host to confirm the unattended installs (see README)."
  value       = "for id in ${join(" ", [for vm in local.vms : vm.vmid])}; do qm sendkey $id y; qm sendkey $id e; qm sendkey $id s; qm sendkey $id ret; done"
}

output "inventory_file" {
  description = "Ansible inventory written by Terraform."
  value       = abspath("${path.module}/${var.inventory_path}")
}

output "mongo_connection_string" {
  description = "Connection string the dashboard uses. Also in the inventory."
  value       = local.mongo_uri
  sensitive   = true
}
