# Command-line toolbox, identical on the Mac, the VM, and the future laptop.
{
  flake.modules.homeManager.cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ripgrep
        fd
        jq
        yq-go
        dust # readable du
        duf # readable df
        tree
        just
        curl
        wget
      ];

      programs = {
        # fish enables man-page caching by default; on macOS home-manager doesn't
        # provide `man` (the system one is used), so the cache has no effect.
        man.generateCaches = false;

        eza.enable = true;
        btop.enable = true;
        bat.enable = true;
        fzf.enable = true;
        zoxide.enable = true;

        # `use flake` in a .envrc: per-project dev environment, cached.
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}
