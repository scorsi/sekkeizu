# Claude Code CLI. The package is unfree in nixpkgs: the darwin half whitelists it
# (with useGlobalPkgs, nixpkgs config lives at the system level, not in home-manager).
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
      # Compiled, so no interpreter is needed at runtime (Claude Code shells out to it on
      # every status-line refresh).
      statusline = pkgs.stdenv.mkDerivation {
        name = "claude-code-statusline";
        src = ./claude-code-statusline.nim;
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.nim ];
        # The store file name isn't a valid Nim module name.
        buildPhase = "cp $src main.nim && nim c -d:release --nimcache:$TMPDIR/nimcache -o:claude-code-statusline main.nim";
        installPhase = "install -D claude-code-statusline $out/bin/claude-code-statusline";
      };

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
        statusLine = {
          type = "command";
          command = "${statusline}/bin/claude-code-statusline";
        };
      };
      settingsPatchJson = pkgs.writeText "claude-code-settings-patch.json" (
        builtins.toJSON settingsPatch
      );
      settingsFile = "${config.programs.claude-code.configDir}/settings.json";
    in
    {
      programs.claude-code.enable = true;
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
