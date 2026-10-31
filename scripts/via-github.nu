#!/usr/bin/env nu
# Runs a command with this repo's own flakes (the `scorsi-*` inputs, on kajiba) fetched from
# their GitHub mirrors instead: fresh install or recovery, when kajiba is out of reach.
#
#   nu scripts/via-github.nu nix run .#switch
#   nix run nixpkgs#nushell -- scripts/via-github.nu nix flake check     # no nushell yet
#
# Nothing is rewritten: git (which Nix runs to fetch git+ssh inputs) gets an `insteadOf` rule
# through the environment, and Nix still checks every input against the rev and narHash locked in
# flake.lock, so the result is the same as from kajiba. The bootstrap script sets the same rule.

# Where the inputs are fetched from: kajiba today, Forgejo for locks written before the move.
const forgejo = ["https://kajiba.uchi.scorsi.dev/scorsi/" "ssh://git@forgejo.uchi.scorsi.dev:2222/scorsi/"]
const github = "ssh://git@github.com/scorsi/"

def --wrapped main [...command: string] {
  if ($command | is-empty) {
    error make { msg: "usage : nu scripts/via-github.nu <commande> [arguments…]" }
  }
  # One insteadOf value per name: git accepts several for the same base.
  let rules = $forgejo | enumerate | reduce --fold { GIT_CONFIG_COUNT: ($forgejo | length | into string) } { |it, acc|
    $acc | insert $"GIT_CONFIG_KEY_($it.index)" $"url.($github).insteadOf" | insert $"GIT_CONFIG_VALUE_($it.index)" $it.item
  }
  with-env $rules {
    run-external ($command | first) ...($command | skip 1)
  }
}
