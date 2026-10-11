#!/usr/bin/env nu
# Refreshes modules/home/claude-code-manifest.json from the latest claude-code release, so the
# nixpkgs.overlays override in modules/home/claude-code.nix (see that file) tracks upstream
# instead of nixpkgs' lagging manifest.json. Pass a version to pin something other than latest.
#
#   nu scripts/update-claude-code.nu
#   nu scripts/update-claude-code.nu 2.1.300
#
# Same source nixpkgs' own claude-code update.sh uses. Once nixpkgs' pinned manifest catches up
# to (or passes) the version pinned here, drop the override in claude-code.nix and this file.

const base_url = "https://downloads.claude.ai/claude-code-releases"
const manifest_path = "modules/home/claude-code-manifest.json"

def main [version?: string] {
  cd (git rev-parse --show-toplevel | str trim)

  let current = if ($manifest_path | path exists) { open $manifest_path | get version } else { null }
  let version = $version | default (http get --raw $"($base_url)/latest" | str trim)

  if $version == $current {
    print $"déjà à jour : claude-code ($version)"
    return
  }

  http get --raw $"($base_url)/($version)/manifest.json" | save -f $manifest_path
  git add $manifest_path
  print $"claude-code ($current) → ($version)"
}
