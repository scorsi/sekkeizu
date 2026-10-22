# Runs NixOS VMs (nixosConfigurations built on the vfkit-guest feature) on the Mac with vfkit, one
# LaunchAgent each in the owner's GUI session, which opens by itself at boot
# (modules/macos/autologin.nix). Not a LaunchDaemon: tried, it starts before login fine, but at
# macOS shutdown Virtualization.framework fails the stop request ("hypervisor virtualization
# error") and the guest is cut off like in a power cut; the agent gets a clean poweroff at logout.
#
# Each VM's state lives in ~/.local/state/vm/<name>:
#   disk.raw     the VM's disk (sparse), written once by `nix run .#install-<name>`
#   efi-vars     EFI variable store (boot order, systemd-boot one-shot entries); recreated empty
#                if missing, the VM still boots through the removable-media path
#   console.log  guest console (hvc0), vfkit.log: vfkit itself; 3 previous starts kept as .1-.3
#   vm.sock      vfkit's REST control socket
# Updates go through the guest's own nixos-rebuild (`nix run .#deploy-<name>`), never through here.
{ config, lib, ... }:
let
  owner = config.kiso.owner.name;
  inherit (config.sekkeizu) bridgeAddresses;
  home = "/Users/${owner}";

  # Short on purpose: the control socket lives here, and macOS caps socket paths at 104 bytes.
  stateDir = name: "${home}/.local/state/vm/${name}";
  agentName = name: "vm-${name}";
  # nix-darwin's default label for launchd.user.agents.<name>.
  label = name: "org.nixos.${agentName name}";

  vmOptions = {
    options = with lib; {
      vcpu = mkOption {
        type = types.ints.positive;
        description = "Virtual CPUs.";
      };
      memory = mkOption {
        type = types.ints.positive;
        description = "RAM, in MiB. Allocated lazily by Virtualization.framework, but never given back.";
      };
      diskSize = mkOption {
        type = types.ints.positive;
        description = "Disk size, in GiB (sparse: only what the guest writes takes space). Applied by install-<vm>.";
      };
      mac = mkOption {
        type = types.strMatching "([0-9a-f]{2}:){5}[0-9a-f]{2}";
        description = "NIC MAC address, paired with bridgeAddresses in macOS's static DHCP bindings.";
      };
    };
  };

  # Compiled, so no interpreter is needed at runtime. The store file name isn't a valid Nim module
  # name, hence the copy.
  nimProgram =
    pkgs: name: flags:
    pkgs.stdenv.mkDerivation {
      inherit name;
      src = ./${name}.nim;
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.nim ];
      buildPhase = "cp $src main.nim && nim c -d:release ${flags} --nimcache:$TMPDIR/nimcache -o:${name} main.nim";
      installPhase = "install -D ${name} $out/bin/${name}";
    };

  # VMs declared by any darwin host: the apps below are generated for each.
  declaredVms = lib.foldl' (acc: host: acc // (host.config.sekkeizu.vms or { })) { } (
    lib.attrValues config.flake.darwinConfigurations
  );
