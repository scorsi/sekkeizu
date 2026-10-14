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
