# Off-site backups: a Hetzner Storage Box, restic over SFTP. jiban pushes everything (ishizue's
# backups are pulled to it first) through the `backup` subaccount, confined to its directory; a
# second host pushing directly would get a subaccount of its own.
# The box's weekly snapshots are read-only over SFTP (.zfs/) and managed through the API, whose
# token never leaves secrets/infra/: a compromised host can delete files, not the last ten weeks.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.70.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
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

provider "hcloud" {
  token = ephemeral.sops_file.secrets.data["hcloud_token"]
}

# Password login cannot be disabled on a Storage Box: long random ones, kept in the encrypted state.
# Character set taken from the provider's own tests (no published policy found).
resource "random_password" "this" {
  for_each = toset(["box", "backup"])

  length           = 40
  override_special = "-."
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "hcloud_storage_box" "backups" {
  name             = "backups"
  storage_box_type = "bx11"
  location         = "fsn1"
  password         = random_password.this["box"].result

  access_settings = {
    ssh_enabled          = true
    reachable_externally = true
    zfs_enabled          = true # .zfs/: restore single files from a snapshot
    samba_enabled        = false
    webdav_enabled       = false
  }

  # Sundays 03:00 UTC (0 is Sunday in the provider, unlike the API): ten weeks of history.
  snapshot_plan = {
    max_snapshots = 10
    hour          = 3
    minute        = 0
    day_of_week   = 0
  }

  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

# Its SSH key goes into backup/.ssh/authorized_keys on the box by hand: managing keys on the box
# resource itself would recreate it, data included.
resource "hcloud_storage_box_subaccount" "backup" {
  storage_box_id = hcloud_storage_box.backups.id
  name           = "backup"
  home_directory = "backup"
  password       = random_password.this["backup"].result

  access_settings = {
    ssh_enabled          = true
    reachable_externally = true
  }
}

variable "backup_key" {
  type        = string
  description = "jiban's backup-pull public key; exported by the infra shell from modules-private."
}

variable "backup_host_key" {
  type        = string
  description = "The box's SSH host key (`<type> <base64>`); exported by the infra shell from modules-private."
}

# The API has no SSH keys for a subaccount: the box's own `install-ssh-key` command adds it to
# .ssh/authorized_keys, logged in with the subaccount's password. The host key is pinned, so the
# password goes to the box only. Runs again when the key or the subaccount changes.
resource "terraform_data" "backup_key" {
  triggers_replace = [var.backup_key, hcloud_storage_box_subaccount.backup.id]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      known=$(mktemp)
      trap 'rm -f "$known"' EXIT
      printf '[%s]:23 %s\n' "$HOST" "$HOST_KEY" > "$known"
      printf '%s\n' "$KEY" | sshpass -e ssh -F none -p 23 \
        -o UserKnownHostsFile="$known" -o StrictHostKeyChecking=yes \
        -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
        "$LOGIN@$HOST" install-ssh-key
    EOT

    environment = {
      HOST     = hcloud_storage_box_subaccount.backup.server
      LOGIN    = hcloud_storage_box_subaccount.backup.username
      HOST_KEY = var.backup_host_key
      KEY      = var.backup_key
      SSHPASS  = random_password.this["backup"].result
    }
  }
}

output "backup_server" {
  value = hcloud_storage_box_subaccount.backup.server
}

output "backup_username" {
  value = hcloud_storage_box_subaccount.backup.username
}

output "backup_password" {
  value     = random_password.this["backup"].result
  sensitive = true
}
