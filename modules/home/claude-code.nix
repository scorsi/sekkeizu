# Claude Code CLI. The package is unfree in nixpkgs: the darwin half whitelists it
# (with useGlobalPkgs, nixpkgs config lives at the system level, not in home-manager).
{
  flake.modules.darwin.claude-code = {
    nixpkgs.config.allowUnfreePredicate = pkg: (pkg.pname or "") == "claude-code";
  };

  flake.modules.homeManager.claude-code = {
    programs.claude-code.enable = true;
  };
}
