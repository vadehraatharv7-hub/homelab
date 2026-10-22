# Container templates are not downloadable through the API with this provider version, so ask the Proxmox host
# to fetch one with pveam, the same way the web UI does (Storage > CT Templates > Templates).

# Newest Debian 12 standard template currently published (runs at plan time; needs SSH to the Proxmox host).
data "external" "template" {
  count   = var.ct_template == "" ? 1 : 0
  program = ["bash", "${path.module}/scripts/latest-template.sh", local.pve_host, var.pve_ssh_user, var.pve_ssh_private_key_path]
}

resource "null_resource" "template" {
  count = var.manage_template ? 1 : 0

  triggers = {
    template = local.ct_template
    storage  = var.template_storage
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

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if pveam list ${self.triggers.storage} | grep -q '${self.triggers.template}'; then echo 'template already present'; exit 0; fi",
      "pveam update",
      "pveam download ${self.triggers.storage} ${self.triggers.template}",
    ]
  }
}