in
{
  flake.modules.darwin.vfkit-host =
    { config, pkgs, ... }:
    {
      options.sekkeizu.vms = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule vmOptions);
        default = { };
        description = "VMs to run on this Mac, named after their nixosConfigurations (built on the vfkit-guest feature).";
      };

      # bootpd checks these static bindings before its volatile lease database. A MAC alone
      # only preserves an existing lease; /etc/bootptab also survives a fresh Mac installation.
      config.environment.etc.bootptab.text = ''
        %%
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: vm: "${name} 1 ${vm.mac} ${bridgeAddresses.${name}} boot"
          ) config.sekkeizu.vms
        )}
      '';
      config.assertions = [
        {
          assertion = lib.all (name: builtins.hasAttr name bridgeAddresses) (
            builtins.attrNames config.sekkeizu.vms
          );
          message = "Each vfkit VM needs a sekkeizu.bridgeAddresses entry for its DHCP reservation.";
        }
        {
          assertion =
            let
              addresses = map (name: bridgeAddresses.${name}) (builtins.attrNames config.sekkeizu.vms);
            in
            lib.length addresses == lib.length (lib.unique addresses);
          message = "vfkit DHCP reservations must have distinct IPv4 addresses.";
        }
      ];

      config.launchd.user.agents = lib.mapAttrs' (
        name: vm:
        lib.nameValuePair (agentName name) {
          # Waits for /nix/store (see forgejo-runner.nix); `exec` keeps launchd's SIGTERM on vfkit.
          command = lib.escapeShellArgs [
            "${nimProgram pkgs "vm-start" ""}/bin/vm-start"
            (stateDir name)
            name
            "${pkgs.vfkit}/bin/vfkit"
            (toString vm.vcpu)
            (toString vm.memory)
            vm.mac
          ];
          serviceConfig = {
            RunAtLoad = true;
            # A clean stop (guest poweroff) stays stopped; a crash is restarted.
            KeepAlive.SuccessfulExit = false;
            # Not throttled like a background job: it's a whole machine.
            ProcessType = "Interactive";
            # launchd's SIGTERM makes vfkit power the guest off cleanly (a few seconds).
            ExitTimeOut = 60;
          };
        }
      ) config.sekkeizu.vms;
    };

  perSystem =
    { pkgs, system, ... }:
    let
      restoreIdentity = "${
        nimProgram pkgs "restore-vm-identity" (
          lib.escapeShellArgs [
            "-d:sops=${pkgs.sops}/bin/sops"
            "-d:sgdisk=${pkgs.gptfdisk}/bin/sgdisk"
            "-d:debugfs=${pkgs.e2fsprogs}/bin/debugfs"
          ]
        )
      }/bin/restore-vm-identity";
    in
    lib.optionalAttrs (system == "aarch64-darwin") {
      apps = lib.concatMapAttrs (name: vm: {
        "install-${name}" = {
          type = "app";
          program = toString (
            pkgs.writers.writeNu "install-${name}" ''
              def die [msg: string] {
                print --stderr $"install-${name}: ($msg)"
                exit 1
              }

              def running [agent: string] {
                ^launchctl print $agent | complete | get stdout | str contains "state = running"
              }

              # --force: overwrites an existing disk, every byte of the VM's data with it.
              def main [--force] {
                let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
                let state = "${stateDir name}"
                let agent = $"gui/(^id -u | str trim)/${label name}"
                let identity = $"($repo)/secrets/${name}/identity.yaml"

                if (^launchctl print $agent | complete).exit_code != 0 {
                  die "agent ${label name} missing: declare sekkeizu.vms.${name} on this host, then switch"
                }
                if ($"($state)/disk.raw" | path exists) and not $force {
                  die $"($state)/disk.raw already exists. --force overwrites it: all of the VM's data is lost"
                }
                if not ("/etc/nix/machines" | path exists) or not (open --raw /etc/nix/machines | str contains aarch64-linux) {
                  die $"no aarch64-linux builder: uncomment darwin.linux-builder in modules/hosts/(^/bin/hostname -s | str trim).nix, switch, then retry"
                }

                let img = ^nix build $"($repo)#nixosConfigurations.${name}.config.system.build.vfkitImage" --no-link --print-out-paths | str trim

                if (running $agent) {
                  print "Stopping ${name}…"
                  ^launchctl kill SIGTERM $agent
                  while (running $agent) { sleep 1sec }
                }

                mkdir $state
                # The image is fully allocated in the store; copy it sparse, then grow it (sparse too).
                ^${pkgs.coreutils}/bin/cp --sparse=always $"($img)/nixos.img" $"($state)/disk.raw.new"
                ^chmod u+w $"($state)/disk.raw.new"
                ^${pkgs.coreutils}/bin/truncate -s ${toString vm.diskSize}G $"($state)/disk.raw.new"
                if ($identity | path exists) {
                  ^${restoreIdentity} $"($state)/disk.raw.new" $identity
                }
                mv --force $"($state)/disk.raw.new" $"($state)/disk.raw"
                # Boot entries of the previous disk mean nothing for this one.
                rm --force $"($state)/efi-vars"
                # Several GB, and rebuilt on demand anyway.
                ^nix store delete $img | complete | ignore

                ^launchctl kickstart $agent
                if ($identity | path exists) {
                  print "${name} installed and started, with its identity (SSH host key, Tailscale node)."
                } else {
                  print "${name} installed and started (first boot: partition grown, new SSH host key)."
                }
                print "Next: README, section ${name}."
              }
            ''
          );
        };

        "deploy-${name}" = {
          type = "app";
          program = toString (
            pkgs.writers.writeNu "deploy-${name}" ''
              ${builtins.readFile ../flake/nixos-deploy.nu}
              def --wrapped main [...args] {
                $env.PATH = $env.PATH | prepend ${pkgs.nixos-rebuild}/bin
                let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
                # <vm>.local (mDNS over the NAT bridge) rather than Tailscale, which hairpins through
                # the router from the Mac. Built inside the VM, activated in a detached unit. Same root@
                # user for build and target so both share one ControlMaster connection
                # (modules/home/ssh-hosts.nix): one FIDO2 touch.
                deploy root@${name}.local $"($repo)#${name}" ...$args
              }
            ''
          );
        };
      }) declaredVms;
    };
}
