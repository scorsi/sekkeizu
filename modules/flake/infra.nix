# `nix develop .#infra`: OpenTofu for infra/ (README, "Infrastructure"). A shell of its own rather
# than kiso's default one: this is the homelab's tooling, kiso stays generic.
{ config, lib, ... }:
let
  box = config.sekkeizu.services.backup-offsite;
in
{
  perSystem =
    { pkgs, ... }:
    let
      tofuSecrets = "secrets/infra/tofu.yaml";

      # External key provider of OpenTofu's state encryption (infra/encryption.tf). Under the `tofu`
      # wrapper below, the key it decrypted once; run by a bare tofu, sops itself (a decryption each
      # time tofu reads or writes the state). Never on disk.
      # Protocol: a header line, then the keys as JSON; "null" on stdin means nothing to decrypt.
      tofuStateKey = pkgs.writers.writeNuBin "tofu-state-key" ''
        def main [] {
          print '{"magic":"OpenTofu-External-Key-Provider","version":1}'
          # sops finds the age plugin on PATH, even when tofu runs outside the infra shell.
          $env.PATH = $env.PATH | prepend "${pkgs.age-plugin-fido2-hmac}/bin"
          let input = ^${pkgs.coreutils}/bin/cat | str trim
          let key = if ($env.TOFU_STATE_KEY? | is-not-empty) { $env.TOFU_STATE_KEY } else {
            let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
            # into binary: the exact bytes sops prints, or the key changes.
            ^${pkgs.sops}/bin/sops -d --extract '["state_passphrase"]' $"($repo)/${tofuSecrets}"
              | into binary | encode base64
          }
          if ($key | is-empty) {
            error make { msg: "state passphrase not found in ${tofuSecrets}" }
          }
          let keys = if $input == "null" {
            { encryption_key: $key }
          } else {
            { encryption_key: $key, decryption_key: $key }
          }
          print ({ keys: $keys, meta: { external_data: {} } } | to json --raw)
        }
      '';

      # `tofu` of the infra shell: decrypts secrets/infra/tofu.yaml once (one touch) and hands the run
      # its values through the environment, instead of a decryption (and touches) per state access.
      # Trade-off: for the run, the values sit in the environment of tofu and its providers, which
      # already get the API keys and their resources in clear. Only the variables the stack declares
      # are passed, so a provider never sees another stack's key.
      tofu = pkgs.writers.writeNuBin "tofu" ''
        def --wrapped main [...args] {
          let tofu = "${pkgs.opentofu}/bin/tofu"
          # Global options are -flag=value: the first bare word is the subcommand.
          let cmd = $args | where {|a| not ($a | str starts-with "-") } | get 0? | default ""
          # Only the commands that need the providers' keys decrypt up front; anything else (a typo
          # included) goes straight to tofu, and a state read there falls back to tofu-state-key's sops.
          if $cmd not-in [plan apply destroy refresh import console] {
            exec $tofu ...$args
          }
          $env.PATH = $env.PATH | prepend "${pkgs.age-plugin-fido2-hmac}/bin"
          $env.SOPS_AGE_KEY_FILE = $env.SOPS_AGE_KEY_FILE? | default $"($env.HOME)/.config/sops/age/keys.txt"
          let dir = $args | where {|a| $a | str starts-with "-chdir=" } | each {|a| $a | str replace "-chdir=" "" } | get 0? | default "."
          let declared = glob ($dir | path expand | path join "*.tf")
            | each {|f| open --raw $f | parse --regex 'variable\s+"(?<name>\w+)"' | get name }
            | flatten
          let repo = ^${pkgs.git}/bin/git -C $dir rev-parse --show-toplevel | str trim
          let secrets = ^${pkgs.sops}/bin/sops -d --output-type json $"($repo)/${tofuSecrets}" | from json
          # Same bytes as `sops --extract`, which prints the string as is.
          load-env { TOFU_STATE_KEY: ($secrets.state_passphrase | into binary | encode base64) }
          load-env ($secrets | transpose name value | where name in $declared
            | reduce --fold {} {|it, acc| $acc | insert $"TF_VAR_($it.name)" $it.value })
          exec $tofu ...$args
        }
      '';
    in
    {
      devShells.infra = pkgs.mkShellNoCC {
        packages = with pkgs; [
          tofu # wraps opentofu
          sops
          age
          age-plugin-fido2-hmac # secrets/infra/ is encrypted to the FIDO2 keys: a touch per decryption
          tofuStateKey
          sshpass # stacks/storage installs the subaccount's keys on the Storage Box with its password
        ];
        # Same key file as kiso's shell: the FIDO2 identities live next to the admin key.
        shellHook = ''
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
          # Values of modules-private/, which the public infra/ tree must not spell out.
          export TF_VAR_backup_key=${lib.escapeShellArg config.sekkeizu.backupPullKey}
          export TF_VAR_azukari_offsite_key=${lib.escapeShellArg config.sekkeizu.azukariOffsiteKey}
          export TF_VAR_backup_host_key=${lib.escapeShellArg box.hostKey}
        '';
      };
    };
}
