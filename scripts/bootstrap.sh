#!/usr/bin/env bash
# Bootstrap a Mac (Apple Silicon) into its nix-darwin configuration.
#
# Idempotent: re-run on an already configured machine, it skips completed steps
# and finishes with a `darwin-rebuild switch`.
#
# Usage:
#   ./scripts/bootstrap.sh                         # host jiban, repo in ~/sekkeizu
#   ./scripts/bootstrap.sh --host jiban --dir ~/sekkeizu --repo git@github.com:<you>/sekkeizu.git
#   curl -fsSL <raw url>/scripts/bootstrap.sh | bash -s -- --repo <url>
#
# Steps: Command Line Tools → Nix (official installer) → repo (nixpkgs ssh/git, FIDO2 key) → kanna clone
#          → flake inputs from the GitHub mirrors → checks
#          → move aside /etc files that nix-darwin refuses to overwrite → first switch.

set -euo pipefail

HOST="jiban"
DIR="${HOME}/sekkeizu"
REPO=""
NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31mxx\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --host)
    HOST="${2:?--host attend une valeur}"
    shift 2
    ;;
  --dir)
    DIR="${2:?--dir attend une valeur}"
    shift 2
    ;;
  --repo)
    REPO="${2:?--repo attend une valeur}"
    shift 2
    ;;
  -h | --help) usage 0 ;;
  *)
    warn "option inconnue : $1"
    usage 1
    ;;
  esac
done

# ─── 0. Preconditions ────────────────────────────────────────────────
[[ "$(uname -s)" == "Darwin" ]] || die "ce script ne tourne que sur macOS"
[[ "$(uname -m)" == "arm64" ]] || die "ce script vise Apple Silicon (arm64)"
[[ "$EUID" -ne 0 ]] || die "lance-le avec ton utilisateur, pas en root (sudo est demandé quand il faut)"

log "host: ${HOST} · repo: ${DIR}"
sudo -v # asks for the password once, up front

# ─── 1. Command Line Tools (git, compilers) ──────────────────────────
if xcode-select -p >/dev/null 2>&1; then
  log "Command Line Tools : déjà installés"
else
  log "Command Line Tools : installation sans interface graphique"
  marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$marker"
  label="$(softwareupdate -l 2>/dev/null |
    sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' |
    sort -V | tail -n1)"
  [[ -n "$label" ]] || {
    rm -f "$marker"
    die "paquet Command Line Tools introuvable via softwareupdate"
  }
  sudo softwareupdate -i "$label" --verbose
  rm -f "$marker"
fi

# ─── 2. Nix (official installer, multi-user) ─────────────────────────
if [[ -x "$NIX_BIN" ]]; then
  log "Nix : déjà installé ($("$NIX_BIN" --version))"
else
  log "Nix : installation (installeur officiel nixos.org)"
  installer="$(mktemp)"
  curl --proto '=https' --tlsv1.2 -fsSL https://nixos.org/nix/install -o "$installer"
  sh "$installer" --daemon --yes --no-channel-add
  rm -f "$installer"
fi
# Makes `nix` available in this shell without reopening it.
# shellcheck disable=SC1091
[[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]] &&
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# ─── 3. The repo ──────────────────────────────────────────────────────
# Private repo on a brand-new Mac: the system ssh has no FIDO2 support (and Apple's git
# would use it), so clone with nixpkgs' openssh + git. The SSH key lives on the hardware
# key as a resident credential: `ssh-keygen -K` pulls its handle into ~/.ssh.
ssh_cmd="ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes"

with_nix_ssh() {
  "$NIX_BIN" "${NIX_FLAGS[@]}" shell nixpkgs#openssh nixpkgs#git \
    --command env GIT_SSH_COMMAND="$ssh_cmd" "$@"
}

# FIDO2 key handles in ~/.ssh (as written by `ssh-keygen -K`: id_ed25519_sk_rk…), private part only.
fido_handles() {
  local f
  for f in "${HOME}"/.ssh/id_*_sk*; do
    [[ -f "$f" && "$f" != *.pub ]] && printf '%s\n' "$f"
  done
  return 0
}

