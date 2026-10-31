# oroshi, the lab's Nix binary cache (its own repo, consumed as `scorsi-oroshi`; its docs/usage.md):
# the server on hashira-01, the readers, jiban as the only uploader.
#
# The unit only accepts loopback peers (oroshi ADR 0010, 0014): hashira-01's genkan terminates
# `oroshi.uchi` on the web port and proxies to it; the other genkan host forwards that SNI raw to
# hashira-01's. State on one DAS disk, never the /srv/das mergerfs pool (ADR 0014 rules out union
# filesystems). No garbage collector yet (oroshi O2): once full, uploads get 507 and builds go on
# uncached.
#
# jiban signs what it builds (`oroshi-jiban-1`, secrets/jiban/oroshi.yaml) and pushes it with a
# post-build-hook; oroshi only checks signatures. Readers fall through to cache.nixos.org on a miss
# or when oroshi is down. torii-cdg is no reader: the gate reaches the hashira's `services` port
# only, never the web sites (genkan.nix), and a public host has no business reading the lab's builds.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.sekkeizu)
    genkanHosts
    kekkai
    oroshi
    services
    ;
  serverHost = "hashira-01";
  stateDir = "/mnt/das/S3PNQ734/oroshi";
  # The module's default listen address.
  backend = "127.0.0.1:8080";
  # Scraped by the local hikyaku only (masu metric convention: loopback).
  metrics = "127.0.0.1:9478";
  url = "${services.oroshi.url}/nix";
  # Substituted dependencies in jiban's closures keep upstream's signature (oroshi ADR 0007).
  upstreamKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

  readerSettings = {
    substituters = lib.mkBefore [ url ];
    trusted-public-keys = lib.attrValues oroshi.publicKeys;
    # Nix's default 0 leaves curl's own connect timeout (minutes): an unreachable oroshi would stall
    # substitution before Nix disables it and falls through to cache.nixos.org.
    connect-timeout = 5;
    # A narinfo found but its NAR failing (oroshi going down mid-transfer) builds instead of failing.
    fallback = true;
  };
in
{
  options.sekkeizu.oroshi = {
    publicKeys = mkOption {
      type = types.attrsOf types.str;
      description = "Nix signing public keys of oroshi's uploaders, by host.";
    };
    tokenHashes = mkOption {
      type = types.attrsOf types.str;
      description = "Hex SHA-256 of each uploader's write token (`oroshi token hash`), by host.";
    };
  };

  config.flake.modules = {
    # Every genkan host but the server's: forward the name raw by SNI to hashira-01's genkan.
    nixos.genkan =
      { config, ... }:
      lib.mkIf (!config.services.genkan.sites ? ${services.oroshi.host}) {
        services.genkan.passthrough.oroshi = {
          listener = "default";
          sni = [ services.oroshi.host ];
          backend = "${kekkai.nodes.${serverHost}.ipv4}:443";
        };
      };

    nixos.oroshi =
      { pkgs, ... }:
      {
        imports = [ inputs.scorsi-oroshi.nixosModules.default ];

        services.oroshi = {
          enable = true;
          # shortcut: oroshi's flake only exports aarch64 systems, so x86_64 builds its package.nix the
          # way the flake does (its own nixpkgs and crane); drop once it lists x86_64-linux.
          package =
            let
              src = inputs.scorsi-oroshi;
              own = src.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
            in
            own.callPackage "${src}/nix/package.nix" { craneLib = src.inputs.crane.mkLib own; };
          inherit stateDir;
          metrics.listen = metrics;
          # Half the 500 GB disk (decimal, as sold): the rest is headroom for SQLite's WAL, uploads in
          # flight and mergerfs, which also creates files on this branch.
          storage.maxBytes = 250 * 1000 * 1000 * 1000;
          tokens = lib.mapAttrs (_: sha256: {
            inherit sha256;
            scopes = [ "nix:write" ];
          }) oroshi.tokenHashes;
          nix.trustedKeys = lib.attrValues oroshi.publicKeys ++ upstreamKeys;
        };

        systemd.services.oroshi = {
          # The DAS mounts with nofail: without the disk, oroshi must not start on the tmpfs root.
          unitConfig.RequiresMountsFor = [ stateDir ];
          # The module expects a custom stateDir to exist, owned by oroshi; `+` runs this as root.
          serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0750 -o oroshi -g oroshi ${stateDir}";
        };

        services.genkan.sites.${services.oroshi.host}.backend = "http://${backend}";

        # oroshi's loopback /metrics, for the host's hikyaku.
        services.hikyaku.targets.oroshi.url = "http://${metrics}/metrics";
      };

    nixos.oroshi-reader = {
      nix.settings = readerSettings;
      # The nodes ask Quad9, not annai (annai.nix); curl tries each address in turn.
      networking.hosts = lib.genAttrs (map (h: kekkai.nodes.${h}.ipv4) genkanHosts) (_: [
        services.oroshi.host
      ]);
    };

    darwin.oroshi-reader.nix.settings = readerSettings;

    darwin.oroshi-uploader =
      { config, pkgs, ... }:
      let
        netrc = config.sops.secrets.oroshi-netrc.path;
        upload = pkgs.writeShellScript "oroshi-upload" ''
          set -u
          export NIX_CONFIG="netrc-file = ${netrc}
          connect-timeout = 5"
          # Nix stops scheduling builds when this hook fails: an unreachable or full oroshi costs a log
          # line, never a build. The hook blocks the build loop, hence the cap; paths already there are
          # skipped, so an interrupted closure completes on a later build.
          if ! ${pkgs.coreutils}/bin/timeout 600 ${config.nix.package}/bin/nix copy \
            --to '${url}?compression=zstd' $OUT_PATHS; then
            echo "oroshi-upload: upload failed or timed out, skipped: $OUT_PATHS" >&2
          fi
          exit 0
        '';
      in
      {
        sops.secrets =
          lib.genAttrs
            [
              "oroshi-signing-key"
              "oroshi-netrc"
            ]
            (_: {
              sopsFile = ../../secrets/${config.networking.hostName}/oroshi.yaml;
            });
        nix.settings = {
          # Nix signs every path built here with it (oroshi ADR 0007).
          secret-key-files = [ config.sops.secrets.oroshi-signing-key.path ];
          netrc-file = netrc;
          post-build-hook = upload;
        };
      };
  };
}
