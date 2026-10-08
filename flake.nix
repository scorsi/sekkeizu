{
  description = "sekkeizu — jiban (macOS, nix-darwin) and ishizue (NixOS), dendritic pattern";

  inputs = {
    # Single nixpkgs for the whole repo: the -darwin branch has an up-to-date macOS binary cache.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Auto-loads every .nix file under ./modules as a flake-parts module.
    import-tree.url = "github:vic/import-tree";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Installs and pins Homebrew itself (casks stay managed by nix-darwin).
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Catppuccin theme applied to every supported tool (bat, delta, fish, tmux…).
    catppuccin = {
      url = "github:catppuccin/nix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Encrypted secrets, decrypted at activation with the host's SSH key (see modules/base/secrets.nix).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative state on an ephemeral root (systemd mounts/tmpfiles, no activation script).
    preservation.url = "github:nix-community/preservation";

    # The owner's own flakes, prefixed `scorsi-` to tell them apart from external inputs, come from
    # Forgejo (ishizue): on the LAN, no dependence on GitHub. A fresh install or a recovery, when
    # Forgejo is out of reach, takes them from their GitHub mirrors without touching this file or
    # the lock: `nu scripts/via-github.nu <command>` (the bootstrap does it by itself).

    # Neovim and its config, a repo of its own (kiso's `kanna` feature). Pinned here so that
    # `--override-input scorsi-kanna path:…` keeps working from this repo.
    scorsi-kanna = {
      url = "git+ssh://git@ishizue.tail9883f3.ts.net:2222/scorsi/kanna.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The common base (options `kiso.*`, generic features), a flake-parts module. Every input it
    # shares with this repo follows ours: one version of each.
    # The private layer (sensitive services, their values and secrets), a flake-parts module whose
    # files behave like the ones under ./modules.
    scorsi-sekkeizu-private = {
      url = "git+ssh://git@ishizue.tail9883f3.ts.net:2222/scorsi/sekkeizu-private.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        import-tree.follows = "import-tree";
      };
    };

    scorsi-kiso = {
      url = "git+ssh://git@ishizue.tail9883f3.ts.net:2222/scorsi/kiso.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        import-tree.follows = "import-tree";
        nix-darwin.follows = "nix-darwin";
        home-manager.follows = "home-manager";
        nix-homebrew.follows = "nix-homebrew";
        catppuccin.follows = "catppuccin";
        sops-nix.follows = "sops-nix";
        scorsi-kanna.follows = "scorsi-kanna";
      };
    };
  };

  # Everything else lives in ./modules: this file should barely ever change.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.scorsi-kiso.flakeModules.default
        inputs.scorsi-sekkeizu-private.flakeModules.default
        (inputs.import-tree ./modules)
      ];
    };
}
