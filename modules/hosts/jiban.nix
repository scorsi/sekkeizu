# jiban (地盤, le sol porteur) — Mac Mini M4, macOS géré par nix-darwin.
# Un host = son identité + la liste des fonctionnalités qu'il importe. Rien d'autre.
{ config, inputs, ... }:
let
  inherit (config.flake.modules) darwin homeManager;
  inherit (config.sekkeizu) owner stateVersions;
  hostName = "jiban";
in
{
  flake.darwinConfigurations.${hostName} = inputs.nix-darwin.lib.darwinSystem {
    modules = [
      # ─── Fonctionnalités système ─────────────────────────────────────
      darwin.nix
      darwin.owner
      darwin.home-manager
      darwin.fish
      darwin.homebrew
      darwin.defaults

      # ─── Fonctionnalités utilisateur ─────────────────────────────────
      {
        home-manager.users.${owner.name}.imports = [
          homeManager.fish
          homeManager.nushell
          homeManager.ssh
          homeManager.git
          homeManager.cli
          homeManager.tmux
          homeManager.theme
          homeManager.neovim
          # Outils de dev complets tant que le Mac est ta seule machine ;
          # à retirer quand le laptop arrive (jiban redevient un pur serveur).
          homeManager.neovim-dev
        ];
      }

      # ─── Identité de la machine ──────────────────────────────────────
      {
        nixpkgs.hostPlatform = "aarch64-darwin";
        networking = {
          inherit hostName;
          computerName = hostName;
          localHostName = hostName; # joignable en jiban.local (Bonjour)
        };
        # Garde une trace de la révision du repo dans `darwin-version`.
        system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        system.stateVersion = stateVersions.darwin;
      }
    ];
  };
}
