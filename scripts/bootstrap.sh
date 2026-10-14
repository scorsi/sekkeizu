#!/usr/bin/env bash
# Bootstrap a Mac (Apple Silicon) into its nix-darwin configuration.
#
# Idempotent: re-run on an already configured machine, it skips completed steps
# and finishes with a `darwin-rebuild switch`.
#
# Usage (bootstrap.nim must sit next to this file):
#   ./scripts/bootstrap.sh                         # host jiban, repo in ~/repositories/sekkeizu
#   ./scripts/bootstrap.sh --host jiban --dir ~/repositories/sekkeizu --repo git@github.com:<you>/sekkeizu.git \
#     --git-crypt-key <file>                       # the repo's key (password manager, base64 -d)
#
# Steps: Nix (official installer) → the rest in bootstrap.nim: Command Line Tools → repo (nixpkgs
#          ssh/git, FIDO2 key) → clones (kanna, kiso) → git-crypt unlock → flake inputs from the
#          GitHub mirrors → checks → move aside /etc files that nix-darwin refuses to overwrite
#          → first switch.

# Only what has to run before Nix exists lives here: everything else is bootstrap.nim.
set -euo pipefail

NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31mxx\033[0m %s\n' "$*" >&2
  exit 1
}

for arg in "$@"; do
  if [[ "$arg" == -h || "$arg" == --help ]]; then
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
  fi
done

[[ "$(uname -s)" == "Darwin" ]] || die "ce script ne tourne que sur macOS"
[[ "$(uname -m)" == "arm64" ]] || die "ce script vise Apple Silicon (arm64)"
[[ "$EUID" -ne 0 ]] || die "lance-le avec ton utilisateur, pas en root (sudo est demandé quand il faut)"
[[ -f "${HERE}/bootstrap.nim" ]] || die "bootstrap.nim introuvable à côté de ce script (${HERE})"

if [[ -x "$NIX_BIN" ]]; then
  log "Nix : déjà installé ($("$NIX_BIN" --version))"
else
  log "Nix : installation (installeur officiel nixos.org)"
  installer="$(mktemp)"
  curl --proto '=https' --tlsv1.2 -fsSL https://nixos.org/nix/install -o "$installer"
  sh "$installer" --daemon --yes --no-channel-add
  rm -f "$installer"
fi
# Gives bootstrap.nim and the commands it runs Nix's environment without reopening the shell.
# shellcheck disable=SC1091
[[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]] &&
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# clang from nixpkgs: the Command Line Tools may not be installed yet, bootstrap.nim does it.
# Compiled then run (not `nim r`, which adds its own error line to every failure).
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
"$NIX_BIN" --extra-experimental-features "nix-command flakes" shell nixpkgs#nim nixpkgs#clang \
  --command nim c --hints:off --nimcache:"${build}/cache" -o:"${build}/bootstrap" "${HERE}/bootstrap.nim"
"${build}/bootstrap" "$@"
