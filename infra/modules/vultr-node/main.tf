# A Vultr instance with a fixed IPv4 and a firewall that opens only the given ports (and ICMP), on
# IPv4 and IPv6.
terraform {
  required_providers {
    vultr = {
      source = "vultr/vultr"
    }
  }
}

variable "name" {
  type = string
}

variable "region" {
  type        = string
  description = "Vultr region id (cdg: Paris, nrt: Tokyo)."
}

variable "plan" {
  type    = string
  default = "vhp-1c-1gb-amd"
}

# Only the installer's starting point: nixos-anywhere replaces it.
variable "os" {
  type    = string
  default = "Debian 13 x64 (trixie)"
}

# Boots the instance on this ISO while set (attached in place, the disk untouched); back to null
# detaches it and the instance boots its disk again.
variable "iso_url" {
  type    = string
  default = null
}

variable "tcp_ports" {
  type        = list(string)
  default     = []
  description = "Ports or ranges (\"8000:8010\") open to the world."
}

variable "udp_ports" {
  type    = list(string)
  default = []
}

data "vultr_os" "this" {
  filter {
    name   = "name"
    values = [var.os]
  }
}

resource "vultr_firewall_group" "this" {
  description = var.name
}

locals {
  rules = {
    for r in concat(
      setproduct(["tcp"], var.tcp_ports, ["v4", "v6"]),
      setproduct(["udp"], var.udp_ports, ["v4", "v6"]),
    ) : join("-", r) => r
  }
}

resource "vultr_firewall_rule" "this" {
  for_each = local.rules

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = each.value[0]
  port              = each.value[1]
  ip_type           = each.value[2]
  subnet            = each.value[2] == "v4" ? "0.0.0.0" : "::"
  subnet_size       = 0
}

# Ping, and the errors path MTU discovery depends on (ICMPv6 Packet Too Big, IPv4 Fragmentation
# Needed): dropping them blackholes large packets on some paths.
resource "vultr_firewall_rule" "icmp" {
  for_each = { v4 = "0.0.0.0", v6 = "::" }

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "icmp"
  ip_type           = each.key
  subnet            = each.value
  subnet_size       = 0
}

resource "vultr_iso_private" "this" {
  count = var.iso_url == null ? 0 : 1
  url   = var.iso_url
}

# Survives a rebuild of the instance, so DNS does not move.
resource "vultr_reserved_ip" "v4" {
  label   = var.name
  region  = var.region
  ip_type = "v4"
}

resource "vultr_instance" "this" {
  label    = var.name
  hostname = var.name
  region   = var.region
  plan     = var.plan
  os_id    = data.vultr_os.this.id
  # The provider refuses os_id and iso_id together on create: only set it on an existing instance.
  iso_id            = one(vultr_iso_private.this[*].id)
  enable_ipv6       = true
  reserved_ip_id    = vultr_reserved_ip.v4.id
  firewall_group_id = vultr_firewall_group.this.id
  backups           = "disabled"
  activation_email  = false

  lifecycle {
    # Once NixOS is installed, a new Debian image id upstream must not rebuild the machine.
    ignore_changes = [os_id]
  }
}

output "name" {
  value = var.name
}

output "ipv4" {
  value = vultr_reserved_ip.v4.subnet
}

# shortcut: the instance's own IPv6 changes if it is recreated (re-apply dns then); reserve a v6 if that starts to hurt.
output "ipv6" {
  value = vultr_instance.this.v6_main_ip
}
