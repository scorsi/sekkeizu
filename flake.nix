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

    # Neovim and its config, a repo of its own (modules/home/kanna.nix). Always fetched from GitHub,
    # never from Forgejo: rebuilding a machine must not depend on the forge it hosts.
    kanna = {
      url = "github:scorsi/kanna";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Everything else lives in ./modules: this file should barely ever change.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
