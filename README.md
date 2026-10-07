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
nix develop          # shell with nixfmt, statix, deadnix, shellcheck, just, nvd
```

First-time setup on a brand-new Mac:

```bash
curl -fsSL <raw-url>/scripts/bootstrap.sh | bash -s -- --repo git@github.com:<you>/sekkeizu.git
```

See `scripts/bootstrap.sh --help` for the available flags.

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
