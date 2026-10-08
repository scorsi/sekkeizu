# sekkeizu (設計図)

Personal Nix flake for all my machines, built with [flake-parts](https://flake.parts/) and the
[dendritic pattern](https://github.com/mightyiam/dendritic): every feature lives in its own file
under `modules/`, and contributes to as many of `darwin` / `nixos` / `homeManager` as it needs.

## Hosts

| Host      | Machine               | OS             |
| --------- | ---------------------- | -------------- |
| `jiban`   | Mac Mini M4             | macOS (nix-darwin) |
| `ishizue` | NixOS VM on jiban (vfkit) | NixOS |

## Layout

```
modules/
  meta/    flake-level options (config.sekkeizu.*) and the one identity file to edit (owner.nix)
  base/    cross-cutting system setup: Nix itself, home-manager wiring, the primary user account
  home/    home-manager features (fish, git, ssh, tmux, neovim, theme, cli tools…)
  macos/   nix-darwin-only features (macOS defaults, Homebrew, VM host)
  nixos/   NixOS-only features (server)
  vm/      NixOS guest base for VMs on a Mac (vfkit, EFI)
  flake/   flake plumbing (supported systems, dev shell, apps, the darwinConfigurations option)
  hosts/   one file per machine: its identity + the features it imports
scripts/
  bootstrap.sh   turns a fresh Mac into a working jiban
files/nvim/      Neovim config, a separate git submodule (github.com/scorsi/nvim)
```

A feature file declares `flake.modules.<class>.<name>`; a host file just lists the names it wants.
Adding a feature never requires touching an existing file.

## Usage

```bash
nix run .#switch   # rebuild + diff against the current generation (sudo prompt included)
nix run .#check     # nix flake check
nix run .#fmt       # nix fmt (nixfmt-tree)
nix run .#rekey-host <host>  # new SSH host key (reinstall): update .sops.yaml + re-encrypt secrets/<host>/
nix run .#install-ishizue    # on jiban: build ishizue's disk image and start it (once)
nix run .#deploy-ishizue     # nixos-rebuild switch to ishizue, built inside the VM
nix develop          # shell with nixfmt, statix, deadnix, shellcheck, just, nvd
```

## Reinstalling a Mac from scratch

Steps in execution order. Everything not listed here is declarative and comes back with the
switch. Repo and nvim submodule are private (SSH over FIDO2 key), so the bootstrap script cannot be
fetched with `curl` from GitHub: bring `scripts/bootstrap.sh` over (AirDrop, `scp`, USB stick).

1. **Before wiping**: everything pushed (`sekkeizu` and `files/nvim`), and the sops admin key
   (`~/.config/sops/age/keys.txt`) is in the password manager.
2. **Erase All Content and Settings**, then in Setup Assistant: create the account with the name set
   in `modules/meta/owner.nix`, and **turn FileVault off** when the assistant offers it (with
   FileVault on, macOS ignores `/etc/kcpassword` and the headless boot stops at the unlock screen).
3. **Bootstrap**, with the first FIDO2 key plugged in:
   ```bash
   bash bootstrap.sh --repo git@github.com:scorsi/sekkeizu.git
   ```
   It installs the Command Line Tools and Nix, pulls the key handle (`ssh-keygen -K`: PIN, then touch),
   clones with submodules and runs the first switch. That switch can complain that sops cannot
   decrypt `kcpassword`: expected, the host key is new (step 8 fixes it).
4. **One `ssh-keygen -K` per additional key**: plug the next FIDO2 key, then
   `cd ~/.ssh && ssh-keygen -K` (the bootstrap only handled the first one).
5. **Screen Sharing**: System Settings → General → Sharing → Screen Sharing on (not declarative).
   Remote Login (sshd) is declared.
6. **Tailscale**: `sudo tailscale up`, then in the admin console disable key expiry for the machine.
7. **Admin age key**: restore `~/.config/sops/age/keys.txt` from the password manager (on the machine
   where step 8 runs; `jiban` itself is fine).
8. **Re-key**: the reinstall generated a new SSH host key, so the old age recipient is dead.
   `nix run .#rekey-host jiban`, then commit and push `.sops.yaml` and `secrets/jiban/`
   (pull them on jiban if it ran elsewhere).
9. **Second switch**: `nix run .#switch` (or `drs`): the secrets now decrypt and `/etc/kcpassword` is installed.
10. **Immediate screen lock**: `sysadminctl -screenLock immediate -password -` (type the account
    password when prompted). The `askForPassword` default alone is not honoured by recent macOS, and
    the command needs the password, so it cannot be declared. Check with `sysadminctl -screenLock status`.
11. **Reboot** and check: auto-login works, the screen is locked (password asked), `tailscale status`
    and `ssh jiban` still answer.

## ishizue (NixOS VM on jiban)

A classic NixOS machine (own disk, own /nix/store, systemd-boot) booted in EFI mode by vfkit
(Virtualization.framework). A LaunchAgent of the owner's session (`org.nixos.vm-ishizue`) starts
it at login, i.e. at boot thanks to auto-login. vCPU, RAM, disk size and MAC are declared on the
Mac side: `sekkeizu.vms.ishizue` in `modules/hosts/jiban.nix`. Reachable over Tailscale, and as
`ishizue.local` from jiban (NAT bridge, used by deploys).

State, in `~/.local/state/vm/ishizue/`:

- `disk.raw`: the disk (sparse; the guest's weekly fstrim gives freed blocks back to the Mac).
- `efi-vars`: the EFI variable store (boot order, systemd-boot one-shot entries). Keep it with the
  disk; without it the VM still boots (fallback `EFI/BOOT/BOOTAA64.EFI`) but loses those.
- `console.log` (guest console) and `vfkit.log`, rotated at each start (3 previous kept as `.1`-`.3`):
  vfkit never reopens them, so newsyslog couldn't rotate them while the VM runs.

### Ephemeral root

`/` is a 1 GB tmpfs, rebuilt empty at every boot. The disk (ext4, label `nixos`) is mounted on
`/persist` and carries `/nix` (bind of `/persist/nix`) and everything declared to survive. Each
feature adds its own state to `sekkeizu.persist.directories` / `.files` (tailscale keeps
`/var/lib/tailscale`…); `modules/nixos/impermanence.nix` aggregates them (via
[preservation](https://github.com/nix-community/preservation)) and keeps the machine-id, the
uid/gid map, `/var/lib/systemd`, `/var/log` and the owner's whole home. The SSH host key lives
directly at `/persist/etc/ssh/ssh_host_ed25519_key` (sops decrypts before the bind mounts exist).

Anything installed by hand outside the declared paths is gone at the next reboot: declare it.

Day to day:

- Deploy: `nix run .#deploy-ishizue` (nixos-rebuild, built inside the VM). Each remote `sudo` asks
  for a touch on the FIDO2 key (pam_rssh over the forwarded agent).
- Rollback: `nix run .#deploy-ishizue -- --rollback`, or for one boot only,
  `sudo bootctl set-oneshot nixos-generation-<n>.conf` in the VM, then reboot.
- Restart: `launchctl kickstart -k gui/$(id -u)/org.nixos.vm-ishizue`. A clean poweroff of the
  guest stays stopped; start it again with `launchctl kickstart gui/$(id -u)/org.nixos.vm-ishizue`.
- Resources: edit `sekkeizu.vms.ishizue`, switch jiban, restart the VM. A bigger `diskSize` only
  applies to a new install.

### Installing it (first time, or `--force` to start over with an empty disk)

1. **Linux builder**: uncomment `darwin.linux-builder` in `modules/hosts/jiban.nix`, `nix run .#switch`.
2. **Install**: `nix run .#install-ishizue` builds the disk image (~4 min), copies it sparse, grows
   it to `diskSize` and starts the VM. It refuses to overwrite an existing disk without `-- --force`.
3. **First boot** (~15 s): the partition grows, a new SSH host key is generated. Forget the old
   one: `ssh-keygen -R ishizue.local; ssh-keygen -R ishizue`.
4. **Tailscale**: `ssh ishizue.local` (touch), `sudo tailscale up` (touch), then disable key expiry
   for ishizue in the admin console. `tailscale netcheck` should say `UDP: true`.
   *Keeping the identity of the previous install* (no re-key, same Tailscale node): before
   `install-ishizue --force`, fetch `/etc/ssh/ssh_host_ed25519_key{,.pub}` (or the `/persist` copy
   on an already impermanent install) and `/var/lib/tailscale` from the old VM to jiban. After the
   first boot of the new one, `sudo`-copy them to `/persist/etc/ssh/` (mode 600/644) and
   `/persist/var/lib/tailscale/`, then `sudo reboot`; skip steps 3 (known_hosts) and 5.
5. **Re-key**: `nix run .#rekey-host ishizue` (new age recipient in `.sops.yaml`, re-encrypts
   `secrets/ishizue/`). Commit and push.
6. **Deploy**: `nix run .#deploy-ishizue`, built inside the VM.
7. **Drop the linux builder**: comment `darwin.linux-builder` again, `nix run .#switch`
   (nix-darwin deletes its disk).

## Bootstrap

```bash
./scripts/bootstrap.sh --repo git@github.com:<you>/sekkeizu.git   # see --help for the flags
```

Idempotent: on an already configured machine it skips what is done and ends with a switch.

## Identity

The only file meant to be edited per-user is [`modules/meta/owner.nix`](modules/meta/owner.nix):
account name, display name, email, and the FIDO2 (YubiKey/Thetis) SSH keys used both to log in
and to sign commits.

## Submodule

`files/nvim` is a separate repo (its own history, its own `lazy-lock.json`). Clone with:

```bash
git clone --recurse-submodules git@github.com:<you>/sekkeizu.git
# or, on an existing checkout:
git submodule update --init --recursive
```

`scripts/bootstrap.sh` does this for you.
