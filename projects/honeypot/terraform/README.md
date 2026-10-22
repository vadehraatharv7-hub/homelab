# Honeypot platform on Proxmox (Homelab)

The same platform as `Multi_ML_HoneyPot/honeypot-infra` (Azure), built on your Proxmox host with the
`telmate/proxmox` provider: two honeypots, the SecDash dashboard and a MongoDB database, in two isolated zones.

```
Internet --(router port forwards)--> DMZ  VLAN 66 10.66.0.0/24      CORE VLAN 67 10.67.0.0/24
                                      vm-honeypot  .10  Cowrie     vm-monitoring .10  SecDash
 22,23 ------------------------------>  (SSH/Telnet decoy)  --8081-->   (dashboard, ban list)
 80,443 -----------------------------> vm-snare     .11  Snare            |
                                       (web decoy)  --8081--^             +--27017--> vm-database .11  MongoDB
```

**Security model: the honeypots will be compromised; the dashboard and database must not be.**

* Two VLANs, one per zone, so the zones are separate networks.
* Every VM has a **Proxmox firewall** on its virtual NIC (policy drop in and out, enforced by the hypervisor, so a root
  shell inside a compromised honeypot cannot remove it). `macfilter` and `ipfilter` stop MAC/IP/ARP spoofing.
* Honeypots may only talk to the dashboard on `8081`, DNS, NTP and the **public** internet on 80/443. They cannot reach the
  database, your LAN or any private network. Only the dashboard may reach the database (`27017`).
* SSH moved to port `22222`, key-only, and only from `admin_cidr`. The decoys own port 22.

## What Terraform creates

| File | Does |
|---|---|
| `iso.tf` | Downloads the Ubuntu 22.04 server ISO onto Proxmox, verified by SHA-256 |
| `seed.tf` | Builds one unattended-install seed ISO per VM (user, SSH key, static IP, port 22222, packages) |
| `vms.tf` | Four VMs on the zone VLANs, installer ISO + seed attached, firewall on |
| `firewall.tf` | Writes `/etc/pve/firewall/<vmid>.fw` for each VM over SSH (the provider has no firewall resource) |
| `inventory.tf` | Writes `inventory.ini` for the existing Ansible roles (database password included) |

VM IDs are `9101`-`9104` (`vmid_base`). Host names match Azure (`vm-honeypot`, `vm-snare`, ...) because the dashboard
names sensors after them. The NIC is renamed to `eth0`, which the Ansible roles and xdp-shield expect.

## Before you start

1. **Proxmox**
   * The bridge (`vmbr0`) must be **VLAN aware**: node > Network > edit the bridge.
   * `iso_storage` must allow the **ISO image** content type.
   * API token. The privileges below are enough (run on the Proxmox host):
     ```
     pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
     pveum aclmod / -user terraform@pam -role TerraformProv
     pveum aclmod / -token 'terraform@pam!homelab' -role TerraformProv   # if the token has privilege separation
     ```
   * **Enable the datacenter firewall** (Datacenter > Firewall > Options > Firewall: Yes). Per-VM rules do nothing until
     this is on. Proxmox keeps access to the web UI and SSH open from the host's own network, but check that you can still
     reach it from your workstation first.
   * `root` SSH to the Proxmox host (key or ssh-agent). Only used to write the firewall files; set
     `manage_firewall_rules = false` to skip it and apply equivalent rules yourself.
2. **Router / firewall** (Terraform prints this list as `router_requirements`)
   * An interface on each VLAN with the `.1` address of its subnet.
   * Allow DMZ -> `10.67.0.10` tcp/8081 and nothing else towards the core zone. Block both zones from your LAN.
   * Allow your admin network -> both zones on tcp/22222 and -> the dashboard on tcp/80,443.
   * Port-forward WAN 22 and 23 to `10.66.0.10`, and WAN 80 and 443 to `10.66.0.11`. Forward without NAT on the source
     address, or the honeypots will log your router instead of the attackers.
   * Allow both zones out to the internet.
3. **Credentials**: `credential.auto.tfvars` holds `terraform_user` (the full token ID `user@realm!tokenname`) and
   `terraform_token` (its secret). Both values must be quoted. It is git-ignored.

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in pm_api_url, pve_node, admin_cidr, ...
terraform init
terraform plan
terraform apply
```

### Confirm the installs

`ansible-playbook proxmox-installs.yml` does this for you. By hand:

The VMs boot the Ubuntu installer and find their seed ISO. Ubuntu asks **once per VM** `Continue with autoinstall?`
because the install wipes the disk. Open each VM's console and type `yes`, or once every console shows the prompt run
the command Terraform prints as `confirm_installs_command` on the Proxmox host (it sends the keys with `qm sendkey`).
Everything after that is unattended and takes a few minutes; each VM reboots into the installed system.

Then set `enable_guest_agent = true` in `terraform.tfvars` and apply again (the agent exists only after the install).

### Configure the software

`../ansible` installs and verifies everything: it confirms the installers, hardens the VMs, installs MongoDB, the
dashboard, Cowrie and Snare, and finally proves the zones are isolated. The inventory is written by Terraform and
used automatically.

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml
```

`../deploy.sh` runs everything from this README in order, Terraform included. See `../ansible/README.md`.

## Limits and honest notes

* **Not applied against real hardware.** It passes `terraform validate`, and the generated firewall files, install seed
  and inventory were rendered and inspected, but nothing has been run against a Proxmox host. Run `terraform plan` first.
* The provider cannot create bridges, VLANs or firewall rules, so those come from the VLAN-aware bridge you already
  have, your router, and the files in `firewall.tf`.
* Zone isolation is enforced twice: by the router (if you configure it as above) and by the Proxmox firewall. Keep both.
* `terraform.tfstate` contains the database password and the throw-away OS password. Treat it as a secret.
* Destroying removes the VMs and their firewall files. It does not delete the downloaded ISO's storage entry.
