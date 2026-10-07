# sops-nix: secrets live encrypted in secrets/<host>/ and are decrypted at activation
# using the host's own SSH key, so no extra key has to be deployed.
{ inputs, ... }:
let
  # Same key that .sops.yaml derives the host's age recipient from.
  hostKey = "/etc/ssh/ssh_host_ed25519_key";
in
{
  flake.modules.darwin.secrets = {
    imports = [ inputs.sops-nix.darwinModules.sops ];
    sops.age.sshKeyPaths = [ hostKey ];
  };

  flake.modules.nixos.secrets = {
    imports = [ inputs.sops-nix.nixosModules.sops ];
    sops.age.sshKeyPaths = [ hostKey ];
  };
}
