# SSH client + agent, with FIDO2 key support (ed25519-sk).
#
# macOS ships its own ssh/ssh-agent, built WITHOUT hardware key support:
# replaced here by nixpkgs'. The agent runs as a LaunchAgent (macOS) or a
# systemd user service (NixOS). An incoming SSH session with a forwarded agent
# (`ssh -A`) keeps the laptop's agent: home-manager doesn't override it.
{
  flake.modules.homeManager.ssh =
    { pkgs, ... }:
    {
      services.ssh-agent = {
        enable = true;
        package = pkgs.openssh;
      };

      programs.ssh = {
        enable = true;
        package = pkgs.openssh;
        enableDefaultConfig = false;
        # Raw OpenSSH directives (ssh_config(5)), one block per host pattern.
        settings = {
          "*" = {
            # The key used (hardware key handle) is added to the agent:
            # git can then sign with it, and `ssh -A` forwards it.
            AddKeysToAgent = "yes";
            # Avoids the "agent refused operation" noise when the agent tries the
            # FIDO2 identity whose device is absent before falling back to the plugged-in one.
            LogLevel = "ERROR";
          };
          # sekkeizu machines: forwarded agent to sign commits from the server.
          "jiban jiban.local ishizue ishizue.local" = {
            ForwardAgent = true;
          };
          # A deploy opens several connections (build host, target host, switch): one master
          # connection means a single FIDO2 touch. %C hashes local host, host, port and user, so
          # root@ and the owner get separate masters; it also keeps the socket path under macOS's
          # 104-byte limit.
          "ishizue ishizue.local" = {
            ControlMaster = "auto";
            ControlPath = "~/.ssh/cm-%C";
            ControlPersist = "10m";
          };
        };
      };
    };
}
