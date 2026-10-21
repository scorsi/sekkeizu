# kekkai, the lab's overlay (kekkai milestone v0.3, review gate 1): jiban and ishizue linked over
# vfkit's NAT bridge with static endpoints. torii joins with the lighthouse and relay (v0.4, v0.5,
# gate 2); until then Tailscale keeps carrying everything that is not on this table.
# Keys: secrets/<host>/kekkai.yaml (private), sekkeizu.kekkai.nodes.<host>.publicKey (kekkai ADR 0017).
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) bridgeAddresses kekkai;
  inherit (config.kiso) owner;

  # Each node's address on the bridge. jiban is bootpd's gateway there (also in nixos/server.nix
  # and backup/pull.nix).
  endpoints = {
    jiban = "192.168.64.1";
    inherit (bridgeAddresses) ishizue;
  };
  port = 4802;

  # The peers of each node and what each may open on it (kekkai ADR 0011: default deny, ICMP and
  # replies always pass). ishizue: annai uchi and SSH. jiban: nothing, every flow between the two
  # starts on jiban (deploys, backup pull, hikyaku, the remote builder).
  allowInbound = {
    ishizue.jiban = [
      "udp/53"
      "tcp/53"
      "tcp/22"
    ];
    jiban.ishizue = [ ];
  };

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
          endpoints = [ "${endpoints.${name}}:${toString port}" ];
          allowInbound = rules;
        }) allowInbound.${host};
        # Scraped by the local hikyaku only (masu metric convention: loopback).
        metrics.listen = "127.0.0.1:9480";
        # `kekkai status --json` without sudo.
        operators = [ owner.name ];
      };
    };
in
{
  flake.modules.nixos.kekkai =
    { config, ... }:
    let
      address = endpoints.${config.networking.hostName};
    in
    {
      imports = [ (node "nixosModules") ];

      # The daemon runs as its static user (kekkai ADR 0018); sops-nix's default mode is 0400.
      sops.secrets.kekkai-key.owner = "kekkai";

      # kekkai's per-peer filter is the only one on the overlay (docs/migration.md, "not both"):
      # allowInbound above is the single place a port opens to a peer.
      networking.firewall.trustedInterfaces = [ "kekkai0" ];
      # The tunnel's UDP port, on the bridge address only (like annai's port 53).
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -d ${address} -p udp --dport ${toString port} -j nixos-fw-accept
      '';
    };

  flake.modules.darwin.kekkai.imports = [ (node "darwinModules") ];
}
