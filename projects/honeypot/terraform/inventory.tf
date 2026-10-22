resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/${var.inventory_path}"
  file_permission = "0600"
  content = templatefile("${path.module}/inventory.tftpl", {
    honeypot_ip    = local.vms.honeypot.ip
    snare_ip       = local.vms.snare.ip
    monitoring_ip  = local.vms.monitoring.ip
    database_ip    = local.vms.database.ip
    admin_user     = var.admin_username
    private_key    = var.ssh_private_key_path
    mongo_uri      = local.mongo_uri
    mongo_password = random_password.mongo_app.result
    mongo_admin_pw = random_password.mongo_admin.result
    vmids          = { for name, vm in local.vms : name => vm.vmid }
    hostnames      = { for name, vm in local.vms : name => vm.hostname }
    pve_host       = local.pve_host
    pve_user       = var.pve_ssh_user
    pve_key        = var.pve_ssh_private_key_path
    admin_cidr     = var.admin_cidr
  })
}
