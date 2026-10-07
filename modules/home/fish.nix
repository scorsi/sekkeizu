# fish: login shell (system level) + configuration (home-manager level).
# Typical example of the dendritic pattern: one feature, three classes, one file.
{ config, ... }:
let
  owner = config.sekkeizu.owner.name;
in
{
  flake.modules.darwin.fish =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      environment.shells = [ pkgs.fish ];

      # nix-darwin won't change the shell of an account it doesn't manage:
      # done here at activation instead, idempotently.
      system.activationScripts.postActivation.text = ''
        target=/run/current-system/sw/bin/fish
        current=$(dscl . -read /Users/${owner} UserShell | awk '{print $2}')
        if [ "$current" != "$target" ]; then
          echo "sekkeizu: shell de ${owner} -> $target"
          dscl . -create /Users/${owner} UserShell "$target"
        fi
      '';
    };

  flake.modules.nixos.fish =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      users.users.${owner}.shell = pkgs.fish;
    };

  flake.modules.homeManager.fish =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;

        # Plugins carried over from dev-configs (ex-fisher), now provided by nixpkgs.
        plugins = map (p: { inherit (p) name src; }) (
          with pkgs.fishPlugins;
          [
            fzf-fish # Ctrl+R history, Ctrl+Alt+F files, Ctrl+Alt+L git log…
            autopair # auto-closes () [] {} "" ''
            sponge # removes failed commands from history
          ]
        );

        interactiveShellInit = ''
          set -g fish_greeting
          set -g sponge_purge_only_on_exit true
          set -g fzf_preview_dir_cmd eza --tree --color=always
          set -g fzf_diff_highlighter delta --paging=never --width=20
        '';

        shellAliases = {
          ls = "eza --color=always --icons=always -A";
          ll = "ls --long --no-filesize --no-time --no-user --no-permissions --git";
          lt = "ll --tree";
          cat = "bat";
          vim = "nvim";
          vi = "nvim";
        };

        shellAbbrs = {
          g = "git";
          gs = "git status -sb";
          zz = "z -";
          # Rebuild the Mac from the repo (bootstrap's default path).
          drs = "sudo darwin-rebuild switch --flake ~/sekkeizu";
        };
      };

      # fzf.fish ships its own shortcuts: disable fzf's to avoid duplicates.
      programs.fzf.enableFishIntegration = false;
      # The ls/ll/lt aliases above replace the ones home-manager generates.
      programs.eza.enableFishIntegration = false;

      programs.starship.enable = true;
    };
}
