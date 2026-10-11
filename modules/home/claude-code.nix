# Claude Code CLI. The package is unfree in nixpkgs: the darwin half whitelists it
# (with useGlobalPkgs, nixpkgs config lives at the system level, not in home-manager).
{
  flake.modules.darwin.claude-code = {
    nixpkgs.config.allowUnfreePredicate = pkg: (pkg.pname or "") == "claude-code";
  };

  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Claude Code installs whatever these keys declare on its next start, in the CLI and the
      # desktop app alike. programs.claude-code.{settings,plugins} can't do it: the first turns
      # settings.json into a read-only store link (Claude Code writes to it), the second only
      # wraps the CLI binary, which the desktop app doesn't use.
      plugins = {
        extraKnownMarketplaces.ponytail.source = {
          source = "github";
          repo = "DietrichGebert/ponytail";
        };
        enabledPlugins = {
          "ponytail@ponytail" = true;
          "rust-analyzer-lsp@claude-plugins-official" = true;
        };
      };
      pluginsJson = pkgs.writeText "claude-code-plugins.json" (builtins.toJSON plugins);
      settingsFile = "${config.programs.claude-code.configDir}/settings.json";
    in
    {
      programs.claude-code.enable = true;
      # Plugin hooks (e.g. ponytail's UserPromptSubmit) shell out to `node`.
      home.packages = [ pkgs.nodejs ];

      # Merged into the mutable file rather than owning it: the declared keys win, the rest
      # (theme, effort level, whatever Claude Code writes) is kept.
      home.activation.claudeCodePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings=${lib.escapeShellArg settingsFile}
        run mkdir -p "$(dirname "$settings")"
        [ -s "$settings" ] || echo '{}' > "$settings"
        tmp=$(mktemp)
        ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$settings" ${pluginsJson} > "$tmp"
        if cmp -s "$tmp" "$settings"; then rm "$tmp"; else run mv "$tmp" "$settings"; fi
      '';
    };
}
