#!/usr/bin/env bash
# Runs INSIDE the container as root (uploaded and started by Terraform). Idempotent: safe to run again.
# Reads settings from /root/.budget-bootstrap.env.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
source /root/.budget-bootstrap.env

APP_DIR=/opt/budget-tracker
DATA_DIR=/var/lib/budget-tracker
ENV_FILE=/etc/budget-tracker.env

step() { printf '\n==> %s\n' "$*"; }

step "Base packages and time zone"
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl git gnupg sudo tzdata unattended-upgrades
ln -sf "/usr/share/zoneinfo/${APP_TZ}" /etc/localtime
echo "${APP_TZ}" > /etc/timezone
# Security updates install themselves.
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades

step "Node.js 24 (NodeSource apt repository, signed)"
if ! command -v node >/dev/null || ! node -e 'process.exit(parseInt(process.versions.node) >= 24 ? 0 : 1)'; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install -y -qq nodejs
fi
node --version

step "Service user and directories"
id budget >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin budget
install -d -o budget -g budget -m 0755 "$APP_DIR"
install -d -o budget -g budget -m 0700 "$DATA_DIR"

step "Deploy user (for CI): may only run budget-update"
id deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
passwd -l deploy >/dev/null # no password login; reached only through Tailscale SSH
echo 'deploy ALL=(root) NOPASSWD: /usr/local/bin/budget-update' > /etc/sudoers.d/budget-deploy
chmod 440 /etc/sudoers.d/budget-deploy
visudo -cf /etc/sudoers.d/budget-deploy >/dev/null

