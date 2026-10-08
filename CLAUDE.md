# CLAUDE.md

Guidance for Claude Code when working in this repo. See [README.md](README.md) for what the
repo is and how it's laid out.

## Conventions

- **Comments: English, why not what.** Only comment on non-obvious reasoning (a constraint, a
  workaround, a gotcha) — never restate what the code already says. User-facing runtime strings
  (bootstrap script `log`/`warn`/`die` messages, shell error output) stay in French; that's output
  for the repo owner, not documentation.
- **Dendritic pattern**: a feature is one file under `modules/` declaring
  `flake.modules.<darwin|nixos|homeManager>.<name>`. A host file (`modules/hosts/*.nix`) just
  lists the feature names it imports. Adding a feature should never require editing an existing
  file other than the host(s) that opt into it.
- **Nix formatting**: run `nix fmt` (aliased via `nix run .#fmt`) before considering Nix changes
  done. `nix flake check` (or `nix run .#check`) builds every darwin host on macOS — run it after
  any change under `modules/`.
- `modules/meta/owner.nix` holds real identity data (account name, email, SSH public keys) for
  this specific user/machine: the values of kiso's options. Treat it as config to preserve, not a
  template to genericize.
- **Generic features are kiso's.** fish, git, ssh, tmux, Nix settings and the like live in
  `~/repositories/kiso` (its own CLAUDE.md); change them there, test here with
  `--override-input kiso path:$HOME/repositories/kiso`, then push and `nix flake update kiso`.

## Standing rules

1. **Repo boundary.** sekkeizu describes WHERE things run and HOW they are configured: hosts,
   features, services, network, secrets, infrastructure. Application code (in-house components,
   the site's content, editor config like kanna) lives in its own repo, exposes a flake and is
   consumed here as a pinned input.
2. **Trust levels.** The publishable common base is `kiso` (`github:scorsi/kiso`, public, a
   flakeModule: nix, shell, git, ssh, tmux, tooling, options `kiso.*`), developed in
   `~/repositories/kiso`. Planned: sensitive services move to a separate private repo; a work PC
   imports only kiso. Keep every generic feature movable: no reference to the homelab (host names,
   tailnet, IPs, domains, services) inside it — and nothing of the sort ever goes into kiso.
3. **Destructive tests.** First check that a recent backup exists (`~/Backups/ishizue/`,
   `/persist/backups/` on ishizue). Leave no temporary file behind (`.bak`, copies, decrypted
   secrets). Report any operation that touched real data, even when it turned out harmless.
4. **Naming.** Components and repos take their names from Japanese construction: tools and
   building elements (jiban the bedrock, ishizue the foundation stone, kanna the plane, kiso the
   base…).

## kanna (the Neovim config)

Neovim and its Lua config live in their own repo and flake, `kanna` (`github:scorsi/kanna`),
consumed as a pinned input; the live clone on jiban is `~/repositories/kanna`, which
`~/.config/nvim` links to. A Neovim change is committed and pushed **in that repo**; sekkeizu only
moves its pin (`nix flake update kanna`, commit `flake.lock`). See kanna's README for testing a Nix
change with `--override-input` before pushing.

## Testing changes

There's no app to run — verification is `nix flake check` / `nix run .#check` succeeding, plus
(when touching `scripts/bootstrap.sh`) `shellcheck scripts/bootstrap.sh`. Both are cheap; run them
before reporting Nix or shell changes as complete.

## Git

Commits are SSH-signed via a plugged-in FIDO2 key (see `modules/home/git.nix`); signing just needs
a touch on the hardware key, no PIN. Creating commits (including signing) in this repo on behalf
of the user is fine — no need to ask first.
