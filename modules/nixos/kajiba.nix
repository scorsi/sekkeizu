# kajiba, the owner's own forge (its own repo, consumed as `scorsi-kajiba`), on hashira-01 next to
# Forgejo until the switch, with a runner (feature `kajiba-runner`) on each host of `runnerHosts`.
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

  # Runner hosts and what each announces, declared on the forge under the host's name. kvm where the
  # host loads it (m75q.nix: nixosTests on KVM); ishizue is a vfkit guest, without nested KVM.
  # `ci` is the `ci.slice` envelope shared by the runner and nix-daemon (kajiba-runner below), and
  # `cores` nix's per-build cores: maxJobs × cores stays within the slice's CPUQuota.
  runnerHosts = {
    # 12 cores, 15 GB each: ~6 GB and 4 cores left to their services.
    hashira-01 = {
      arch = "x86_64";
      tags = [ "kvm" ];
      maxJobs = 2;
      cores = 4;
      ci = {
        MemoryMax = "9G";
        CPUQuota = "800%";
      };
    };
    hashira-02 = {
      arch = "x86_64";
      tags = [ "kvm" ];
      maxJobs = 2;
      cores = 4;
      ci = {
        MemoryMax = "9G";
        CPUQuota = "800%";
      };
    };
    # aarch64 CI. A nixosTest boots 2-3 VMs of ~400 MB each; on this 4 vCPU / 8 GiB VM, parallel
    # builds starve them into timeouts: one build at a time, ~3 GiB and 2 vCPUs left to its services.
    ishizue = {
      arch = "aarch64";
      tags = [ ];
      maxJobs = 1;
      cores = 2;
      ci = {
        MemoryMax = "5G";
        MemorySwapMax = "2G";
        CPUQuota = "200%";
      };
    };
  };

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
    yagura = "櫓 — my observability UI: node state, metrics and logs in one place, with views that cross signals";
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
      # The forge checks each runner's SPIFFE ID, not this. kekkai.nix already opens the `services`
      # port to every runner host.
      allow = lib.concatMap (h: [
        kekkai.nodes.${h}.ipv4
        kekkai.nodes.${h}.ipv6
      ]) (lib.attrNames runnerHosts);
    };
  };

  flake.modules.nixos.kajiba =
    { config, pkgs, ... }:
    let
      packages = inputs.scorsi-kajiba.packages.${pkgs.stdenv.hostPlatform.system};
      server = config.services.kajiba-server;
    in
    {
      imports = [ inputs.scorsi-kajiba.nixosModules.server ];

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
        runners = lib.mapAttrs (h: r: {
          spiffeId = "spiffe://${trustDomain}/${h}/kajiba-runner";
          capabilities = {
            inherit (r) arch tags maxJobs;
            os = "linux";
          };
        }) runnerHosts;
        repos = lib.mapAttrs (name: description: {
          owner = owner.name;
          inherit description;
          # Push-triggered CI only where it pays off; elsewhere `kajiba ci run --worktree` on demand.
          ci = if name == "kajiba" then "push" else "manual";
        }) repos;
      };

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
      };
    };

  # A runner of the forge, importable without it; hanko-ca.nix issues its host a `kajiba-runner` SVID.
  flake.modules.nixos.kajiba-runner =
    { config, pkgs, ... }:
    let
      host = config.networking.hostName;
      runner = config.services.kajiba-runner;
      self = runnerHosts.${host};
    in
    {
      imports = [ inputs.scorsi-kajiba.nixosModules.runner ];

      services.kajiba-runner = {
        enable = true;
        package = inputs.scorsi-kajiba.packages.${pkgs.stdenv.hostPlatform.system}.kajiba-runner;
        name = host;
        url = services.kajiba-runners.url;
        inherit (self) tags maxJobs;
        tls = svid "kajiba-runner" // {
          inherit trustDomain;
          serverId = idOf "kajiba-server";
        };
      };

      # The runner asks Quad9, not annai (annai.nix), like azukari-backup.
      networking.hosts = lib.genAttrs (map (h: kekkai.nodes.${h}.ipv4) genkanHosts) (_: [
        services.kajiba-runners.host
      ]);

      # Its source cache, kept to spare a full fetch after a reboot.
      sekkeizu.persist.directories = [
        {
          directory = runner.stateDir;
          user = "kajiba-runner";
          group = "kajiba-runner";
          mode = "0700";
        }
      ];
      systemd.services.kajiba-runner.unitConfig.RequiresMountsFor = [ runner.stateDir ];

      nix.settings = {
        max-jobs = self.maxJobs;
        inherit (self) cores;
      };

      # Builds run under nix-daemon, outside the runner's cgroup, and the runner evaluates in its own
      # process: one budget for both, manual daemon builds included. No MemoryHigh: past it,
      # unswappable memory throttles forever; a breach must OOM-kill, visibly.
      systemd.slices.ci.sliceConfig = self.ci;
      systemd.services.nix-daemon.serviceConfig.Slice = "ci.slice";
      systemd.services.kajiba-runner.serviceConfig.Slice = "ci.slice";
    };
}
