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

module "torii" {
  source = "../../modules/vultr-node"

  # Named after Vultr's region (IATA airport codes: cdg Paris, nrt Tokyo).
  name   = "torii-${var.region}"
  region = var.region
  # SSH only, to install and reach the machine; each service opens its ports when it lands.
  tcp_ports = ["22"]
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
