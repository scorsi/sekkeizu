# hanko's internal identities (hanko ADR 0004): hanko-ca on ishizue signs 24 h X.509-SVIDs for the
# services below, attested by the caller's kekkai address; hanko-node on each host keeps them in
# /var/lib/hanko/<service>/. Consumers watch their files and reload in-process (hanko ADR 0013):
# hanko reloads nothing. The CA key is in ishizue's sops file, the CA certificate (public) here.
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) domain kekkai;
  trustDomain = "uchi.${domain}";
  caHost = "ishizue";
  port = 4900;

  # host -> service -> group that reads the SVID (the unit's own static group, azukari ADR 0020).
  # azukari-backup runs on every host with an export under /persist/backups: Forgejo on ishizue,
  # masu and nisshi on hashira-01, hanko's ACME account on hashira-02. kajiba's forge and its
  # runner authenticate each other with theirs (nixos/kajiba.nix, kajiba ADR 0124).
  services = {
    ishizue.azukari-backup = "azukari-backup";
    hashira-01 = {
      azukari-server = "azukari";
      azukari-backup = "azukari-backup";
      kajiba-server = "kajiba-server";
      kajiba-runner = "kajiba-runner";
    };
    hashira-02.azukari-backup = "azukari-backup";
  };
  idOf = host: service: "spiffe://${trustDomain}/${host}/${service}";
in
{
  flake.modules.nixos.hanko-ca =
    { config, lib, ... }:
    {
      imports = [ inputs.scorsi-hanko.nixosModules.ca ];

      sops.secrets.hanko-ca-key = {
        owner = "hanko-ca";
        mode = "0400";
        restartUnits = [ "hanko-ca.service" ];
      };
      environment.etc."hanko/ca.pem".source = ./hanko-ca.pem;

      services.hanko-ca = {
        enable = true;
        keyFile = config.sops.secrets.hanko-ca-key.path;
        certFile = "/etc/hanko/ca.pem";
        listen = "${kekkai.nodes.${caHost}.ipv4}:${toString port}";
        hosts = lib.mapAttrs' (
          host: svcs: lib.nameValuePair kekkai.nodes.${host}.ipv4 (map (idOf host) (lib.attrNames svcs))
        ) services;
      };
      # kekkai.nix opens tcp/4900 on ishizue to every other host listed in `services`; ishizue's own
      # hanko-node reaches it over loopback, which the firewall does not filter.
    };

  flake.modules.nixos.hanko-internal =
    { config, lib, ... }:
    let
      host = config.networking.hostName;
    in
    {
      # Same key as in hanko.nix: one import on hosts running both.
      imports = [
        {
          key = "scorsi-hanko/node";
          imports = [ inputs.scorsi-hanko.nixosModules.default ];
        }
      ];

      services.hanko-node = {
        enable = true;
        internal.ca = "${kekkai.nodes.${caHost}.ipv4}:${toString port}";
        certificates = lib.mapAttrs (service: group: {
          issuer = "internal";
          spiffeId = idOf host service;
          inherit group;
        }) services.${host};
      };

      # The consumers' groups exist before their services are deployed: hanko's module creates the
      # SVID directories with them but declares none (azukari's modules declare the same, empty).
      users.groups = lib.genAttrs (lib.attrValues services.${host}) (_: { });
    };

}
