# Headless NixOS server: key-only SSH for the owner, the NixOS twin of modules/macos/server.nix.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.nixos.server = {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AuthenticationMethods = "publickey";
        AllowUsers = [ owner.name ];
      };
    };

    # The owner has no password (FIDO2 keys only): sudo authenticates with a signature from the
    # SSH agent forwarded by the client (`ssh -A`), i.e. one touch on the hardware key per sudo.
    # pam_rssh rather than pam_ssh_agent_auth (security.pam.sshAgentAuth), which can't verify
    # security-key (sk-ssh-ed25519) signatures.
    security.pam.rssh = {
      enable = true;
      # Root-owned and separate from the login keys: nothing the user can write.
      settings.auth_key_file = "/etc/ssh/sudo_authorized_keys";
    };
    security.pam.services.sudo.rssh = true;
    environment.etc."ssh/sudo_authorized_keys".text = lib.concatMapStrings (
      k: "${k.key}\n"
    ) owner.sshKeys;
  };
}
