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
  meta/    flake-level options (config.sekkeizu.*), the identity file (owner.nix) and where services live (endpoints.nix)
  base/    cross-cutting system setup: Nix itself, home-manager wiring, the primary user account
  home/    home-manager features (fish, git, ssh, tmux, kanna, theme, cli tools…)
  macos/   nix-darwin-only features (macOS defaults, Homebrew, VM host)
  nixos/   NixOS-only features (server, Caddy, Forgejo, site)
  ci/      Forgejo Actions runners (NixOS and macOS)
  backup/  off-VM copies (jiban pulls ishizue's backups)
  network/ Tailscale
  vm/      NixOS guest base for VMs on a Mac (vfkit, EFI)
  flake/   flake plumbing (supported systems, dev shell, apps, the darwinConfigurations option)
  hosts/   one file per machine: its identity + the features it imports
scripts/
  bootstrap.sh   turns a fresh Mac into a working jiban
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
switch. The repo is private (SSH over FIDO2 key), so the bootstrap script cannot be
fetched with `curl` from GitHub: bring `scripts/bootstrap.sh` over (AirDrop, `scp`, USB stick).

1. **Before wiping**: everything pushed (`sekkeizu` and `~/repositories/kanna`), and the sops admin key
   (`~/.config/sops/age/keys.txt`) is in the password manager.
2. **Erase All Content and Settings**, then in Setup Assistant: create the account with the name set
   in `modules/meta/owner.nix`, and **turn FileVault off** when the assistant offers it (with
   FileVault on, macOS ignores `/etc/kcpassword` and the headless boot stops at the unlock screen).
3. **Bootstrap**, with the first FIDO2 key plugged in:
   ```bash
   bash bootstrap.sh --repo git@github.com:scorsi/sekkeizu.git
   ```
   It installs the Command Line Tools and Nix, pulls the key handle (`ssh-keygen -K`: PIN, then touch),
   clones sekkeizu and kanna (`~/repositories/kanna`, the live Neovim config) and runs the first switch. That switch can complain that sops cannot
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

- Deploy: `nix run .#deploy-ishizue` (nixos-rebuild, built inside the VM). Connects as `root@` (key-only,
  FIDO2 keys, allowed only from the Mac's NAT bridge and Tailscale), one shared SSH connection:
  one touch per deploy. Interactive `sudo` in the VM still uses pam_rssh (a touch each).
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

## Forge and web (ishizue)

Everything is reachable only over Tailscale (the firewall trusts `tailscale0` and nothing else).
One name per machine, `ishizue.<tailnet>.ts.net`, services told apart by port:

| Service   | Address                                  | Behind                     |
| --------- | ---------------------------------------- | -------------------------- |
| Forgejo   | `https://ishizue.<tailnet>.ts.net`       | Caddy → 127.0.0.1:3000     |
| Git (SSH) | `ssh://git@ishizue.<tailnet>.ts.net:2222` | Forgejo's built-in SSH server |
| Site      | `https://ishizue.<tailnet>.ts.net:8443`  | Caddy, static files        |

Addresses are declared once, in `modules/meta/endpoints.nix` (`sekkeizu.services.*`); Caddy,
Forgejo's `ROOT_URL` and the runners read them from there. Moving to `git.lab.<domain>` means editing
that file (and swapping Tailscale certificates for ACME in Caddy).

- **Git over SSH on 2222**: Forgejo's own SSH server, not the system sshd, which stays key-only for
  the owner. No shared `git` account on the system, no `AllowUsers` change; the server only speaks
  git, with the keys stored in Forgejo (`owner.sshKeys`, added by the `forgejo-admin` unit).
- **Backups**: `forgejo dump` daily (04:31) in `/persist/backups/forgejo`, 7 days kept. jiban pulls
  them at 05:15 into `~/Backups/ishizue/forgejo/` (30 days kept) as the `backup` account, which
  can only run `rrsync -ro /persist/backups` and only from the NAT bridge (`modules/backup/pull.nix`).
  One line per run in `~/Library/Logs/backup-ishizue.log`, a notification on failure. Run it now:
  `launchctl kickstart gui/$(id -u)/org.nixos.backup-ishizue`. External disk and off-site (restic)
  come next, from `~/Backups`.
- **Runners** (host executor, no containers): `linux` on ishizue (Nix, git, node, zola, rsync;
  systemd sandbox, writes only to its state directory and `/var/lib/site`), `macos` on jiban (LaunchDaemon, hidden
  non-admin `_forgejo-runner` account). Rationale in `modules/ci/forgejo-runner.nix`.
  Registration is declarative: a shared secret per runner in sops, pre-registered by Forgejo.
- **Site**: Zola repository `site` on Forgejo; a push to `main` runs `.forgejo/workflows/deploy.yml`
  (`runs-on: linux`): `zola build`, then `rsync` into `/var/lib/site`, served by Caddy on 8443.

### Manual steps, in order

1. **Tailscale admin console → DNS → HTTPS Certificates**: enable. Without it Caddy cannot get
   its certificate (`tailscale cert` answers "does not support getting TLS certs"); it retries by
   itself every minute once enabled.
2. **Deploy ishizue**: `nix run .#deploy-ishizue`.
3. **Switch jiban**: `nix run .#switch` (creates the `_forgejo-runner` account and the daemon).
   Check in Forgejo → Site administration → Actions → Runners that `ishizue` and `jiban` are idle.
4. **Log in**: user = `owner.name`, password:
   `sops -d --extract '["forgejo-admin-password"]' secrets/ishizue/secrets.yaml`
   (the `forgejo-admin` unit resets the account to that password at each Forgejo start).
5. **Create the site**: from the `site` checkout,
   `git remote add origin ssh://git@ishizue.<tailnet>.ts.net:2222/<owner>/site.git && git push -u origin main`
   (push-to-create makes the private repository). The workflow runs by itself.
6. **Rotate a runner secret**: new `openssl rand -hex 20` in `secrets/ishizue/secrets.yaml` (and
   `secrets/jiban/secrets.yaml` for jiban's), deploy/switch.

Test the macOS runner with a workflow containing `runs-on: macos` and `run: sw_vers`.

## Bootstrap

```bash
./scripts/bootstrap.sh --repo git@github.com:<you>/sekkeizu.git   # see --help for the flags
```

Idempotent: on an already configured machine it skips what is done and ends with a switch.

## Identity

The only file meant to be edited per-user is [`modules/meta/owner.nix`](modules/meta/owner.nix):
account name, display name, email, and the FIDO2 (YubiKey/Thetis) SSH keys used both to log in
and to sign commits.

## Neovim: kanna

The Neovim config is its own repo and flake, [kanna](https://github.com/scorsi/kanna), consumed as
the input `kanna` (always from GitHub). Feature `kanna`: the config from the store, frozen with
`flake.lock`. Feature `kanna-dev` (jiban): `~/.config/nvim` links to the clone in
`~/repositories/kanna` (`sekkeizu.reposDir`), so Lua edits apply without a rebuild. Nix changes
in kanna: see its README (`--override-input kanna path:…`, then `nix flake update kanna`).
