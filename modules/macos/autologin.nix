# Automatic login for a headless Mac: boots straight into the owner's session.
# The password lives in secrets/<host>/kcpassword (sops, see `nix run .#set-autologin-password`);
# the host file points `sops.secrets.kcpassword.sopsFile` at it.
# Does NOT work with FileVault enabled: macOS ignores /etc/kcpassword and stops at the pre-boot unlock screen.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.darwin.autologin =
    { config, ... }:
    {
      system.defaults.loginwindow.autoLoginUser = owner.name;

      sops.secrets.kcpassword.format = "binary";

      # A real file, not a link to /run/secrets: /run doesn't exist yet when loginwindow reads it at boot.
      # mkOrder 1600 runs after sops-nix's own mkAfter (1500) install step, so the secret is decrypted by then.
      system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
        install -m 600 -o root -g wheel ${config.sops.secrets.kcpassword.path} /etc/kcpassword
        if fdesetup status | grep -q "is On"; then
          echo "warning: FileVault is on, auto-login is ignored by macOS (disable it for a headless boot)" >&2
        fi
      '';
    };
}
