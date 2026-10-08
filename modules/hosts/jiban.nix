# jiban (地盤, the bedrock) — Mac Mini M4, macOS managed by nix-darwin.
# A host = its identity + the list of features it imports. Nothing else.
{ config, inputs, ... }:
let
  inherit (config.flake.modules) darwin homeManager;
  inherit (config.sekkeizu) owner stateVersions;
  hostName = "jiban";
in
{
  flake.darwinConfigurations.${hostName} = inputs.nix-darwin.lib.darwinSystem {
    modules = [
      # ─── System features ──────────────────────────────────────────────
      darwin.nix
      darwin.owner
      darwin.home-manager
      darwin.fish
      darwin.homebrew
      darwin.defaults
      darwin.claude-code
      darwin.secrets
      darwin.autologin
      darwin.tailscale
      darwin.server

      # ─── User features ────────────────────────────────────────────────
      {
        home-manager.users.${owner.name}.imports = [
          homeManager.fish
          homeManager.nushell
          homeManager.ssh
          homeManager.git
          homeManager.cli
          homeManager.pay-respects
          homeManager.github
          homeManager.claude-code
          homeManager.tmux
          homeManager.theme
          homeManager.neovim
          # Full dev tooling while the Mac is the only machine;
          # remove once the laptop arrives (jiban goes back to being a pure server).
          homeManager.neovim-dev
        ];
      }

      # ─── Machine identity ─────────────────────────────────────────────
      {
        nixpkgs.hostPlatform = "aarch64-darwin";
        networking = {
          inherit hostName;
          computerName = hostName;
          localHostName = hostName; # reachable as jiban.local (Bonjour)
        };
        time.timeZone = "Europe/Paris";
        # Keeps track of the repo revision in `darwin-version`.
        system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        system.stateVersion = stateVersions.darwin;

        sops.secrets.kcpassword.sopsFile = ../../secrets/${hostName}/kcpassword;
      }
    ];
  };
}
