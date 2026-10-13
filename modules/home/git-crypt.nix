# git-crypt on PATH: an unlocked clone of this repo calls it by name from its git filters
# (.gitattributes), on every checkout, add and diff.
{
  flake.modules.homeManager.git-crypt =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.git-crypt ];
    };
}
