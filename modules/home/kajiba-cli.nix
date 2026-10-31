# kajiba CLI (`kajiba login`, `kajiba ci …`) against the forge on hashira-01.
{ inputs, ... }:
{
  flake.modules.homeManager.kajiba-cli =
    { pkgs, ... }:
    {
      home.packages = [ inputs.scorsi-kajiba.packages.${pkgs.stdenv.hostPlatform.system}.kajiba-cli ];
    };
}
