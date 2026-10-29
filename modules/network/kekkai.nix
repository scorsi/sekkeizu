# kekkai, the lab's overlay (kekkai v0.5, review gate 2 passed: kekkai ADR 0021). jiban and
# ishizue keep their direct path over vfkit's NAT bridge with static endpoints; torii-cdg, the
# public gate, is a node too and carries the lighthouse and relay (feature `kekkai-gate`) that
# every node uses.
# Keys: secrets/<host>/kekkai.yaml (private), sekkeizu.kekkai.nodes.<host>.publicKey, and the
# lighthouse's and relay's own keys in sekkeizu.kekkai (kekkai ADR 0005, 0017).
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) bridgeAddresses kekkai publicAddresses;
  inherit (config.kiso) owner;

  gate = "torii-cdg";
  hashira = [
    "hashira-01"
    "hashira-02"
  ];
  public = publicAddresses.${gate};
  ports = {
    lighthouse = 4800;
    relay = 4801;
    node = 4802;
  };

  # Each node's address on the bridge. jiban is bootpd's gateway there (also in nixos/server.nix).
  bridge = {
    jiban = "192.168.64.1";
    inherit (bridgeAddresses) ishizue;
  };
  # Static endpoints of `peer` as seen from `host`: the gate at its public addresses, the bridge
  # between jiban and ishizue. None for the others: they sit behind NAT (the hashira on the home
  # LAN's DHCP, no fixed address), the lighthouse tells their peers where they are.
  endpointsOf =
    host: peer:
    if peer == gate then
      [
        "${public.ipv4}:${toString ports.node}"
        "[${public.ipv6}]:${toString ports.node}"
      ]
    else
      lib.optional (bridge ? ${host} && bridge ? ${peer}) "${bridge.${peer}}:${toString ports.node}";

  # The peers of each node and what each may open on it (kekkai ADR 0011: default deny, ICMP and
  # replies always pass). ishizue: annai uchi and SSH from jiban, Forgejo's HTTP and SSH ports from
  # genkan's node. jiban: nothing, every flow between the two starts on jiban (deploys,
  # hikyaku, the remote builder). The gate: SSH from jiban. The hashira: SSH from jiban (deploys);
  # every node's hikyaku pushes to masu and nisshi on hashira-01 (observability/masu.nix, nisshi.nix);
  # hashira-02 runs genkan: the web port and Forgejo's git SSH (2222) for jiban and ishizue's runner,
  # the PROXY listener (8443, genkan.nix) for the gate's genkan.
  stores = [
    "tcp/9472"
    "tcp/9473"
  ];
  # azukari's store (backup/azukari.nix), for the nodes that back up to it.
  azukari = [ "tcp/5000" ];
  web = [
    "tcp/443"
    "tcp/2222"
  ];
  allowInbound = {
    ishizue = {
      jiban = [
        "udp/53"
        "tcp/53"
        "tcp/22"
      ];
      ${gate} = [ ];
      # hanko-ca (hanko-ca.nix): the hosts it issues SVIDs to.
      hashira-01 = [ "tcp/4900" ];
      hashira-02 = [
        "tcp/3000"
        "tcp/2222"
        "tcp/4900"
      ];
    };
    jiban = {
      ishizue = [ ];
      ${gate} = [ ];
    }
    // lib.genAttrs hashira (_: [ ]);
    ${gate} = {
      jiban = [ "tcp/22" ];
      ishizue = [ ];
    }
    // lib.genAttrs hashira (_: [ ]);
    hashira-01 = {
      jiban = [ "tcp/22" ] ++ stores;
      ishizue = stores ++ azukari;
      ${gate} = stores;
      hashira-02 = stores ++ azukari;
    };
    hashira-02 = {
      jiban = [ "tcp/22" ] ++ web;
      ishizue = web;
      ${gate} = [ "tcp/8443" ];
      # Its Forgejo runner reaches Forgejo through genkan (HTTPS and the SSH passthrough).
      hashira-01 = web;
    };
  };

  # The lighthouse's and relay's peer list: every node with a key.
  servicePeers = lib.mapAttrs (_: n: { inherit (n) publicKey; }) (
    lib.filterAttrs (_: n: n.publicKey != null) kekkai.nodes
  );

  node =
    platform:
    { config, pkgs, ... }:
    let
      host = config.networking.hostName;
      self = kekkai.nodes.${host};
      packages = inputs.scorsi-kekkai.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      imports = [ inputs.scorsi-kekkai.${platform}.node ];

      sops.secrets.kekkai-key.sopsFile = ../../secrets/${host}/kekkai.yaml;

      services.kekkai-node = {
        enable = true;
        # kekkai's own builds, tested against its own nixpkgs, rather than its overlay on ours.
        package = packages.kekkai-node;
        cliPackage = packages.kekkai;
        privateKeyFile = config.sops.secrets.kekkai-key.path;
        addresses = [
          "${self.ipv4}/32"
          "${self.ipv6}/128"
        ];
        peers = lib.mapAttrs (name: rules: {
          inherit (kekkai.nodes.${name}) publicKey;
          addresses = [
            "${kekkai.nodes.${name}.ipv4}/32"
            "${kekkai.nodes.${name}.ipv6}/128"
          ];
          endpoints = endpointsOf host name;
          allowInbound = rules;
        }) allowInbound.${host};
        # One endpoint each in v0: IPv4, which every node reaches (ishizue is behind vfkit's IPv4 NAT).
        # The gate's own node uses them too: from the host's public address, so the lighthouse
        # hands out that address rather than loopback.
        lighthouses = [
          {
            publicKey = kekkai.lighthousePublicKey;
            endpoint = "${public.ipv4}:${toString ports.lighthouse}";
          }
        ];
        relays = [
          {
            publicKey = kekkai.relayPublicKey;
            endpoint = "${public.ipv4}:${toString ports.relay}";
          }
        ];
        # Scraped by the local hikyaku only (masu metric convention: loopback).
        metrics.listen = "127.0.0.1:9480";
        # `kekkai status --json` without sudo.
        operators = [ owner.name ];
      };
    };
