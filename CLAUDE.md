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
  this specific user/machine. Treat it as config to preserve, not a template to genericize.

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
