# Claude Code CLI. The package is unfree in nixpkgs: the darwin half whitelists it
# (with useGlobalPkgs, nixpkgs config lives at the system level, not in home-manager).
{
  flake.modules.darwin.claude-code = {
    nixpkgs.config.allowUnfreePredicate = pkg: (pkg.pname or "") == "claude-code";
  };

  flake.modules.homeManager.claude-code =
    { pkgs, ... }:
    {
      programs.claude-code.enable = true;
      # Plugin hooks (e.g. ponytail's UserPromptSubmit) shell out to `node`.
      home.packages = [ pkgs.nodejs ];
    };
}
