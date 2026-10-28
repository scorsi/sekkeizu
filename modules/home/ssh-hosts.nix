# SSH client settings for this repo's machines; the client itself (nixpkgs' OpenSSH with FIDO2
# support, the agent) is kiso's `ssh` feature.
{ config, ... }:
let
  kekkaiName = host: "${host}.kekkai.uchi.${config.sekkeizu.domain}";
in
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
      "ishizue ishizue.local torii-cdg.scorsi.dev ${kekkaiName "ishizue"} ${kekkaiName "torii-cdg"} ${kekkaiName "hashira-01"} ${kekkaiName "hashira-02"}" =
        {
          ControlMaster = "auto";
          ControlPath = "~/.ssh/cm-%C";
          ControlPersist = "10m";
        };
      # Same host key whichever path a deploy takes (kekkai, or the fallback name): one known_hosts
      # entry per host.
      ${kekkaiName "ishizue"}.HostKeyAlias = "ishizue.local";
      ${kekkaiName "torii-cdg"}.HostKeyAlias = "torii-cdg.scorsi.dev";
    };
  };
}
