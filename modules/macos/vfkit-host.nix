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
        description = "NIC MAC address: macOS's DHCP server keys the VM's NAT address on it.";
      };
    };
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

      config.launchd.user.agents = lib.mapAttrs' (
        name: vm:
        lib.nameValuePair (agentName name) {
          serviceConfig = {
            ProgramArguments = [
              "${pkgs.writeShellScript "vm-${name}-start" ''
                set -euo pipefail
                state=${stateDir name}
                mkdir -p "$state"
                cd "$state"

                # vfkit never reopens its files (and Virtualization.framework rewrites the console
                # from the start), so newsyslog can't rotate them live: rotate at each start instead.
                # Empty files are skipped, so a crash loop doesn't push the useful logs out.
                for f in vfkit.log console.log; do
                  [ -s "$f" ] || continue
                  for i in 2 1; do [ -f "$f.$i" ] && mv -f "$f.$i" "$f.$((i + 1))"; done
                  mv -f "$f" "$f.1"
                done
                exec >>vfkit.log 2>&1

                if [ ! -f disk.raw ]; then
                  echo "$(date '+%F %T') pas de disque : nix run .#install-${name}"
                  exit 0
                fi

                # Left behind by a power cut: vfkit won't bind over it (launchd runs one instance).
                rm -f vm.sock
                create=
                [ -e efi-vars ] || create=,create
                exec ${pkgs.vfkit}/bin/vfkit \
                  --cpus ${toString vm.vcpu} --memory ${toString vm.memory} \
                  --bootloader "efi,variable-store=$state/efi-vars$create" \
                  --device virtio-rng \
                  --device "virtio-blk,path=$state/disk.raw" \
                  --device virtio-net,nat,mac=${vm.mac} \
                  --device "virtio-serial,logFilePath=$state/console.log" \
                  --restful-uri "unix://$state/vm.sock"
              ''}"
            ];
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
      # A VM keeps the same identity across reinstalls when secrets/<vm>/identity.yaml exists (sops,
      # admin key): SSH host key (so no re-key of secrets/<vm>/) and Tailscale state (same node, same
      # IP). macOS can't mount ext4, so the files are written into the fresh image offline, with
      # debugfs, before its first boot. Decrypted only into a private temporary directory, removed
      # on exit. Usage: restore-vm-identity <disk.raw> <identity.yaml>
      restoreIdentity = pkgs.writeShellScript "restore-vm-identity" ''
        set -euo pipefail
        disk=$1 identity=$2
        export SOPS_AGE_KEY_FILE=''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
        umask 077
        seed=$(mktemp -d)
        trap 'rm -rf "$seed"' EXIT
        for k in ssh_host_ed25519_key ssh_host_ed25519_key_pub tailscaled_state; do
          ${pkgs.sops}/bin/sops -d --extract "[\"$k\"]" "$identity" > "$seed/$k"
        done

        # make-disk-image's "efi" layout: partition 1 is the ESP, 2 the ext4 disk (/persist).
        first=$(${pkgs.gptfdisk}/bin/sgdisk -i 2 "$disk" | ${pkgs.gawk}/bin/awk '/^First sector:/ { print $3 }')
        fs="$disk?offset=$((first * 512))"
        debugfs=${pkgs.e2fsprogs}/bin/debugfs

        # Paths are relative to /persist. Errors on mkdir (already there) and rm (not there) are
        # expected; what counts is checked right after.
        "$debugfs" -w -f - "$fs" >/dev/null 2>&1 <<EOF || true
        mkdir /etc
        mkdir /etc/ssh
        mkdir /var
        mkdir /var/lib
        mkdir /var/lib/tailscale
        rm /etc/ssh/ssh_host_ed25519_key
        rm /etc/ssh/ssh_host_ed25519_key.pub
        rm /var/lib/tailscale/tailscaled.state
        write $seed/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
        write $seed/ssh_host_ed25519_key_pub /etc/ssh/ssh_host_ed25519_key.pub
        write $seed/tailscaled_state /var/lib/tailscale/tailscaled.state
        sif /etc mode 040755
        sif /etc/ssh mode 040755
        sif /var mode 040755
        sif /var/lib mode 040755
        sif /var/lib/tailscale mode 040700
        sif /etc/ssh/ssh_host_ed25519_key mode 0100600
        sif /etc/ssh/ssh_host_ed25519_key.pub mode 0100644
        sif /var/lib/tailscale/tailscaled.state mode 0100600
        $(for f in /etc /etc/ssh /var /var/lib /var/lib/tailscale /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub /var/lib/tailscale/tailscaled.state; do
          printf 'sif %s uid 0\nsif %s gid 0\n' "$f" "$f"
        done)
        EOF

        # debugfs exits 0 even when a command fails: read every file back.
        for f in ssh_host_ed25519_key:/etc/ssh/ssh_host_ed25519_key ssh_host_ed25519_key_pub:/etc/ssh/ssh_host_ed25519_key.pub tailscaled_state:/var/lib/tailscale/tailscaled.state; do
          "$debugfs" -R "cat ''${f#*:}" "$fs" 2>/dev/null | cmp -s - "$seed/''${f%%:*}" ||
            { echo "restore-vm-identity : ''${f#*:} mal écrit dans l'image" >&2; exit 1; }
        done
        echo "identité restaurée dans l'image (clé hôte SSH, état Tailscale)"
      '';
    in
    lib.optionalAttrs (system == "aarch64-darwin") {
      apps = lib.concatMapAttrs (name: vm: {
        "install-${name}" = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "install-${name}" ''
              set -euo pipefail
              die() { echo "install-${name}: $*" >&2; exit 1; }
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              state=${stateDir name}
              agent=gui/$(id -u)/${label name}

              force=no
              case "''${1:-}" in
                "") ;;
                --force) force=yes ;;
                *) die "usage : nix run .#install-${name} [-- --force]" ;;
              esac

              launchctl print "$agent" >/dev/null 2>&1 ||
                die "agent ${label name} absent : déclare sekkeizu.vms.${name} sur cet hôte, puis switch"
              if [ -e "$state/disk.raw" ] && [ "$force" = no ]; then
                die "$state/disk.raw existe déjà. --force l'écrase : toutes les données de la VM sont perdues"
              fi
              grep -qs aarch64-linux /etc/nix/machines ||
                die "aucun builder aarch64-linux : décommente darwin.linux-builder dans modules/hosts/$(/bin/hostname -s).nix, switch, puis relance"

              img=$(nix build "$repo#nixosConfigurations.${name}.config.system.build.vfkitImage" --no-link --print-out-paths)

              if launchctl print "$agent" | grep -q 'state = running'; then
                echo "Arrêt de ${name}…"
                launchctl kill SIGTERM "$agent"
                while launchctl print "$agent" | grep -q 'state = running'; do sleep 1; done
              fi

              mkdir -p "$state"
              # The image is fully allocated in the store; copy it sparse, then grow it (sparse too).
              ${pkgs.coreutils}/bin/cp --sparse=always "$img/nixos.img" "$state/disk.raw.new"
              chmod u+w "$state/disk.raw.new"
              ${pkgs.coreutils}/bin/truncate -s ${toString vm.diskSize}G "$state/disk.raw.new"
              if [ -f "$repo/secrets/${name}/identity.yaml" ]; then
                ${restoreIdentity} "$state/disk.raw.new" "$repo/secrets/${name}/identity.yaml"
              fi
              mv -f "$state/disk.raw.new" "$state/disk.raw"
              # Boot entries of the previous disk mean nothing for this one.
              rm -f "$state/efi-vars"
              # Several GB, and rebuilt on demand anyway.
              nix store delete "$img" >/dev/null 2>&1 || true

              launchctl kickstart "$agent"
              if [ -f "$repo/secrets/${name}/identity.yaml" ]; then
                echo "${name} installé et démarré, avec son identité (clé hôte SSH, nœud Tailscale)."
              else
                echo "${name} installé et démarré (premier boot : partition agrandie, nouvelle clé hôte SSH)."
              fi
              echo "Suite : README, section ${name}."
            ''
          );
        };

        "deploy-${name}" = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "deploy-${name}" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              # <vm>.local (mDNS over the NAT bridge) rather than Tailscale, which hairpins through
              # the router from the Mac. Built inside the VM. Same root@ user for build and target so
              # both share one ControlMaster connection (modules/home/ssh.nix): one FIDO2 touch.
              exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
                --flake "$repo#${name}" \
                --build-host root@${name}.local --target-host root@${name}.local "$@"
            ''
          );
        };
      }) declaredVms;
    };
}
