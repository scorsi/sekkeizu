# OpenAI Codex CLI. Package only: login is interactive (`codex login`), no declared config.
{
  # With useGlobalPkgs, overlays live at the system level, not in home-manager.
  flake.modules.darwin.codex = {
    # nixpkgs packaging lags upstream releases, and older codex versions can't use OpenAI's
    # latest models. Upstream's prebuilt release replaces it: no 20-minute Rust build (which
    # also needs OpenAI's own sandboxed V8 build), and a bump is a version + hash change.
    # codex-package is upstream's install layout: codex, its code-mode host and a bundled rg.
    # Drop this once nixpkgs' codex reaches 0.163.0.
    nixpkgs.overlays = [
      (final: prev: {
        codex = final.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "codex";
          version = "0.163.0";
          src = final.fetchurl {
            url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-aarch64-apple-darwin.tar.gz";
            hash = "sha256-sDRPwuQfFeAHEUflhpAIBHuP9L8sSoiXl107rj8QOzQ=";
          };
          dontUnpack = true;
          installPhase = "mkdir $out && tar -xzf $src -C $out";
          # Upstream signs the binaries; stripping would invalidate the signature.
          dontFixup = true;
          meta = {
            description = "Lightweight coding agent that runs in your terminal";
            homepage = "https://github.com/openai/codex";
            license = final.lib.licenses.asl20;
            mainProgram = "codex";
            platforms = [ "aarch64-darwin" ];
            sourceProvenance = [ final.lib.sourceTypes.binaryNativeCode ];
          };
        });
      })
    ];
  };

  flake.modules.homeManager.codex = {
    programs.codex.enable = true;
  };
}
