# Limits sign-in attempts and, when enable_access_wall is true, puts a login wall (Cloudflare Access) in front of the site.
# Everything here is skipped unless cloudflare_api_token and public_hostname are set, so the rest of the stack works without it.
#
#   visitor ──▶ Cloudflare ──▶ Access: sign in with a one-time PIN sent to access_emails ──▶ tunnel ──▶ app
#   iOS Shortcuts ──▶ /api/shortcuts/* ──▶ Access: service token headers (no interactive login) ──▶ app (and its own API token)

locals {
  cf_enabled   = nonsensitive(var.cloudflare_api_token != "") && var.public_hostname != ""
  host_labels  = split(".", var.public_hostname)
  cf_zone_name = var.cloudflare_zone_name != "" ? var.cloudflare_zone_name : join(".", slice(local.host_labels, 1, length(local.host_labels)))
  access_on    = local.cf_enabled && var.enable_access_wall
}

check "access_has_an_owner" {
  assert {
    condition     = !local.access_on || length(var.access_emails) > 0
    error_message = "enable_access_wall is true, so access_emails must list who may sign in (otherwise nobody could reach the site)."
  }
}

data "cloudflare_zone" "this" {
  count  = local.cf_enabled ? 1 : 0
  filter = { name = local.cf_zone_name }
}

locals {
  cf_account_id = local.access_on ? data.cloudflare_zone.this[0].account.id : ""
  cf_zone_id    = local.cf_enabled ? data.cloudflare_zone.this[0].zone_id : ""
}

# ---- who may sign in -------------------------------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_policy" "owner" {
  count            = local.access_on ? 1 : 0
  account_id       = local.cf_account_id
  name             = "Budget: owner sign-in"
  decision         = "allow"
  session_duration = "720h" # a month: when the session ends the installed app cannot reach the server until you sign in again
  include          = [for e in var.access_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "site" {
  count                = local.access_on ? 1 : 0
  account_id           = local.cf_account_id
  name                 = "Budget"
  type                 = "self_hosted"
  domain               = var.public_hostname
  session_duration     = "720h"
  app_launcher_visible = false
  policies             = [{ id = cloudflare_zero_trust_access_policy.owner[0].id, precedence = 1 }]
}

# ---- iOS Shortcuts cannot do an interactive login, so /api/shortcuts/* accepts a service token instead ------------------
resource "cloudflare_zero_trust_access_service_token" "shortcuts" {
  count      = local.access_on ? 1 : 0
  account_id = local.cf_account_id
  name       = "Budget: iOS Shortcuts"
  duration   = "8760h" # one year; re-apply with -replace to rotate
}

resource "cloudflare_zero_trust_access_policy" "shortcuts" {
  count      = local.access_on ? 1 : 0
  account_id = local.cf_account_id
  name       = "Budget: Shortcuts service token"
  decision   = "non_identity"
  include    = [{ service_token = { token_id = cloudflare_zero_trust_access_service_token.shortcuts[0].id } }]
}

# More specific path, so it wins over the whole-site application above.
resource "cloudflare_zero_trust_access_application" "shortcuts" {
  count            = local.access_on ? 1 : 0
  account_id       = local.cf_account_id
  name             = "Budget: Shortcuts API"
  type             = "self_hosted"
  domain           = "${var.public_hostname}/api/shortcuts"
  session_duration = "24h"
  policies         = [{ id = cloudflare_zero_trust_access_policy.shortcuts[0].id, precedence = 1 }]
}

# ---- brute-force protection for the password form (free plan: one rule, 10 s window) ---------------------------------------
resource "cloudflare_ruleset" "login_rate_limit" {
  count   = local.cf_enabled ? 1 : 0
  zone_id = local.cf_zone_id
  name    = "Budget: limit sign-in attempts"
  kind    = "zone"
  phase   = "http_ratelimit"
  rules = [{
    action      = "block"
    description = "At most 5 password attempts per 10 seconds per visitor"
    enabled     = true
    expression  = "(http.host eq \"${var.public_hostname}\" and http.request.uri.path eq \"/api/login\" and http.request.method eq \"POST\")"
    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      requests_per_period = 5
      mitigation_timeout  = 10
    }
  }]
}
