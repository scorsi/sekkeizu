# kajiba, the owner's own forge (its own repo, consumed as `scorsi-kajiba`), on hashira-01 with one
# runner there, next to Forgejo until the switch.
#
# Three ways in, all through genkan on both hashira (kekkai.nix opens the backend ports to
# hashira-02's genkan; hashira-01's reaches its own kekkai address locally):
# - `kajiba.uchi` on the web port: genkan terminates TLS (hanko's wildcard) and forwards over h2c
#   (genkan ADR 0016), so the CLI's gRPC reaches kajiba's plaintext port as HTTP/2 and git over HTTP
#   as HTTP/1.1. Overlay only, never public: anonymous reads of the public repositories stay inside
#   kekkai.
# - `runner-gateway.kajiba.uchi` on genkan's `services` port: forwarded raw by SNI to kajiba's runner
#   listener, mTLS end to end with hanko-ca's SVIDs (kajiba ADR 0124, hanko-ca.nix), like azukari.
# - git over SSH on 2223 (Forgejo keeps 2222): genkan's `kajiba-ssh` passthrough to kajiba's own
#   sshd. Not on 2223 itself: hashira-01's genkan holds that port on every address.
#
# Repositories are declared here (kajiba ADR 0026: nothing creates one at runtime) and filled once
# with `kajiba-server admin import`. The sshd's host key is in sops (secrets/hashira-01/kajiba.yaml),
# pinned as `kajiba-ssh.hostKey` in endpoints.nix.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu)
    domain
    genkanHosts
    kekkai
    services
    ;
  inherit (config.kiso) owner;
  trustDomain = "uchi.${domain}";
  host = "hashira-01";
  address = kekkai.nodes.${host}.ipv4;
  # After azukari (5000); kekkai.nix opens them to hashira-02's genkan.
  ports = {
    http = 5010;
    runners = 5011;
    ssh = 5012;
  };
  idOf = service: "spiffe://${trustDomain}/${host}/${service}";
  # hanko-node's files (hanko-ca.nix), group-readable by the service.
  svid = service: {
    svidFile = "/var/lib/hanko/${service}/svid.pem";
    keyFile = "/var/lib/hanko/${service}/key.pem";
    bundleFile = "/var/lib/hanko/${service}/bundle.pem";
  };
  ownerKeys = map (k: k.key) owner.sshKeys;

  # The owner's repositories on Forgejo (descriptions from koseki), imported after the first deploy.
  # CI only on kajiba itself for now.
  repos = {
    annai = "案内 — my DNS server in Zig: internal zones and resolver inside the overlay, public nameserver outside, dynamic ACME records";
    azukari = "預かり — my homelab store with typed buckets, backups first: nodes push data they encrypted, the store only adds, prunes and replicates";
    genkan = "玄関 — my Caddy-like reverse proxy in Go: TLS, routing and the front door of my homelab";
    hanko = "判子 — my certificate service: Let's Encrypt by DNS-01 through annai, internal SPIFFE identities later";
    hikyaku = "飛脚 — my node agent: scrapes metrics, reads journald, spools to disk, pushes to masu and nisshi";
    kajiba = "鍛冶場 — my own git forge: single-user, Nix-native CI, Rust server and runners, SvelteKit front";
    kanna = "鉋 — my Neovim config as a Nix flake: standalone package and Home Manager module, with a live-editable dev mode";
    kekkai = "結界 — my mesh overlay network replacing Tailscale: Rust data plane, lighthouse and relay, Go CLI";
    kiso = "基礎 — shared Nix foundation for my machines: a reusable flake module with nix-darwin, NixOS and Home Manager basics (fish, nushell, git, ssh, tmux, theme)";
    koseki = "戸籍 — registry of my repositories: Forgejo, GitHub and the push mirrors between them, in OpenTofu";
    masu = "枡 — my metric store: lossless archive of raw scrapes, a time-series engine later";
    nisshi = "日誌 — my log store: hash-chained NDJSON segments, and the common log schema";
    oroshi = "卸 — package registry for the homelab: Nix binary cache, then Go, Cargo, Hex and npm with pull-through caching";
    rirekisho = "履歴書 — my résumé (FR/EN), Astro + Svelte, data in TOML, PDF and site built with Nix";
    sekkeizu = "設計図 — my homelab blueprint: nix-darwin and NixOS hosts, services, networking and secrets in one Nix flake";
    shiori = "栞 — status line for Claude Code in Nim, configured like Starship, as a Nix flake with a Home Manager module";
  };
