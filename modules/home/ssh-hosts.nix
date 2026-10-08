# SSH client settings for this repo's machines; the client itself (nixpkgs' OpenSSH with FIDO2
# support, the agent) is kiso's `ssh` feature.
{
  flake.modules.homeManager.ssh-hosts = {
    programs.ssh.settings = {
      # Forwarded agent to sign commits from the server.
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
}
