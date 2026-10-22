#!/usr/bin/env bash
# Terraform "external" data source: prints {"name": "<newest debian-12-standard template>"} for pveam on the Proxmox host.
# Usage: latest-template.sh HOST USER [PRIVATE_KEY_PATH]   (empty key path = ssh-agent)
set -euo pipefail
host="$1"; user="$2"; key="${3:-}"

opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
[ -n "$key" ] && opts+=(-i "${key/#\~/$HOME}")

name=$(ssh "${opts[@]}" "$user@$host" \
  "pveam update >/dev/null 2>&1 || true; pveam available --section system | awk '/debian-12-standard/ {print \$2}' | sort -V | tail -1") \
  || { echo "could not SSH to $user@$host to list templates" >&2; exit 1; }

[ -n "$name" ] || { echo "no debian-12-standard template found; set ct_template explicitly" >&2; exit 1; }
printf '{"name":"%s"}\n' "$name"