step "Configuration (${ENV_FILE}, root-only)"
umask 077
{
  echo "PORT=${APP_PORT}"
  echo "DB_PATH=${DATA_DIR}/budget.db"
  echo "TZ=${APP_TZ}"
  echo "NODE_ENV=production"
  echo "APP_PASSWORD=\"${APP_PASSWORD}\""
  echo "VAPID_SUBJECT=\"${VAPID_SUBJECT}\""
  echo "HOST=${APP_HOST}"
  if [ -n "${TRUST_PROXY}" ]; then echo "TRUST_PROXY=${TRUST_PROXY}"; fi
  if [ -n "${ALLOWED_HOSTS}" ]; then echo "ALLOWED_HOSTS=\"${ALLOWED_HOSTS}\""; fi
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
umask 022
echo "APP_REPO=\"${APP_REPO}\"" > /etc/budget-tracker.deploy
chmod 644 /etc/budget-tracker.deploy

step "Update script (/usr/local/bin/budget-update)"
cat > /usr/local/bin/budget-update <<'UPDATE'
#!/usr/bin/env bash
# Deploy a branch, tag or commit and restart; roll back automatically if the app does not come up healthy.
#   budget-update [ref]        (default: main)
set -euo pipefail
ref="${1:-main}"
# Callable via sudo by the CI user, so never trust the argument.
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 2; }
[[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || { echo "invalid ref" >&2; exit 2; }
# shellcheck disable=SC1091
source /etc/budget-tracker.deploy
port=$(sed -n 's/^PORT=//p' /etc/budget-tracker.env)
app=/opt/budget-tracker
as_app() { runuser -u budget -- "$@"; }

[ -d "$app/.git" ] || { as_app git -C "$app" init -q; as_app git -C "$app" remote add origin "$APP_REPO"; }
as_app git -C "$app" remote set-url origin "$APP_REPO"
prev=$(as_app git -C "$app" rev-parse HEAD 2>/dev/null || true)

as_app git -C "$app" fetch --depth 1 origin "$ref"
as_app git -C "$app" reset --hard FETCH_HEAD

# Build the web app into dist.next, then swap it in, so visitors never see a half-built site.
build() {
  (cd "$app" && as_app npm ci --no-audit --no-fund && as_app env BUILD_OUT=../dist.next npm run build && as_app npm prune --omit=dev --no-audit --no-fund)
  as_app rm -rf "$app/dist.old"
  if [ -d "$app/dist" ]; then as_app mv "$app/dist" "$app/dist.old"; fi
  as_app mv "$app/dist.next" "$app/dist"
}
build

systemctl restart budget-tracker
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${port}/api/session" >/dev/null 2>&1; then
    echo "budget-tracker is up at $(as_app git -C "$app" rev-parse --short HEAD)"
    exit 0
  fi
  sleep 1
done

echo "health check failed" >&2
if [ -n "$prev" ]; then
  echo "rolling back to ${prev}" >&2
  as_app git -C "$app" reset --hard "$prev"
  if [ -d "$app/dist.old" ]; then as_app rm -rf "$app/dist"; as_app mv "$app/dist.old" "$app/dist"; fi
  (cd "$app" && as_app npm ci --omit=dev --no-audit --no-fund)
  systemctl restart budget-tracker
fi
exit 1
UPDATE
chmod 755 /usr/local/bin/budget-update

step "systemd service"
cat > /etc/systemd/system/budget-tracker.service <<'UNIT'
[Unit]
Description=Budget Tracker
After=network-online.target
Wants=network-online.target

[Service]
User=budget
Group=budget
WorkingDirectory=/opt/budget-tracker
EnvironmentFile=/etc/budget-tracker.env
ExecStart=/usr/bin/node server/index.js
Restart=on-failure
RestartSec=3
MemoryMax=400M
# Sandboxing (needs nesting=1 on the container, which Terraform sets)
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/budget-tracker
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable budget-tracker >/dev/null

step "Deploy ${APP_REF}"
/usr/local/bin/budget-update "${APP_REF}"

if [ -n "${TS_AUTHKEY}" ]; then
  step "Tailscale (userspace networking: no TUN device needed in an unprivileged container)"
  if ! command -v tailscale >/dev/null; then
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -qq
    apt-get install -y -qq tailscale
  fi
  sed -i '/^FLAGS=/d' /etc/default/tailscaled
  echo 'FLAGS="--tun=userspace-networking"' >> /etc/default/tailscaled
  systemctl enable --now tailscaled >/dev/null
  systemctl restart tailscaled
  sleep 2
  if ! tailscale status >/dev/null 2>&1; then
    tailscale up --auth-key="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME}" --ssh --advertise-tags=tag:budget --accept-dns=false
  fi
  # Optional: also publish the app inside the tailnet (needs HTTPS certificates enabled in the admin console).
  if [ -n "${TS_SERVE}" ]; then
    tailscale serve --bg --https=443 "http://127.0.0.1:${APP_PORT}" \
      || echo "WARNING: tailscale serve failed. Enable MagicDNS + HTTPS certificates in the Tailscale admin console."
  fi
  tailscale status | head -3 || true
fi

if [ -n "${CF_TUNNEL_TOKEN}" ]; then
  step "Cloudflare Tunnel (cloudflared, signed apt repository)"
  if ! command -v cloudflared >/dev/null; then
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
    apt-get update -qq
    apt-get install -y -qq cloudflared
  fi
  id cloudflared >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared
  # The token lives in a root-only file (unlike `cloudflared service install`, which writes it into a world-readable unit).
  ( umask 077; printf 'TUNNEL_TOKEN=%s\n' "${CF_TUNNEL_TOKEN}" > /etc/cloudflared.env )
  chmod 600 /etc/cloudflared.env
  cat > /etc/systemd/system/cloudflared.service <<'CFUNIT'
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=cloudflared
EnvironmentFile=/etc/cloudflared.env
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
CFUNIT
  systemctl daemon-reload
  systemctl enable cloudflared >/dev/null
  systemctl restart cloudflared
  sleep 3
  systemctl --no-pager --lines=3 status cloudflared || echo "WARNING: cloudflared is not running yet; check: journalctl -u cloudflared"
fi

# Secrets now live only in /etc/budget-tracker.env.
shred -u /root/.budget-bootstrap.env 2>/dev/null || rm -f /root/.budget-bootstrap.env
if [ "${APP_HOST}" = "127.0.0.1" ]; then step "Done: app listens on 127.0.0.1:${APP_PORT} (published through the Cloudflare Tunnel)"; else step "Done: http://$(hostname -I | awk '{print $1}'):${APP_PORT}"; fi
