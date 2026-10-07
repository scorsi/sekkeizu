# flake-parts foundation: supported systems and activation of `flake.modules.<class>.<name>`,
# the option the whole dendritic pattern relies on.
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [
    "aarch64-darwin" # jiban (Mac Mini M4)
    "aarch64-linux" # ishizue (NixOS VM on Apple Silicon)
    "x86_64-linux" # future laptop, CI, dev machines
  ];
}
