# The résumé (rirekisho repository): its Forgejo Actions workflow builds the
# pages and PDFs and copies them into `dir`; genkan serves that directory as static files, on the
# overlay as `rirekisho.uchi` and publicly under `rirekisho.public` (endpoints.nix) through
# torii-cdg's genkan (genkan.nix), with a certificate of their own from hanko. The runner's account
# can write there and nowhere else (forgejo-runner.nix).
#
# The résumé's contact details stay out of its public repository: RIREKISHO_EMAIL and
# RIREKISHO_PHONE in a dotenv file, readable by the runner only, which rirekisho's workflow reads at
# build time (/run/secrets/rirekisho-env, sops-nix's default path for this name).
# Edit: `sops edit secrets/hashira-02/rirekisho.env` (values unquoted, spaces allowed). Locally, for a
# PDF with them: `sops exec-env secrets/hashira-02/rirekisho.env 'pnpm build && pnpm pdf'`.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) services;
  rirekisho = services.rirekisho;
  dir = "/var/lib/rirekisho";
in
{
  flake.modules.nixos.rirekisho =
    { config, pkgs, ... }:
    let
      runner = config.sekkeizu.forgejo-runner;
    in
    {
      sekkeizu = {
        persist.directories = [
          {
            directory = dir;
            user = runner.user;
            group = runner.user;
            mode = "0755";
          }
        ];
        # Node, pnpm and Chromium come from the repository's own dev shell; only the copy runs on the host.
        forgejo-runner = {
          extraPackages = [ pkgs.rsync ];
          writablePaths = [ dir ];
        };
      };

      sops.secrets.rirekisho-env = {
        sopsFile = ../../secrets/${config.networking.hostName}/rirekisho.env;
        format = "dotenv";
        # The whole file, not one of its keys.
        key = "";
        owner = runner.user;
      };

      services.hanko.certificates.rirekisho-public = {
        hosts = rirekisho.public;
        reload = [ "genkan.service" ];
        group = "genkan";
      };

      services.genkan = {
        certificates.rirekisho-public = {
          hosts = rirekisho.public;
          cert = "/var/lib/hanko/rirekisho-public/fullchain.pem";
          key = "/var/lib/hanko/rirekisho-public/key.pem";
        };
        sites = {
          ${rirekisho.host}.root = dir;
        }
        // lib.genAttrs rirekisho.public (_: {
          root = dir;
          # Named, the PROXY listener serves them (genkan ADR 0013); `uchi` names stay off it.
          listeners = [
            "default"
            "edge"
          ];
        });
      };
    };
}
