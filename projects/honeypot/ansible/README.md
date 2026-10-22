# Ansible - install and configure everything

Run after (or through) `../deploy.sh`. The inventory is written by Terraform to `../terraform/inventory.ini`;
`ansible.cfg` already points at it.

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml
```

`site.yml` does everything, in order:

| Step | What happens |
|---|---|
| `proxmox-installs.yml` | Types the one confirmation each Ubuntu installer needs (`qm sendkey` on the Proxmox host), then waits until every VM has installed itself and answers on SSH. VMs that already answer are skipped. |
| `common` (all VMs) | Updates (reboots if needed), time zone and NTP, hardened `sshd`, fail2ban on port 22222, unattended security updates, kernel hardening |
| `mongodb` (database) | MongoDB 8.0 from the official repository, held at the installed version, bound to the private address, authentication on, an administrator and the application account, daily backup, log rotation |
| `monitoring` | Go and Node, the SecDash backend and frontend, PM2, nginx with HTTPS, admin login and tokens (stored on this machine in `~/.secdash_*`) |
| `vector`, `honeypot`, `xpd_shield` (honeypot) | Cowrie (SSH 22 / Telnet 23 decoys), log shipping, the XDP ban filter |
| `vector`, `snare`, `xpd_shield` (snare) | Snare + Tanner behind a TLS proxy, log forwarder, the XDP ban filter |
| `verify.yml` | Checks that every service runs **and** that the zones are isolated (see below) |

Run parts of it:

```bash
ansible-playbook proxmox-installs.yml          # only the installs
ansible-playbook site.yml --tags verify        # only the checks
ansible-playbook site.yml --limit database     # one machine
```

Everything is idempotent: a second run changes nothing that is already right.

## The isolation tests

`verify.yml` does not just look at services. From inside each honeypot it tries to open connections that must fail:
the database (27017), the dashboard's SSH (22222) and web UI (443). From the dashboard it tries the honeypot's admin SSH.
If any of them connects, the run stops and tells you to check the Proxmox firewall. This is how you find out that the
datacenter firewall is still off or a firewall file was not written.

## Requirements on this machine

Ansible 2.15+, the collections in `requirements.yml`, Go (the backend and xdp-shield are compiled here), and SSH access
to the VMs with the key named in the inventory. The xdp-shield sources are expected at
`../../Multi_ML_HoneyPot/xdp-shield` (`xdp_shield_src` in `group_vars/all.yml`).

## Secrets

`~/.secdash_admin_password` (dashboard `admin` login), `~/.secdash_token` (API token) and `~/.secdash_ingest_key`
(shared secret the sensors send) are created on first run, mode 0600, and reused afterwards. The database passwords come from
the inventory. Keep the inventory out of git.

## Not covered

* The router: VLAN interfaces, inter-zone rules and the port forwards for 22, 23, 80 and 443.
* The Proxmox host: a VLAN-aware bridge, the API token, and the datacenter firewall switch.
* Backups leave the database VM only if you copy `/var/backups/mongodb` somewhere; the dump sits on the same disk.
* Traffic to MongoDB is not encrypted. It crosses only the core VLAN and the Proxmox firewall limits it to the dashboard.
