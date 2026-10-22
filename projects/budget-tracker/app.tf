# Installs Node, creates the service user, deploys the app from GitHub and starts it under systemd.
# Re-runs (idempotently) when the ref, the settings or the bootstrap script change.
resource "null_resource" "app" {
  triggers = {
    container = proxmox_lxc.budget.id
    ref       = var.app_ref
    settings  = sha256(local.bootstrap_env)
    script    = filesha256("${path.module}/scripts/bootstrap.sh")
  }

  connection {
    type        = "ssh"
    host        = local.ct_ip
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m" # the container needs a moment to boot and start sshd

    # Optional jump host: the Proxmox host can reach the container's bridge even when this machine cannot.
    bastion_host        = var.ssh_via_pve_host ? local.pve_host : null
    bastion_user        = var.ssh_via_pve_host ? var.pve_ssh_user : null
    bastion_private_key = var.ssh_via_pve_host && var.pve_ssh_private_key_path != "" ? file(pathexpand(var.pve_ssh_private_key_path)) : null
  }

  provisioner "file" {
    content     = local.bootstrap_env
    destination = "/root/.budget-bootstrap.env"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/bootstrap.sh"
    destination = "/root/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /root/.budget-bootstrap.env",
      "bash /root/bootstrap.sh",
    ]
  }
}
