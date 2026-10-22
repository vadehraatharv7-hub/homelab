locals {
  pve_host = var.pve_ssh_host != "" ? var.pve_ssh_host : regex("^https://([^:/]+)", var.pm_api_url)[0]

  ssh_public_key = trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path)))

  ct_ip = split("/", var.ip_cidr)[0]

  ct_template  = var.ct_template != "" ? var.ct_template : data.external.template[0].result.name
  ostemplate   = "${var.template_storage}:vztmpl/${local.ct_template}"
  app_password = var.app_password != "" ? var.app_password : random_password.app[0].result
  root_pw      = var.ct_root_password != "" ? var.ct_root_password : random_password.root[0].result

  tunnel = nonsensitive(var.cloudflare_tunnel_token != "") # only whether it is set, never the token
  # "cloudflare": trust CF-Connecting-IP (tunnel). "1": trust X-Forwarded-For (tailscale serve or another proxy).
  trust_proxy_mode = local.tunnel ? "cloudflare" : (var.trust_proxy || (var.tailscale_auth_key != "" && var.tailscale_serve)) ? "1" : ""
  allowed_hosts    = distinct(compact(concat(var.allowed_hosts, [var.public_hostname])))

  # Written to /root/.budget-bootstrap.env inside the container (mode 600) and read by bootstrap.sh.
  bootstrap_env = templatefile("${path.module}/templates/bootstrap.env.tftpl", {
    app_repo      = var.app_repo
    app_ref       = var.app_ref
    app_port      = var.app_port
    app_password  = local.app_password
    timezone      = var.app_timezone
    vapid_subject = var.vapid_subject
    trust_proxy   = local.trust_proxy_mode
    ts_authkey    = var.tailscale_auth_key
    ts_hostname   = var.tailscale_hostname
    ts_serve      = var.tailscale_serve
    allowed_hosts = join(",", local.allowed_hosts)
    cf_token      = var.cloudflare_tunnel_token
    listen_host   = local.tunnel ? "127.0.0.1" : "0.0.0.0"
  })
}

resource "random_password" "app" {
  count   = var.app_password == "" ? 1 : 0
  length  = 24
  special = false # letters and digits only: safe in a systemd EnvironmentFile
}

resource "random_password" "root" {
  count   = var.ct_root_password == "" ? 1 : 0
  length  = 24
  special = false
}
