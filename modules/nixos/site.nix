# The static site: built by a Forgejo Actions workflow in the `site` repository, which copies the
# result into `dir`; Caddy serves that directory on its own port. The directory survives reboots,
# and the runner's account can write there and nowhere else (see forgejo-runner.nix).
{ config, ... }:
let
  inherit (config.sekkeizu) services;
  site = services.site;
  dir = "/var/lib/site";
in
{
  flake.modules.nixos.site =
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
        # What the workflow of the site repository calls (zola build, rsync).
        forgejo-runner = {
          extraPackages = [
            pkgs.zola
            pkgs.rsync
          ];
          writablePaths = [ dir ];
        };
      };

      services.caddy.virtualHosts.${site.url}.extraConfig = ''
        root * ${dir}
        encode zstd gzip
        file_server
      '';
    };
}
