# Claude Code CLI. The package is unfree in nixpkgs: the darwin half whitelists it
# (with useGlobalPkgs, nixpkgs config lives at the system level, not in home-manager).
# The status line is shiori, its own flake: it patches settings.json's statusLine key itself.
{ inputs, ... }:
{
  flake.modules.darwin.claude-code = {
    nixpkgs.config.allowUnfreePredicate = pkg: (pkg.pname or "") == "claude-code";
    # nixpkgs packaging lags upstream releases by weeks; override just the binary manifest
    # (same mechanism nixpkgs' own update.sh uses) to track current claude-code. Drop this
    # once nixpkgs' pinned manifest.json catches up to claude-code-manifest.json's version.
    nixpkgs.overlays = [
      (final: prev: {
        claude-code = prev.claude-code.override {
          manifest = prev.lib.importJSON ./claude-code-manifest.json;
        };
      })
    ];
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
      settingsPatch = {
        extraKnownMarketplaces.ponytail.source = {
          source = "github";
          repo = "DietrichGebert/ponytail";
        };
        enabledPlugins = {
          "ponytail@ponytail" = true;
        }
        # The LSP plugins only wire Claude Code to servers kanna's withDevTools puts on PATH;
        # keep this list in step with kanna/nix/dev-tools.nix. Guarded for hosts without kanna.
        // lib.optionalAttrs (config.programs ? kanna && config.programs.kanna.withDevTools) {
          "rust-analyzer-lsp@claude-plugins-official" = true;
          "typescript-lsp@claude-plugins-official" = true;
          "gopls-lsp@claude-plugins-official" = true;
          "lua-lsp@claude-plugins-official" = true;
        };
      };
      settingsPatchJson = pkgs.writeText "claude-code-settings-patch.json" (
        builtins.toJSON settingsPatch
      );
      settingsFile = "${config.programs.claude-code.configDir}/settings.json";
    in
    {
      imports = [ inputs.scorsi-shiori.homeModules.shiori ];

      programs.claude-code.enable = true;
      programs.shiori = {
        enable = true;
        preset = "nerd-font";
        settings.palette = "catppuccin-mocha";
      };
      # Plugin hooks (e.g. ponytail's UserPromptSubmit) shell out to `node`.
      home.packages = [ pkgs.nodejs ];

      # Merged into the mutable file rather than owning it: the declared keys win, the rest
      # (theme, effort level, whatever Claude Code writes) is kept.
      home.activation.claudeCodeSettingsPatch = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings=${lib.escapeShellArg settingsFile}
        run mkdir -p "$(dirname "$settings")"
        [ -s "$settings" ] || echo '{}' > "$settings"
        tmp=$(mktemp)
        ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$settings" ${settingsPatchJson} > "$tmp"
        if cmp -s "$tmp" "$settings"; then rm "$tmp"; else run mv "$tmp" "$settings"; fi
      '';
    };
}
