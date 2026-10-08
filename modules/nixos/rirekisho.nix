# The résumé (rirekisho repository), served like the site: its Forgejo Actions workflow builds the
# pages and PDFs and copies them into `dir`; Caddy serves that directory on its own port, on the
# tailnet only for now. The runner's account can write there and nowhere else (forgejo-runner.nix).
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

      services.caddy.virtualHosts.${rirekisho.url}.extraConfig = ''
        root * ${dir}
        encode zstd gzip
        file_server
      '';
    };
}
