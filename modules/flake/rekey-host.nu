def main [host: string, --public-key: path] {
  if $host !~ '^[a-z0-9][a-z0-9-]*$' { error make { msg: "invalid host name" } }
  let public_key = if $public_key != null {
    $public_key | path expand
  } else if $host == (^hostname -s | str trim) {
    "/etc/ssh/ssh_host_ed25519_key.pub"
  } else {
    error make { msg: "remote hosts require --public-key from a trusted console or an independently verified source" }
  }
  let pub = open --raw $public_key | str trim | split row --regex '\s+' | first 2 | str join " "
  if not ($pub | str starts-with "ssh-ed25519 ") { error make { msg: "expected an ed25519 host public key" } }
  let age = $pub | ^ssh-to-age | str trim

  cd (^git rev-parse --show-toplevel | str trim)
  let config = open --raw .sops.yaml
  let anchor = '(?m)^  - &' + $host + ' (?<recipient>age1[0-9a-z]+)'
  let matches = $config | parse --regex $anchor
  if ($matches | length) != 1 { error make { msg: $"expected one &($host) anchor in .sops.yaml" } }
  let old = $matches.0.recipient
  let rules = $config | from yaml | get creation_rules
  # Follow the first matching SOPS rule, including shared directories such as secrets/hanko/.
  let files = ^git ls-files -z -- secrets | split row (char nul) | where $it != "" | where { |file|
    let rule = $rules | where { |rule| $file =~ $rule.path_regex } | get 0?
    $rule != null and ($old in ($rule.key_groups | get age | flatten))
  }
  if ($files | is-empty) { error make { msg: $"no tracked secrets use &($host)" } }

  $env.SOPS_AGE_KEY_FILE = $env.SOPS_AGE_KEY_FILE? | default $"($env.HOME)/.config/sops/age/keys.txt"
  if not ($env.SOPS_AGE_KEY_FILE | path exists) {
    error make { msg: $"age identities not found: ($env.SOPS_AGE_KEY_FILE)" }
  }
  print $"recipient of ($host): ($age)"
  print $"updating ($files | length) encrypted files; FIDO2 identities need a touch per file"

  # Keep only ciphertext in memory so a refused touch or failed update does not leave a partial rotation.
  let originals = $files | each { |file| {path: $file, content: (open --raw $file)} }
  try {
    $config | str replace --regex $anchor $"  - &($host) ($age)" | save --force .sops.yaml
    for file in $files {
      let format = match ($file | path parse | get extension) {
        "yaml" | "yml" => "yaml",
        "env" => "dotenv",
        _ => "json" # SOPS binary envelopes (kcpassword, git-crypt-key) are JSON.
      }
      ^sops updatekeys --yes --input-type $format $file
    }
  } catch { |err|
    for file in $originals { $file.content | save --force $file.path }
    $config | save --force .sops.yaml
    error make { msg: $"rotation failed; original encrypted files restored: ($err.msg)" }
  }
}
