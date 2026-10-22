# ---------------------------------------------------------------- Proxmox access

variable "pm_api_url" {
  type        = string
  description = "Proxmox API endpoint, for example https://pve.lan:8006/api2/json"

  validation {
    condition     = can(regex("^https://[^/]+/api2/json$", var.pm_api_url))
    error_message = "pm_api_url must look like https://HOST:8006/api2/json."
  }
}

variable "terraform_user" {
  type        = string
  sensitive   = true
  description = "Full API token ID: user@realm!tokenname (from credential.auto.tfvars)."
}

variable "terraform_token" {
  type        = string
  sensitive   = true
  description = "API token secret (from credential.auto.tfvars)."
}

variable "pm_tls_insecure" {
  type        = bool
  default     = false
  description = "Accept the self-signed certificate Proxmox ships with. Prefer installing a real certificate."
}

variable "pve_node" {
  type        = string
  description = "Name of the Proxmox node the container is created on."
}

variable "pve_ssh_host" {
  type        = string
  default     = ""
  description = "Host to SSH to for downloading the CT template. Empty = the host in pm_api_url."
}

variable "pve_ssh_user" {
  type        = string
  default     = "root"
  description = "User that may run pveam on the Proxmox host."
}

variable "ssh_via_pve_host" {
  type        = bool
  default     = false
  description = "Reach the container through the Proxmox host as an SSH jump host. Use it when your workstation cannot route to the container's network (a NAT bridge, no subnet route)."
}

variable "manage_template" {
  type        = bool
  default     = true
  description = "Download the CT template with pveam over SSH. Set false when the template is already on the Proxmox storage."
}

variable "pve_ssh_private_key_path" {
  type        = string
  default     = ""
  description = "Private key for the Proxmox host. Empty = use your ssh-agent."
}

# ---------------------------------------------------------------- Container

variable "ct_hostname" {
  type        = string
  default     = "budget-tracker"
  description = "Container hostname."
}

variable "ct_id" {
  type        = number
  default     = 0
  description = "Container ID (VMID, 100 or higher). 0 = let Proxmox pick the next free one."
}

variable "ct_template" {
  type        = string
  default     = ""
  description = "CT template file name, for example debian-12-standard_12.12-1_amd64.tar.zst. Empty = newest Debian 12 standard template."
}

variable "template_storage" {
  type        = string
  default     = "local"
  description = "Proxmox storage with the 'Container template' content type."
}

variable "ct_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage for the container's root disk."
}

variable "ct_disk_gb" {
  type        = number
  default     = 4
  description = "Root disk size in GB. The app and its SQLite database are tiny; 4 leaves room for logs and backups."
}

variable "ct_cores" {
  type    = number
  default = 1
}

variable "ct_memory_mb" {
  type        = number
  default     = 512
  description = "RAM in MB. Node + SQLite idle around 80 MB."
}

variable "ct_swap_mb" {
  type    = number
  default = 256
}

variable "ct_start_on_boot" {
  type        = bool
  default     = true
  description = "Start the container when the Proxmox host boots."
}

variable "ct_root_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Root password for the Proxmox console. Empty = a random one (see the root_password output). SSH is key-only either way."
}

# ---------------------------------------------------------------- Network

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Bridge the container attaches to."
}

variable "vlan_id" {
  type        = number
  default     = 0
  description = "VLAN tag. 0 = untagged. The bridge must be VLAN-aware for anything else."
}

variable "ip_cidr" {
  type        = string
  description = "Static address with prefix, for example 192.168.1.50/24. Static, because Terraform SSHes in to install the app."

  validation {
    condition     = can(cidrhost(var.ip_cidr, 0)) && can(regex("/", var.ip_cidr))
    error_message = "ip_cidr must look like 192.168.1.50/24."
  }
}

variable "gateway" {
  type        = string
  description = "Default gateway for the container."
}

variable "dns_server" {
  type        = string
  default     = "1.1.1.1"
  description = "DNS server for the container (it needs the internet for packages and the daily exchange rate)."
}

# ---------------------------------------------------------------- Access to the container

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Public key to authorise for root. Leave empty to read ssh_public_key_path."
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa_azure.pub"
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa_azure"
  description = "Private key Terraform (and later the GitHub Actions deploy) uses to log in as root."
}

# ---------------------------------------------------------------- The app

variable "app_repo" {
  type        = string
  default     = "https://github.com/vadehraatharv7-hub/budget-tracker.git"
  description = "Git repository the app is deployed from (public, so no credentials are needed)."
}

