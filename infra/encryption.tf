# Shared by every stack (symlinked as stacks/*/encryption.tf): the state and plans are encrypted
# before they touch the disk, so terraform.tfstate can be committed. The passphrase comes from sops
# through `tofu-state-key` (infra devShell, modules/flake/infra.nix): run tofu from `nix develop .#infra`.
terraform {
  encryption {
    key_provider "external" "sops" {
      command = ["tofu-state-key"]
    }

    key_provider "pbkdf2" "state" {
      chain = key_provider.external.sops
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }

    # One passphrase for every stack: dns reads torii's state.
    remote_state_data_sources {
      default {
        method = method.aes_gcm.state
      }
    }
  }
}
