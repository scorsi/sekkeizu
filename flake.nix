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

    # Partitions a cloud machine's disk when nixos-anywhere installs it (modules/nixos/vultr-guest.nix).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The owner's own flakes, prefixed `scorsi-` to tell them apart from external inputs, come from
    # Forgejo (ishizue): on the LAN, no dependence on GitHub. A fresh install or a recovery, when
    # Forgejo is out of reach, takes them from their GitHub mirrors without touching this file or
    # the lock: `nu scripts/via-github.nu <command>` (the bootstrap does it by itself).

    # Neovim and its config, a repo of its own (kiso's `kanna` feature). Pinned here so that
    # `--override-input scorsi-kanna path:…` keeps working from this repo.
    scorsi-kanna = {
      url = "git+https://kajiba.uchi.scorsi.dev/scorsi/kanna.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The DNS server of the homelab (modules/network/annai.nix). Not following our nixpkgs: annai
    # pins its own nixpkgs and Zig toolchain (zig2nix) and is built and tested against them.
    scorsi-annai.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/annai.git";

    # The observability stores (modules/observability/masu.nix, nisshi.nix). Not following our nixpkgs either:
    # each pins its own and is tested against it.
    scorsi-masu.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/masu.git";
    scorsi-nisshi.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/nisshi.git";
    # The node agent (modules/observability/hikyaku.nix); its masu and nisshi inputs are test-only.
    scorsi-hikyaku.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/hikyaku.git";

    # The certificates (modules/network/hanko.nix). Not following our nixpkgs: tested against its
    # own; its annai and nisshi inputs are test-only.
    scorsi-hanko.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/hanko.git";

    # The object store and the nodes' backups (modules/backup/azukari.nix). Not following our
    # nixpkgs: tested against its own; its masu and nisshi inputs are test-only.
    scorsi-azukari.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/azukari.git";

    # The Nix binary cache (modules/cache/oroshi.nix). Not following our nixpkgs: tested against its
    # own; its masu and nisshi inputs are test-only.
    scorsi-oroshi.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/oroshi.git";

    # The overlay network (modules/network/kekkai.nix). Not following our nixpkgs: tested against
    # its own; its masu and nisshi inputs are test-only.
    scorsi-kekkai.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/kekkai.git";

    # The reverse proxy (modules/network/genkan.nix). Not following our nixpkgs: tested against its
    # own; its masu and nisshi inputs are test-only.
    scorsi-genkan.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/genkan.git";

    # The forge (modules/nixos/kajiba.nix). Not following our nixpkgs: tested against its own; its
    # masu and nisshi inputs are test-only.
    scorsi-kajiba.url = "git+https://kajiba.uchi.scorsi.dev/scorsi/kajiba.git";

    # The Claude Code status line (modules/home/claude-code.nix).
    scorsi-shiori = {
      url = "git+https://kajiba.uchi.scorsi.dev/scorsi/shiori.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The common base (options `kiso.*`, generic features), a flake-parts module. Every input it
    # shares with this repo follows ours: one version of each.
    scorsi-kiso = {
      url = "git+https://kajiba.uchi.scorsi.dev/scorsi/kiso.git";
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
        # modules-private/ is git-crypt encrypted (.gitattributes): values that stay out of the public tree.
        (inputs.import-tree [
          ./modules
          ./modules-private
        ])
      ];
    };
}