if [[ "$REPO" == git@* || "$REPO" == ssh://* ]]; then
  if [[ -z "$(fido_handles)" ]]; then
    log "clé FIDO2 : aucun handle dans ~/.ssh, récupération (branche la clé, PIN puis touch)"
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
    (cd "${HOME}/.ssh" && with_nix_ssh ssh-keygen -K </dev/tty)
  fi
  while IFS= read -r handle; do
    ssh_cmd="${ssh_cmd} -i ${handle}"
  done < <(fido_handles)
fi

if [[ -f "${DIR}/flake.nix" ]]; then
  log "repo : présent dans ${DIR}"
elif [[ -n "$REPO" ]]; then
  log "repo : clonage de ${REPO}"
  with_nix_ssh git clone "$REPO" "$DIR"
else
  die "pas de flake dans ${DIR} : passe --repo <url> ou copie le repo (ex. scp -r depuis le laptop)"
fi

# The Neovim config (kanna) comes from the flake input, but on a dev machine ~/.config/nvim links to
# a live clone (`kanna-dev` feature, sekkeizu.reposDir): fetch it next to where the repo came from.
KANNA_DIR="${HOME}/repositories/kanna"
if [[ -d "${KANNA_DIR}/.git" ]]; then
  log "kanna : présent dans ${KANNA_DIR}"
elif [[ -n "$REPO" ]]; then
  log "kanna : clonage de ${REPO%/*}/kanna.git"
  mkdir -p "${KANNA_DIR%/*}"
  with_nix_ssh git clone "${REPO%/*}/kanna.git" "$KANNA_DIR"
else
  warn "kanna absent de ${KANNA_DIR} : ~/.config/nvim pointera dans le vide tant qu'il n'est pas cloné"
fi

# Nix only sees files tracked by git: an unadded file = "doesn't exist".
if git -C "$DIR" status --porcelain 2>/dev/null | grep -q '^??'; then
  warn "fichiers non suivis par git dans ${DIR} : ils seront ignorés par Nix (git add ?)"
fi

# The repo's own flakes (inputs scorsi-*) come from Forgejo, which a fresh machine can't reach yet
# (no Tailscale): take them from their GitHub mirrors, at the revisions locked in flake.lock. Same
# rewrite as scripts/via-github.nu. Fetched now as the user, with the FIDO2 key; every evaluation
# below, root's included, then finds them in the store.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.ssh://git@github.com/scorsi/.insteadOf"
export GIT_CONFIG_VALUE_0="ssh://git@ishizue.tail9883f3.ts.net:2222/scorsi/"
log "inputs : récupération (miroirs GitHub)"
with_nix_ssh "$NIX_BIN" "${NIX_FLAGS[@]}" flake archive "$DIR" >/dev/null

# ─── 4. Checks before switching ───────────────────────────────────────
flake="${DIR}#darwinConfigurations.${HOST}"
log "évaluation de ${HOST}"
configured_user="$("$NIX_BIN" "${NIX_FLAGS[@]}" eval --raw "${flake}.config.system.primaryUser")" ||
  die "évaluation impossible : host '${HOST}' inexistant ou erreur Nix (voir ci-dessus)"
[[ "$configured_user" == "$(whoami)" ]] ||
  die "sekkeizu.owner.name = '${configured_user}' mais tu es '$(whoami)' : corrige modules/meta/owner.nix"

# ─── 5. /etc files nix-darwin refuses to overwrite ───────────────────
# nix-darwin aborts if it finds these files unmanaged by it: rename them once.
for f in /etc/bashrc /etc/zshrc /etc/zprofile /etc/shells /etc/nix/nix.conf /etc/nix/nix.custom.conf; do
  if [[ -f "$f" && ! -L "$f" ]]; then
    log "mise de côté : $f -> ${f}.before-nix-darwin"
    sudo mv "$f" "${f}.before-nix-darwin"
  fi
done

# ─── 6. Switch ─────────────────────────────────────────────────────────
if command -v darwin-rebuild >/dev/null 2>&1; then
  log "switch (darwin-rebuild déjà installé)"
  sudo darwin-rebuild switch --flake "${DIR}#${HOST}"
else
  # First switch: darwin-rebuild comes from the flake, at the version pinned in flake.lock.
  log "premier switch"
  sudo -H "$NIX_BIN" "${NIX_FLAGS[@]}" run "${DIR}#darwin-rebuild" -- switch --flake "${DIR}#${HOST}"
fi

log "terminé. Ouvre un nouveau terminal (shell : fish). Rebuilds suivants : drs"