in
{
  flake.modules.nixos.genkan.services.genkan = {
    listeners.kajiba-ssh.address = ":${toString services.kajiba-ssh.port}";
    sites.${services.kajiba.host} = {
      backend = "http://${address}:${toString ports.http}";
      h2c = true;
    };
    # kajiba's sshd takes no PROXY header.
    passthrough.kajiba-ssh = {
      listener = "kajiba-ssh";
      backend = "${address}:${toString ports.ssh}";
    };
    passthrough.kajiba-runners = {
      listener = "services";
      sni = [ services.kajiba-runners.host ];
      backend = "${address}:${toString ports.runners}";
      # The only runner is on hashira-01; the forge checks its SPIFFE ID, not this.
      allow = [
        kekkai.nodes.${host}.ipv4
        kekkai.nodes.${host}.ipv6
      ];
    };
  };

  flake.modules.nixos.kajiba =
    { config, pkgs, ... }:
    let
      packages = inputs.scorsi-kajiba.packages.${pkgs.stdenv.hostPlatform.system};
      server = config.services.kajiba-server;
      runner = config.services.kajiba-runner;
    in
    {
      imports = [
        inputs.scorsi-kajiba.nixosModules.server
        inputs.scorsi-kajiba.nixosModules.runner
      ];

      # The module generates a host key when none is there; on the tmpfs root that would be a new one
      # at every boot. Read by sshd as root.
      sops.secrets.kajiba-ssh-host-key = {
        sopsFile = ../../secrets/${config.networking.hostName}/kajiba.yaml;
        path = "/etc/ssh/kajiba_host_ed25519_key";
        mode = "0400";
        restartUnits = [ "kajiba-sshd.service" ];
      };

      # Opened by the module on every interface (LAN included): key-only, kajiba-git only.
      services.kajiba-git = {
        package = packages.kajiba-git;
        ssh.port = ports.ssh;
      };

      services.kajiba-server = {
        enable = true;
        package = packages.kajiba-server;
        ui.package = packages.kajiba-ui;
        http = {
          listen = "${address}:${toString ports.http}";
          publicUrl = services.kajiba.url;
        };
        # Clone URLs show genkan's port, not the sshd's.
        ssh.port = services.kajiba-ssh.port;
        users.${owner.name} = {
          isAdmin = true;
          sshKeys = ownerKeys;
          signingKeys = ownerKeys;
          # The CLI's PAT on jiban; only its hash is here (the token stays in the password manager).
          tokens.cli = {
            sha256 = "fbb180ccd47001656f74341deab5fbcc38b76aba0e2f14609bf56c0784471957";
            scopes = [
              "repo:read"
              "repo:write"
              "ci:trigger"
            ];
          };
        };
        runnerListener = {
          listen = "${address}:${toString ports.runners}";
          inherit trustDomain;
        }
        // svid "kajiba-server";
        runners.${host} = {
          spiffeId = idOf "kajiba-runner";
          capabilities = {
            arch = "x86_64";
            os = "linux";
            # m75q.nix loads kvm-amd: nixosTests run on KVM.
            tags = [ "kvm" ];
            maxJobs = 1;
          };
        };
        repos = lib.mapAttrs (name: description: {
          owner = owner.name;
          inherit description;
          ciEnabled = name == "kajiba";
        }) repos;
      };

      services.kajiba-runner = {
        enable = true;
        package = packages.kajiba-runner;
        name = host;
        url = services.kajiba-runners.url;
        tags = [ "kvm" ];
        maxJobs = 1;
        tls = svid "kajiba-runner" // {
          inherit trustDomain;
          serverId = idOf "kajiba-server";
        };
      };

      # The runner asks Quad9, not annai (annai.nix), like azukari-backup.
      networking.hosts = lib.genAttrs (map (h: kekkai.nodes.${h}.ipv4) genkanHosts) (_: [
        services.kajiba-runners.host
      ]);

      sekkeizu.persist.directories =
        map
          (directory: {
            inherit directory;
            user = "kajiba-server";
            group = "kajiba-server";
            mode = "0750";
          })
          [
            server.stateDir
            server.dump.dir
          ]
        ++ [
          {
            directory = config.services.kajiba-git.stateDir;
            user = "kajiba-git";
            group = "kajiba-git";
            mode = "0750";
          }
          # Its source cache, kept to spare a full fetch after a reboot.
          {
            directory = runner.stateDir;
            user = "kajiba-runner";
            group = "kajiba-runner";
            mode = "0700";
          }
        ];

      systemd.services = {
        # Binding the kekkai address needs kekkai.nix's ip_nonlocal_bind (as in azukari.nix).
        kajiba-server = {
          after = [ "systemd-sysctl.service" ];
          unitConfig.RequiresMountsFor = [
            server.stateDir
            server.dump.dir
          ];
        };
        kajiba-git.unitConfig.RequiresMountsFor = [ config.services.kajiba-git.stateDir ];
        kajiba-runner.unitConfig.RequiresMountsFor = [ runner.stateDir ];
      };
    };
}
