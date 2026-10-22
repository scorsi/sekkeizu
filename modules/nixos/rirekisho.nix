# The résumé (rirekisho repository), served like the site: its Forgejo Actions workflow builds the
# pages and PDFs and copies them into `dir`; genkan serves that directory as static files, on the
# overlay only for now. The runner's account can write there and nowhere else (forgejo-runner.nix).
#
# The résumé's contact details stay out of its public repository: RIREKISHO_EMAIL and
# RIREKISHO_PHONE in a dotenv file, readable by the runner only, which rirekisho's workflow reads at
# build time (/run/secrets/rirekisho-env, sops-nix's default path for this name).
# Edit: `sops edit secrets/ishizue/rirekisho.env` (values unquoted, spaces allowed). Locally, for a
# PDF with them: `sops exec-env secrets/ishizue/rirekisho.env 'pnpm build && pnpm pdf'`.
{ config, ... }:
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
        sopsFile = ../../secrets/ishizue/rirekisho.env;
        format = "dotenv";
        # The whole file, not one of its keys.
        key = "";
        owner = runner.user;
      };

      services.genkan.sites.${rirekisho.host}.root = dir;
    };
}
