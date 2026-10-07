# Socle flake-parts : systèmes supportés et activation de `flake.modules.<classe>.<nom>`,
# l'option sur laquelle repose tout le pattern dendritique.
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [
    "aarch64-darwin" # jiban (Mac Mini M4)
    "aarch64-linux" # ishizue (VM NixOS sur Apple Silicon)
    "x86_64-linux" # futur laptop, CI, machines de dev
  ];
}
