# torii, the lab's public gate: kekkai's lighthouse and relay, public DNS and web.
terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.33.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}

# Ephemeral: the API key is decrypted for the run only, never written to the state or the plan.
ephemeral "sops_file" "secrets" {
  source_file = "${path.module}/../../../secrets/infra/tofu.yaml"
}

provider "vultr" {
  api_key = ephemeral.sops_file.secrets.data["vultr_api_key"]
}

variable "region" {
  type    = string
  default = "cdg"
}

# Only for installing NixOS (modules/nixos/vultr-guest.nix): `tofu apply -var iso_url=<NixOS minimal ISO>`,
# then remove it in Vultr's console and a plain `tofu apply` deletes it (see vultr-guest.nix, step 5). Last used (2026-10-18):
# https://releases.nixos.org/nixos/26.05/nixos-26.05.11985.26f4107e47e3/nixos-minimal-26.05.11985.26f4107e47e3-x86_64-linux.iso
variable "iso_url" {
  type    = string
  default = null
}

module "torii" {
  source = "../../modules/vultr-node"

  # Named after Vultr's region (IATA airport codes: cdg Paris, nrt Tokyo).
  name    = "torii-${var.region}"
  region  = var.region
  iso_url = var.iso_url
  # 22: SSH, to install and reach the machine. Each service opens its ports when it lands
  # (docs/migration.md); 53: annai soto, the public nameservers (modules/network/annai-soto.nix).
  tcp_ports = ["22", "53"]
  udp_ports = ["53"]
}

output "name" {
  value = module.torii.name
}

output "ipv4" {
  value = module.torii.ipv4
}

output "ipv6" {
  value = module.torii.ipv6
}
