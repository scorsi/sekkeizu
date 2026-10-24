# kekkai, the lab's overlay (kekkai v0.5, review gate 2 passed: kekkai ADR 0021). jiban and
# ishizue keep their direct path over vfkit's NAT bridge with static endpoints; torii-cdg, the
# public gate, is a node too and carries the lighthouse and relay (feature `kekkai-gate`) that
# every node uses. Tailscale stays until the kekkai switch (docs/migration.md, step 5).
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
  public = publicAddresses.${gate};
  ports = {
    lighthouse = 4800;
    relay = 4801;
    node = 4802;
  };

  # Each node's address on the bridge. jiban is bootpd's gateway there (also in nixos/server.nix
  # and backup/pull.nix).
  bridge = {
    jiban = "192.168.64.1";
    inherit (bridgeAddresses) ishizue;
  };
  # Static endpoints of `peer` as seen from `host`: the gate at its public addresses, the bridge
  # between jiban and ishizue. The gate has none for them: they sit behind NAT, the lighthouse
  # tells it where they are.
  endpointsOf =
    host: peer:
    if peer == gate then
      [
        "${public.ipv4}:${toString ports.node}"
        "[${public.ipv6}]:${toString ports.node}"
      ]
    else
      lib.optional (host != gate) "${bridge.${peer}}:${toString ports.node}";

  # The peers of each node and what each may open on it (kekkai ADR 0011: default deny, ICMP and
  # replies always pass). ishizue: annai uchi, SSH, genkan and Forgejo's git SSH (2222; the gate never
  # fetches from Forgejo, deploys copy closures). jiban: nothing, every flow between the two starts on
  # jiban (deploys, backup pull, hikyaku, the remote builder). The gate: SSH from jiban.
  # The gate's hikyaku pushes to masu and nisshi on ishizue (observability/stores.nix); its genkan
  # forwards the public names to ishizue's PROXY listener (8443, genkan.nix).
  allowInbound = {
    ishizue = {
      jiban = [
        "udp/53"
        "tcp/53"
        "tcp/22"
        "tcp/443"
        "tcp/2222"
      ];
      ${gate} = [
        "tcp/8443"
        "tcp/9472"
        "tcp/9473"
      ];
    };
    jiban = {
      ishizue = [ ];
      ${gate} = [ ];
    };
    ${gate} = {
      jiban = [ "tcp/22" ];
      ishizue = [ ];
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
