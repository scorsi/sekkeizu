# Automatic login for a headless Mac: boots straight into the owner's session.
# The password lives in secrets/<host>/kcpassword (sops, see `nix run .#set-autologin-password`);
# the host file points `sops.secrets.kcpassword.sopsFile` at it.
# Does NOT work with FileVault enabled: macOS ignores /etc/kcpassword and stops at the pre-boot unlock screen.
# Since the session is open without anyone typing a password, the screen is locked right away:
# the display is put to sleep at login and waking it demands the password. Only the GUI session
# is locked; launchd daemons (sshd, tailscaled) and SSH logins are unaffected.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.darwin.autologin =
    { config, ... }:
    {
      system.defaults.loginwindow.autoLoginUser = owner.name;

      system.defaults.screensaver = {
        askForPassword = true;
        askForPasswordDelay = 0;
      };

      # displaysleep is "never" (see server.nix), so nothing else would trigger the lock.
      launchd.user.agents.lock-screen-at-login.serviceConfig = {
        ProgramArguments = [
          "/usr/bin/pmset"
          "displaysleepnow"
        ];
        RunAtLoad = true;
      };

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
