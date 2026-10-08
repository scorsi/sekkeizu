#!/usr/bin/env nu
# Runs a command with this repo's own flakes (the `scorsi-*` inputs, on Forgejo) fetched from
# their GitHub mirrors instead: fresh install or recovery, when Forgejo is out of reach.
#
#   nu scripts/via-github.nu nix run .#switch
#   nix run nixpkgs#nushell -- scripts/via-github.nu nix flake check     # no nushell yet
#
# Nothing is rewritten: git (which Nix runs to fetch git+ssh inputs) gets an `insteadOf` rule
# through the environment, and Nix still checks every input against the rev and narHash locked in
# flake.lock, so the result is the same as from Forgejo. The bootstrap script sets the same rule.

const forgejo = "ssh://git@ishizue.tail9883f3.ts.net:2222/scorsi/"
const github = "ssh://git@github.com/scorsi/"

def --wrapped main [...command: string] {
  if ($command | is-empty) {
    error make { msg: "usage : nu scripts/via-github.nu <commande> [arguments…]" }
  }
  with-env {
    GIT_CONFIG_COUNT: "1"
    GIT_CONFIG_KEY_0: $"url.($github).insteadOf"
    GIT_CONFIG_VALUE_0: $forgejo
  } {
    run-external ($command | first) ...($command | skip 1)
  }
}
