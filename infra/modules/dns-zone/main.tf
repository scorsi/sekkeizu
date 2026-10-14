# The records of one Porkbun zone. A zone without mail says so: SPF -all and DMARC reject (nobody
# sends in its name), null MX (RFC 7505: senders give up at once instead of falling back to the A
# record and retrying for days).
terraform {
  required_providers {
    porkbun = {
      source = "jianyuan/porkbun"
    }
  }
}

variable "domain" {
  type = string
}

variable "records" {
  type = list(object({
    name     = optional(string, "")
    type     = string
    content  = string
    priority = optional(number)
  }))
  default     = []
  description = "Records of the zone; name is the subdomain, empty for the apex."
}

variable "null_mail" {
  type        = bool
  default     = false
  description = "The zone neither sends nor receives mail."
}

locals {
  records = concat(
    var.null_mail ? [
      { name = "", type = "MX", content = ".", priority = 0 },
      { name = "", type = "TXT", content = "v=spf1 -all" },
      { name = "_dmarc", type = "TXT", content = "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s" },
    ] : [],
    var.records,
  )
}

resource "porkbun_dns_record" "this" {
  for_each = { for r in local.records : "${r.name}/${r.type}/${r.content}" => r }

  domain    = var.domain
  subdomain = each.value.name == "" ? null : each.value.name
  type      = each.value.type
  content   = each.value.content
  priority  = try(each.value.priority, null) # the built-in records above set it on MX only
}
