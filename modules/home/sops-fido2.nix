# The FIDO2 age plugin on PATH: every sops file is encrypted to the two FIDO2 keys (.sops.yaml), and
# sops, the flake apps (rekey-host, install-ishizue) and the infra shell call it by name to decrypt.
{
  flake.modules.homeManager.sops-fido2 =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.age-plugin-fido2-hmac ];
    };
}
