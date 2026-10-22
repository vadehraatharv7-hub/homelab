#!/usr/bin/env bash
# From an empty Proxmox host to a verified honeypot platform, in one command:
#
#   ./deploy.sh                      # everything
#   ./deploy.sh --tags verify        # extra arguments go to ansible-playbook
#
# Needs: terraform, ansible, go (the dashboard backend and xdp-shield are built here), and
# terraform/terraform.tfvars + terraform/credential.auto.tfvars filled in (see README.md).
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "1/4  Terraform: ISO, install seeds, VMs, firewall files, inventory"
(cd terraform && terraform init -input=false && terraform apply ${TF_APPLY_ARGS:-})

step "2/4  Ansible collections"
(cd ansible && ansible-galaxy collection install -r requirements.yml)

step "3/4  Ansible: confirm installs, harden, deploy, verify"
(cd ansible && ansible-playbook site.yml "$@")

# The QEMU guest agent exists only after the install. Telling Proxmox to use it earlier would make
# Terraform wait for an address that cannot appear yet, so it is switched on now.
step "4/4  Terraform: switch on the guest agent"
printf 'enable_guest_agent = true\n' > terraform/guest-agent.auto.tfvars
(cd terraform && terraform apply ${TF_APPLY_ARGS:-})

printf '\n\033[1mDone.\033[0m Remember the router: port-forward 22/23 to the honeypot and 80/443 to snare.\n'
