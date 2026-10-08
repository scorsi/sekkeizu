# sekkeizu (設計図)

Personal Nix flake for all my machines, built with [flake-parts](https://flake.parts/) and the
[dendritic pattern](https://github.com/mightyiam/dendritic): every feature lives in its own file
under `modules/`, and contributes to as many of `darwin` / `nixos` / `homeManager` as it needs.

## Hosts

| Host      | Machine               | OS             |
| --------- | ---------------------- | -------------- |
| `jiban`   | Mac Mini M4             | macOS (nix-darwin) |
| `ishizue` | NixOS VM on Apple Silicon | NixOS (planned) |

## Layout

```
modules/
  meta/    flake-level options (config.sekkeizu.*) and the one identity file to edit (owner.nix)
  base/    cross-cutting system setup: Nix itself, home-manager wiring, the primary user account
  home/    home-manager features (fish, git, ssh, tmux, neovim, theme, cli tools…)
  macos/   nix-darwin-only features (macOS defaults, Homebrew)
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
