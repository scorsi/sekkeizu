# hanko, the lab's certificates (docs/migration.md, step 3): Let's Encrypt by DNS-01, the challenge
# record written by RFC 2136 UPDATE to every annai `soto` address (annai-soto.nix, same TSIG key).
# The internal wildcard is what genkan serves in step 4; genkan's own group reads it (hanko ADR 0005).
# A oneshot without /metrics (hanko ADR 0007): its schema v1 lines reach nisshi through hikyaku's
# journald reader.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) domain publicAddresses;
  soto = publicAddresses.torii-cdg;
in
{
  flake.modules.nixos.hanko =
    { config, pkgs, ... }:
    let
      backup = pkgs.writeShellApplication {
        name = "backup-hanko-account";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.diffutils
          pkgs.openssl
        ];
        text = builtins.readFile ../backup/hanko-account.sh;
      };
    in
    {
      imports = [ inputs.scorsi-hanko.nixosModules.default ];

      sops.secrets.hanko-tsig = {
        sopsFile = ../../secrets/hanko/tsig.yaml;
        owner = "hanko";
        mode = "0400";
      };

      services.hanko = {
        enable = true;
        acme = {
          # Trials: https://acme-staging-v02.api.letsencrypt.org/directory. Changing it keeps a
          # still-valid certificate (hanko's Due ignores the issuer): remove uchi/*.pem to reissue.
          directory = "https://acme-v02.api.letsencrypt.org/directory";
          acceptTerms = true;
        };
        dns = {
          nameservers = [
            "${soto.ipv4}:53"
            "[${soto.ipv6}]:53"
          ];
          tsigKeyFile = config.sops.secrets.hanko-tsig.path;
        };
        certificates.uchi = {
          hosts = [ "*.uchi.${domain}" ];
          reload = [ "genkan.service" ];
          group = "genkan";
        };
      };

      # genkan's own group (genkan's module declares the same, step 4): the certificate directory
      # needs it before genkan is deployed.
      users.groups.genkan = { };

      # CAA pins this account's URI: restoring its key preserves that identity.
      sekkeizu.persist.directories = [
        {
          directory = "/var/lib/hanko";
          user = "hanko";
          group = "hanko";
          mode = "0751";
        }
      ];

      # The export root, for the backups to pick up; backup-source no longer creates it on this host.
      systemd.tmpfiles.rules = [ "d /persist/backups 0700 root root -" ];

      systemd.services.hanko-backup = {
        description = "Back up Hanko's ACME account identity";
        wantedBy = [ "multi-user.target" ];
        after = [ "hanko.service" ];
        startAt = "*-*-* 04:40:00";
        unitConfig.RequiresMountsFor = [
          "/persist/backups"
          "/var/lib/hanko"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          UMask = "0027";
          ExecStart = "${lib.getExe backup} ${lib.escapeShellArg config.services.hanko.acme.accountKeyFile} /persist/backups/hanko";
          ProtectSystem = "strict";
          ReadWritePaths = [ "/persist/backups" ];
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    };
}
