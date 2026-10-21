# OpenAI Codex CLI. Package only: login is interactive (`codex login`), no declared config.
{
  # With useGlobalPkgs, overlays live at the system level, not in home-manager.
  flake.modules.darwin.codex = {
    # nixpkgs packaging lags upstream releases, and older codex versions can't use OpenAI's
    # latest models; rebuild nixpkgs' derivation from a newer tag. Since the v8 150 bump codex
    # enables V8's sandbox, which denoland ships no prebuilt for: like upstream CI
    # (.github/actions/setup-rusty-v8), link OpenAI's own rusty-v8 release instead.
    # Drop this once nixpkgs' codex reaches 0.163.0.
    nixpkgs.overlays = [
      (
        final: prev:
        let
          v8Release = "https://github.com/openai/codex/releases/download/rusty-v8-v150.4.0";
        in
        {
          codex =
            (prev.codex.override {
              # shortcut: aarch64-darwin hashes only (jiban), add the platform's for another host.
              librusty_v8 = final.fetchurl {
                url = "${v8Release}/librusty_v8_ptrcomp_sandbox_release_aarch64-apple-darwin.a.gz";
                hash = "sha256-AK27SHmISMd1UEQcaGc6XoUpuOG3PqvN7iMss5tA9KE=";
              };
            }).overrideAttrs
              (
                finalAttrs: old: {
                  version = "0.163.0";
                  src = final.fetchFromGitHub {
                    owner = "openai";
                    repo = "codex";
                    tag = "rust-v${finalAttrs.version}";
                    hash = "sha256-Fa9dfiGJy+uqSF4A0EM6AQQhhjQdu+jfhKzqXid9PNA=";
                  };
                  cargoDeps = final.rustPlatform.fetchCargoVendor {
                    inherit (finalAttrs) src sourceRoot;
                    hash = "sha256-TG1fDHQCRDDbk+G0NS/9NTouJupq0Zisi4LIJY4SgYw=";
                  };
                  env = old.env // {
                    RUSTY_V8_SRC_BINDING_PATH = final.fetchurl {
                      url = "${v8Release}/src_binding_ptrcomp_sandbox_release_aarch64-apple-darwin.rs";
                      hash = "sha256-ylrfDPicmnCtRgrnNkiy/om3SqETs8t/dXtqArdYOU8=";
                    };
                  };
                }
              );
        }
      )
    ];
  };

  flake.modules.homeManager.codex = {
    programs.codex.enable = true;
  };
}
