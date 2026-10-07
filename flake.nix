{
  description = "homelab — jiban (macOS, nix-darwin) et ishizue (NixOS), pattern dendritique";

  inputs = {
    # Un seul nixpkgs pour tout le repo : la branche -darwin a un cache binaire macOS à jour.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Charge automatiquement chaque fichier .nix de ./modules comme module flake-parts.
    import-tree.url = "github:vic/import-tree";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Installe et épingle Homebrew lui-même (les casks restent gérés par nix-darwin).
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Thème Catppuccin appliqué à tous les outils supportés (bat, delta, fish, tmux…).
    catppuccin = {
      url = "github:catppuccin/nix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Tout le reste vit dans ./modules : ce fichier ne devrait quasiment plus bouger.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
