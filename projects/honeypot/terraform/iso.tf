# Downloads the Ubuntu installer straight onto the Proxmox ISO storage, verified against
# the published checksum. Nothing is downloaded to your workstation.
resource "proxmox_storage_iso" "ubuntu" {
  pve_node           = var.pve_node
  storage            = var.iso_storage
  filename           = var.ubuntu_iso_filename
  url                = var.ubuntu_iso_url
  checksum           = var.ubuntu_iso_sha256
  checksum_algorithm = "sha256"
}
