# Budget Tracker LXC (Proxmox)

Terraform for a small unprivileged Debian 12 LXC that runs the
[budget-tracker](https://github.com/vadehraatharv7-hub/budget-tracker) app under systemd.
Separate stack and separate state from `../honeypot`; it shares the Proxmox API token in `../../shared/proxmox/`
(through a symlink) and uses the same `telmate/proxmox` provider pin.

```
terraform apply
 ├─ template.tf  pveam downloads the newest Debian 12 CT template on the Proxmox host (over SSH)
 ├─ lxc.tf       unprivileged CT, 1 core / 512 MB / 4 GB, static IP, key-only root SSH, nesting on
 └─ app.tf       over SSH: Node 24 (signed apt repo), user `budget`, app from GitHub, systemd service
```

## Before the first apply

1. **API token** – `shared/proxmox/credential.auto.tfvars` already has one; this folder symlinks it (`credential.auto.tfvars`).
   It needs the usual container rights: `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `Datastore.AllocateSpace`,
   `Datastore.Audit`, `Sys.Audit` (and `SDN.Use` on Proxmox 8 for the bridge).
2. **SSH to the Proxmox host** (`root` by default, ssh-agent or `pve_ssh_private_key_path`) – used for `pveam`.
3. **Storage** – `template_storage` must allow the *Container template* content type
   (Datacenter → Storage → local → Content).
4. **Network** – pick a free static `ip_cidr`. The machine running Terraform must be able to reach it (same LAN/VLAN),
   because the app is installed over SSH.

```bash
cp terraform.tfvars.example terraform.tfvars   # edit: pve_node, ip_cidr, gateway, ...
terraform init
terraform plan
terraform apply
terraform output -raw app_password             # web UI password (random unless you set app_password)
terraform output url                           # https://<public_hostname> when the tunnel is set
```

## Day 2

| Task | How |
|---|---|
| Deploy new code | Push to `main`: GitHub Actions runs CI, then `budget-update <sha>` over Tailscale SSH (the app is served by the Cloudflare Tunnel). By hand: `ssh root@<ip> budget-update [ref]` (output `update_command`). It pulls, runs `npm ci`, restarts, health-checks and **rolls back** if unhealthy. |
| Pin a version | set `app_ref` to a tag or commit and `terraform apply` |
| Logs / status | `ssh root@<ip> journalctl -u budget-tracker -f` (app) · `journalctl -u cloudflared -n 50` (tunnel) |
| Back up | Proxmox backup job (vzdump) on the CT covers everything; DB is `/var/lib/budget-tracker/budget.db` |
| Rotate UI password | change `app_password`, apply (restarts the service, signs everyone out) |

## Notes

- **Publishing**: set `cloudflare_tunnel_token` and `public_hostname`. `cloudflared` runs in the container (outbound only,
  no router ports), the app listens on `127.0.0.1`, trusts `CF-Connecting-IP` and only answers to your hostname. Cloudflare
  provides the HTTPS that install, push and app lock need. Without a token the app listens on the LAN at `http://<ip>:3000`.
  Create the tunnel and add a public hostname -> `http://localhost:3000` in the Zero Trust dashboard first, and consider
  Cloudflare Access in front: `Budget Tracker/docs/DEPLOY.md`.
- **CI deploys**: Tailscale is used only for this. The container has a `deploy` user that can run only
  `sudo budget-update` (no password, no authorized keys: reachable only through Tailscale SSH, which the tailnet ACL
  restricts to the `tag:ci` runner). Set `tailscale_auth_key`; `tailscale_serve = true` additionally publishes the app
  inside your tailnet.
- **Secrets**: the UI password is in Terraform state (and in `/etc/budget-tracker.env`, mode 600, inside the CT). Keep
  `terraform.tfstate` private; it is git-ignored.
- The container is `unprivileged` with `nesting` (needed for systemd's sandboxing). The template is only used at creation,
  so a newer template never rebuilds the container.
- `terraform destroy` removes the container **and its data**; take a backup first.
