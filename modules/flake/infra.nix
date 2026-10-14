# `nix develop .#infra`: OpenTofu for infra/ (README, "Infrastructure"). A shell of its own rather
# than kiso's default one: this is the homelab's tooling, kiso stays generic.
{
  perSystem =
    { pkgs, ... }:
    let
      # External key provider of OpenTofu's state encryption (infra/encryption.tf): hands the state
      # passphrase from sops straight to tofu, so it never sits in the environment or on disk.
      # Protocol: a header line, then the keys as JSON; "null" on stdin means nothing to decrypt.
      tofuStateKey = pkgs.writeShellApplication {
        name = "tofu-state-key";
        runtimeInputs = with pkgs; [
          coreutils
          git
          sops
          age-plugin-fido2-hmac
        ];
        text = ''
          echo '{"magic":"OpenTofu-External-Key-Provider","version":1}'
          input=$(cat)
          repo=$(git rev-parse --show-toplevel)
          key=$(sops -d --extract '["state_passphrase"]' "$repo/secrets/infra/tofu.yaml" | base64 -w0)
          [ -n "$key" ] || { echo "passphrase de l'état introuvable dans secrets/infra/tofu.yaml" >&2; exit 1; }
          if [ "$input" = null ]; then
            printf '{"keys":{"encryption_key":"%s"},"meta":{"external_data":{}}}' "$key"
          else
            printf '{"keys":{"encryption_key":"%s","decryption_key":"%s"},"meta":{"external_data":{}}}' "$key" "$key"
          fi
        '';
      };
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
