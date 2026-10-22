output "container_id" {
  value       = proxmox_lxc.budget.vmid
  description = "Proxmox VMID of the container."
}

output "ip" {
  value = local.ct_ip
}

output "url" {
  value = (local.tunnel && var.public_hostname != "") ? "https://${var.public_hostname}" : (
    local.tunnel ? "https://<the public hostname you added to the tunnel>" : "http://${local.ct_ip}:${var.app_port}"
  )
  description = "Where the app is reachable. Via Cloudflare Tunnel it is HTTPS, so install, push and app lock work."
}

output "ssh" {
  value       = "ssh -i ${var.ssh_private_key_path} root@${local.ct_ip}"
  description = "Log in to the container (key only)."
}

output "update_command" {
  value       = "ssh -i ${var.ssh_private_key_path} root@${local.ct_ip} budget-update ${var.app_ref}"
  description = "Deploys the latest code without Terraform. GitHub Actions will run exactly this."
}

output "app_password" {
  value       = local.app_password
  sensitive   = true
  description = "Web UI password. Show with: terraform output -raw app_password"
}

output "root_password" {
  value       = local.root_pw
  sensitive   = true
  description = "Root password for the Proxmox console. Show with: terraform output -raw root_password"
}