variable "app_ref" {
  type        = string
  default     = "main"
  description = "Branch, tag or commit to deploy. Change it and apply again to upgrade."
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "app_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Password for the web UI (APP_PASSWORD). Empty = a random one (see the app_password output). No quotes or backslashes."

  validation {
    condition     = var.app_password == "" || can(regex("^[^\"'\\\\\\n\\r]{12,}$", var.app_password))
    error_message = "app_password must be at least 12 characters and contain no quotes, backslashes or newlines."
  }
}

variable "app_timezone" {
  type        = string
  default     = "Europe/Copenhagen"
  description = "Time zone for 'today', reminders and recurring items."
}

variable "vapid_subject" {
  type        = string
  default     = "mailto:admin@example.com"
  description = "Contact address sent to push services (use a real one, Apple validates it)."
}

variable "trust_proxy" {
  type        = bool
  default     = false
  description = "Set true when a reverse proxy (Caddy, Traefik, Tailscale serve) sits in front, so login throttling sees real client IPs."
}

variable "allowed_hosts" {
  type        = list(string)
  default     = []
  description = "Hostnames the app answers to (DNS-rebinding defence). Empty = any. Include the IP if you browse by IP."
}

# ---------------------------------------------------------------- Tailscale (GitHub Actions deploys over SSH)

variable "tailscale_auth_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOT
    Tailscale auth key for the container (Admin console > Settings > Keys): tagged tag:budget, pre-approved, one-off.
    Empty = Tailscale is not installed. Tailscale is used only so GitHub Actions can deploy over Tailscale SSH;
    the app itself is published with Cloudflare Tunnel. See docs/DEPLOY.md in the budget-tracker repository.
  EOT
}

variable "tailscale_serve" {
  type        = bool
  default     = false
  description = "Also publish the app inside your tailnet over HTTPS (tailscale serve). Not needed with Cloudflare Tunnel."
}

variable "tailscale_hostname" {
  type        = string
  default     = "budget-tracker"
  description = "Machine name on the tailnet. Becomes https://<name>.<tailnet>.ts.net and the TS_HOST used by the workflow."
}

# ---------------------------------------------------------------- Cloudflare Tunnel (publishes the app)

variable "cloudflare_tunnel_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOT
    Token of a remotely-managed Cloudflare Tunnel (Zero Trust > Networks > Tunnels > your tunnel > Configure).
    Empty = no tunnel. With a token, cloudflared runs in the container, the app listens on 127.0.0.1 only and trusts
    CF-Connecting-IP. Add a public hostname in the dashboard pointing to http://localhost:<app_port>.
  EOT
}

variable "public_hostname" {
  type        = string
  default     = ""
  description = "Public hostname of the tunnel, for example budget.example.com. The app only answers to it (and to loopback)."

  validation {
    condition     = var.public_hostname == "" || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.public_hostname))
    error_message = "public_hostname must be a lower-case hostname such as budget.example.com (no scheme, no path)."
  }
}

# ---------------------------------------------------------------- Cloudflare Access and rate limit (cloudflare.tf)

variable "cloudflare_api_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOT
    Cloudflare API token that manages the login rate limit and, optionally, the Access login wall. Empty = skip both (do it by hand: see docs/DEPLOY.md).
    Create it at dash.cloudflare.com > My Profile > API Tokens > Create Token > Custom token. For the rate limit alone:
      Zone    | Zone                      | Read
      Zone    | Zone WAF                  | Edit
    For the login wall (enable_access_wall = true) also add:
      Account | Access: Apps and Policies | Edit
      Account | Access: Service Tokens    | Edit
    Limit "Zone Resources" to the zone that contains public_hostname (and "Account Resources" to your account for the Access permissions).
  EOT
}

variable "enable_access_wall" {
  type        = bool
  default     = false
  description = "Also create the Cloudflare Access login wall (needs access_emails and the two Access token permissions). Off: only the rate limit is managed."
}

variable "access_emails" {
  type        = list(string)
  default     = []
  description = "Email addresses allowed through the Cloudflare Access login (a one-time PIN is sent to them). Required when the API token is set."
}

variable "cloudflare_zone_name" {
  type        = string
  default     = ""
  description = "The Cloudflare zone (domain) public_hostname belongs to. Empty = public_hostname without its first label (budget.example.com -> example.com)."
}
