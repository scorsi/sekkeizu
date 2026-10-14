# `nix develop .#infra`: OpenTofu for infra/ (README, "Infrastructure"). A shell of its own rather
# than kiso's default one: this is the homelab's tooling, kiso stays generic.
{
  perSystem =
    { pkgs, ... }:
    let
      # External key provider of OpenTofu's state encryption (infra/encryption.tf): hands the state
      # passphrase from sops straight to tofu, so it never sits in the environment or on disk.
      # Protocol: a header line, then the keys as JSON; "null" on stdin means nothing to decrypt.
      tofuStateKey = pkgs.writers.writeNuBin "tofu-state-key" ''
        def main [] {
          print '{"magic":"OpenTofu-External-Key-Provider","version":1}'
          # sops finds the age plugin on PATH, even when tofu runs outside the infra shell.
          $env.PATH = $env.PATH | prepend "${pkgs.age-plugin-fido2-hmac}/bin"
          let input = ^${pkgs.coreutils}/bin/cat | str trim
          let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
          # into binary: the exact bytes sops prints, trailing newline included, or the key changes.
          let key = ^${pkgs.sops}/bin/sops -d --extract '["state_passphrase"]' $"($repo)/secrets/infra/tofu.yaml"
            | into binary | encode base64
          if ($key | is-empty) {
            error make { msg: "state passphrase not found in secrets/infra/tofu.yaml" }
          }
          let keys = if $input == "null" {
            { encryption_key: $key }
          } else {
            { encryption_key: $key, decryption_key: $key }
          }
          print ({ keys: $keys, meta: { external_data: {} } } | to json --raw)
        }
      '';
    in
    {
      devShells.infra = pkgs.mkShellNoCC {
        packages = with pkgs; [
          opentofu
          sops
          age
          age-plugin-fido2-hmac # secrets/infra/ is encrypted to the FIDO2 keys: a touch per decryption
          tofuStateKey
        ];
        # Same key file as kiso's shell: the FIDO2 identities live next to the admin key.
        shellHook = ''
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
        '';
      };
    };
}
