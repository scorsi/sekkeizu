# Headless NixOS server: key-only SSH for the owner, the NixOS twin of modules/macos/server.nix.
{ config, lib, ... }:
let
  inherit (config.kiso) owner;
in
{
  flake.modules.nixos.server = {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        # Root only for deploys (one SSH session = one touch, no per-sudo touches), and only from
        # the Mac's NAT bridge or Tailscale (CGNAT range), with the FIDO2 keys below.
        PermitRootLogin = "prohibit-password";
        AuthenticationMethods = "publickey";
        AllowUsers = [
          owner.name
          "root@192.168.64.1"
          "root@100.64.0.0/10"
        ];
      };
    };
    users.users.root.openssh.authorizedKeys.keys = map (k: k.key) owner.sshKeys;

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
