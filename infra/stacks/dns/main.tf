# Public zones at Porkbun. scorsi.dev carries the infrastructure, scorsi.me the identity (résumé,
# mail later). uchi.scorsi.dev has no record here, on purpose: that internal zone is served by annai
# over kekkai and is never delegated publicly.
terraform {
  required_providers {
    porkbun = {
      source  = "jianyuan/porkbun"
      version = "0.3.3"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}

ephemeral "sops_file" "secrets" {
  source_file = "${path.module}/../../../secrets/infra/tofu.yaml"
}

provider "porkbun" {
  api_key    = ephemeral.sops_file.secrets.data["porkbun_api_key"]
  secret_key = ephemeral.sops_file.secrets.data["porkbun_secret_key"]
}

# Apply torii first: its addresses come from its state.
data "terraform_remote_state" "torii" {
  backend = "local"
  config = {
    path = "${path.module}/../torii/terraform.tfstate"
  }
}

locals {
  torii = data.terraform_remote_state.torii.outputs

  zones = {
    "scorsi.dev" = {
      null_mail = true
      records = [
        { name = local.torii.name, type = "A", content = local.torii.ipv4 },
        { name = local.torii.name, type = "AAAA", content = local.torii.ipv6 },
      ]
    }
    "scorsi.me" = {
      null_mail = false
      records   = []
    }
  }
}

module "zone" {
  source   = "../../modules/dns-zone"
  for_each = local.zones

  domain    = each.key
  null_mail = each.value.null_mail
  records   = each.value.records
}

# Delegation: torii-cdg is the authoritative server for both zones. The glue exists because
# ns1/ns2 live inside the zone they serve, so the registry needs their addresses.
# torii's remote state is readable here thanks to the shared remote_state_data_sources block.
resource "porkbun_glue_record" "ns" {
  for_each = toset(["ns1", "ns2"])

  domain    = "scorsi.dev"
  subdomain = each.key
  ips       = [local.torii.ipv4, local.torii.ipv6]
}

# The glue was created by hand in Porkbun's UI before being managed here.
import {
  for_each = toset(["ns1", "ns2"])
  to       = porkbun_glue_record.ns[each.key]
  id       = "scorsi.dev_${each.key}"
}

# This resource has no import support, so the first apply shows two creates that re-send the
# nameservers already live (no effect). Destroy only warns and leaves them unchanged.
# Rollback: set nameservers to Porkbun's own, curitiba, fortaleza, maceio and salvador
# (each <name>.ns.porkbun.com), and apply.
resource "porkbun_domain_nameservers" "zone" {
  for_each = toset(["scorsi.dev", "scorsi.me"])

  domain      = each.key
  nameservers = [for ns in sort(keys(porkbun_glue_record.ns)) : "${ns}.scorsi.dev"]

  # Glue must exist before the registry is told to use these hosts.
  depends_on = [porkbun_glue_record.ns]
}
