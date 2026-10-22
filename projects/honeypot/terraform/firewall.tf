# Zone isolation, enforced by the Proxmox firewall on each VM's virtual NIC.
#
# The telmate provider has no firewall resources, so this file renders one
# /etc/pve/firewall/<vmid>.fw per VM and copies it to the Proxmox host over SSH.
# The rules are enforced by the hypervisor, outside the guest: a root shell on a
# compromised honeypot cannot switch them off.
#
# Policy for every VM: drop everything, then allow only what the role needs.
#
#   honeypot / snare (DMZ)   in : decoy ports from anywhere, SSH from admin
#                            out: dashboard 8081, DNS, NTP, web to the public internet only
#   monitoring (core)        in : 8081 from the DMZ, UI + SSH from admin
#                            out: database 27017, DNS, NTP, web to the public internet only
#   database (core)          in : 27017 from the dashboard, SSH from admin
#                            out: DNS, NTP, web to the public internet only
#
# Nothing in the DMZ can reach the database, the LAN, or any other private network.

locals {
  # Everything that is not the public internet.
  private_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"]

  rules_common_out = [
    "OUT ACCEPT -p udp -dest ${var.dns_server} -dport 53 # DNS",
    "OUT ACCEPT -p tcp -dest ${var.dns_server} -dport 53 # DNS over TCP",
    "OUT ACCEPT -p udp -dport 123 # NTP",
  ]

  # Order matters: the first matching rule wins, so private ranges are dropped before web is allowed.
  rules_web_out = concat(
    [for r in local.private_ranges : "OUT DROP -dest ${r} # never reach local networks"],
    ["OUT ACCEPT -p tcp -dport 80,443 # package updates, git, downloads"],
  )

  rules = {
    honeypot = concat(
      [
        "IN ACCEPT -p tcp -dport 22,23 # SSH + Telnet decoys (Cowrie), forwarded by the router",
        "IN ACCEPT -source ${var.admin_cidr} -p tcp -dport 22222 # administration",
        "OUT ACCEPT -p tcp -dest ${local.monitoring_ip} -dport 8081 # events + ban list",
      ],
      local.rules_common_out,
      local.rules_web_out,
    )
    snare = concat(
      [
        "IN ACCEPT -p tcp -dport 80,443 # web decoy (Snare), forwarded by the router",
        "IN ACCEPT -source ${var.admin_cidr} -p tcp -dport 22222 # administration",
        "OUT ACCEPT -p tcp -dest ${local.monitoring_ip} -dport 8081 # events",
      ],
      local.rules_common_out,
      local.rules_web_out,
    )
    monitoring = concat(
      [
        "IN ACCEPT -source ${var.dmz_cidr} -p tcp -dport 8081 # sensors send events / xdp-shield reads the ban list",
        "IN ACCEPT -source ${var.admin_cidr} -p tcp -dport 80,443,22222 # dashboard + administration",
        "OUT ACCEPT -p tcp -dest ${local.database_ip} -dport 27017 # MongoDB",
      ],
      local.rules_common_out,
      local.rules_web_out,
    )
    database = concat(
      [
        "IN ACCEPT -source ${local.monitoring_ip} -p tcp -dport 27017 # only the dashboard",
        "IN ACCEPT -source ${var.admin_cidr} -p tcp -dport 22222 # administration",
      ],
      local.rules_common_out,
      local.rules_web_out,
    )
  }

  firewall_files = {
    for name, vm in local.vms : name => join("\n", concat(
      [
        "# Managed by Terraform - changes made here are overwritten.",
        "# macfilter drops frames with a forged source MAC; ipfilter drops packets (and ARP)",
        "# whose source address is not the one in the ipfilter-net0 set below.",
        "[OPTIONS]",
        "enable: 1",
        "policy_in: DROP",
        "policy_out: DROP",
        "macfilter: 1",
        "ipfilter: 1",
        "dhcp: 0",
        "ndp: 0",
        "radv: 0",
        "log_level_in: nolog",
        "log_level_out: nolog",
        "",
        "[IPSET ipfilter-net0]",
        vm.ip,
        "",
        "[RULES]",
      ],
      local.rules[name],
      [""],
    ))
  }
}

resource "null_resource" "firewall" {
  for_each = var.manage_firewall_rules ? local.vms : {}

  # Re-run when the rules change or the target changes. The values are also kept
  # here because destroy-time provisioners may only read "self".
  triggers = {
    vmid     = each.value.vmid
    rules    = sha256(local.firewall_files[each.key])
    host     = local.pve_host
    user     = var.pve_ssh_user
    key_path = var.pve_ssh_private_key_path
  }

  connection {
    type        = "ssh"
    host        = self.triggers.host
    user        = self.triggers.user
    private_key = self.triggers.key_path != "" ? file(pathexpand(self.triggers.key_path)) : null
    agent       = self.triggers.key_path == ""
  }

  provisioner "file" {
    content     = local.firewall_files[each.key]
    destination = "/etc/pve/firewall/${each.value.vmid}.fw"
  }

  provisioner "remote-exec" {
    when   = destroy
    inline = ["rm -f /etc/pve/firewall/${self.triggers.vmid}.fw"]
  }

  # The VM must exist before its firewall file is picked up.
  depends_on = [proxmox_vm_qemu.vm]
}