in
{
  flake.modules.nixos.kekkai =
    { config, lib, ... }:
    let
      address = bridge.${config.networking.hostName} or null;
    in
    {
      imports = [ (node "nixosModules") ];

      # The daemon runs as its static user (kekkai ADR 0018); sops-nix's default mode is 0400.
      sops.secrets.kekkai-key = {
        owner = "kekkai";
        restartUnits = [ "kekkai-node.service" ];
      };

      # kekkai's per-peer filter is the only one on the overlay (docs/migration.md, "not both"):
      # allowInbound above is the single place a port opens to a peer.
      networking.firewall.trustedInterfaces = [ "kekkai0" ];
      # kekkai0 and its address exist only while kekkai-node runs (a non-persistent TUN): services
      # listening on that address (genkan, masu, nisshi) must bind it whether or not it is up, and
      # serve it whenever it is (re)added.
      boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
      # The tunnel's UDP port: on the bridge address only (like annai's port 53) on a VM, on every
      # interface of a public host (Vultr's firewall, infra/stacks/torii, opens the same port).
      networking.firewall.extraCommands = lib.mkIf (address != null) ''
        iptables -A nixos-fw -d ${address} -p udp --dport ${toString ports.node} -j nixos-fw-accept
      '';
      networking.firewall.allowedUDPPorts = lib.mkIf (address == null) [ ports.node ];
    };

  flake.modules.darwin.kekkai =
    { config, ... }:
    {
      imports = [ (node "darwinModules") ];
      # Record the ciphertext fingerprint only after the daemon has restarted with the installed secret.
      system.activationScripts.kekkai-secrets.text = ''
        if [ "$(cat /var/db/kekkai-node.secrets 2>/dev/null)" != "${config.sops.secrets.kekkai-key.sopsFileHash}" ]; then
          /bin/launchctl kickstart -k system/${config.launchd.daemons.kekkai-node.serviceConfig.Label}
          printf '%s\n' '${config.sops.secrets.kekkai-key.sopsFileHash}' > /var/db/kekkai-node.secrets
        fi
      '';
      system.activationScripts.postActivation.text = lib.mkOrder 1650 config.system.activationScripts.kekkai-secrets.text;
    };

  # The lighthouse and relay, on the gate (kekkai ADR 0012, 0014): they list every node.
  flake.modules.nixos.kekkai-gate =
    { config, pkgs, ... }:
    let
      packages = inputs.scorsi-kekkai.packages.${pkgs.stdenv.hostPlatform.system};
      secret = name: {
        sopsFile = ../../secrets/${config.networking.hostName}/kekkai.yaml;
        owner = name;
        restartUnits = [ "${name}.service" ];
      };
    in
    {
      imports = with inputs.scorsi-kekkai.nixosModules; [
        lighthouse
        relay
      ];

      sops.secrets.kekkai-lighthouse-key = secret "kekkai-lighthouse";
      sops.secrets.kekkai-relay-key = secret "kekkai-relay";

      services.kekkai-lighthouse = {
        enable = true;
        package = packages.kekkai-lighthouse;
        cliPackage = packages.kekkai;
        privateKeyFile = config.sops.secrets.kekkai-lighthouse-key.path;
        peers = servicePeers;
        operators = [ owner.name ];
      };

      services.kekkai-relay = {
        enable = true;
        package = packages.kekkai-relay;
        cliPackage = packages.kekkai;
        privateKeyFile = config.sops.secrets.kekkai-relay-key.path;
        # No per-sender limit (maxBytesPerSecond) while every listed node is the owner's own;
        # reconsider when a node outside that circle (a phone, a guest) joins (kekkai ADR 0031).
        peers = servicePeers;
        operators = [ owner.name ];
      };

      # Vultr's firewall (infra/stacks/torii) opens the same ports.
      networking.firewall.allowedUDPPorts = [
        ports.lighthouse
        ports.relay
      ];
    };
}
