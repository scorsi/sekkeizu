use std/assert

def main [rekey: path] {
  ^git init --quiet
  ^age-keygen -o old.key
  ^age-keygen -o other.key
  ^ssh-keygen -q -t ed25519 -N "" -f new.key
  ^ssh-to-age -private-key -i new.key -o new.age
  let old = ^age-keygen -y old.key | str trim
  let other = ^age-keygen -y other.key | str trim
  let new = open --raw new.key.pub | ^ssh-to-age | str trim
  $env.SOPS_AGE_KEY_FILE = "old.key" | path expand
  let public_key = "new.key.pub" | path expand

  $"keys:
  - &fixture-host ($old)
  - &other ($other)
creation_rules:
  - path_regex: secrets/fixture-host/.*
    key_groups:
      - age: [*fixture-host]
  - path_regex: secrets/shared/.*
    key_groups:
      - age: [*fixture-host, *other]
  - path_regex: secrets/other/.*
    key_groups:
      - age: [*other]
" | save .sops.yaml
  for dir in [fixture-host shared other] { mkdir $"secrets/($dir)" }
  for file in [secrets/fixture-host/secret.yaml secrets/shared/secret.yaml secrets/other/secret.yaml] {
    "value: fixture\n" | save $file
    ^sops encrypt --in-place $file
  }
  0x[00ff10ab] | save secrets/fixture-host/binary
  ^sops encrypt --input-type binary --output-type binary --in-place secrets/fixture-host/binary
  "VALUE=fixture\n" | save secrets/fixture-host/secret.env
  ^sops encrypt --in-place secrets/fixture-host/secret.env
  ^git add secrets
  let original_config = open --raw .sops.yaml
  let original_files = glob secrets/**/* | where { |f| ($f | path type) == file } | each { |f| {path: $f, content: (open --raw $f)} }

  assert ((^$rekey fixture-host | complete).exit_code != 0)
  assert ((^$rekey '../fixture-host' --public-key $public_key | complete).exit_code != 0)
  "ssh-ed25519 invalid\n" | save invalid.pub
  assert ((^$rekey fixture-host --public-key invalid.pub | complete).exit_code != 0)
  assert equal (open --raw .sops.yaml) $original_config

  # Force a failure after earlier files have rotated; all ciphertext and the config must roll back.
  let shared = "secrets/shared/secret.yaml"
  "value: fixture\n" | ^sops encrypt --filename-override secrets/other/secret.yaml --input-type yaml --output-type yaml /dev/stdin | save --force $shared
  let unreadable = open --raw $shared
  let failure = ^$rekey fixture-host --public-key $public_key | complete
  assert ($failure.exit_code != 0)
  assert ($failure.stderr | str contains "original encrypted files restored")
  assert equal (open --raw .sops.yaml) $original_config
  assert equal (open --raw $shared) $unreadable
  for file in ($original_files | where { |f| not ($f.path | str ends-with $shared) }) {
    assert equal (open --raw $file.path) $file.content
  }
  $original_files | where { |f| $f.path | str ends-with $shared } | get 0.content | save --force $shared

  ^$rekey fixture-host --public-key $public_key
  $env.SOPS_AGE_KEY_FILE = "new.age" | path expand
  for file in [secrets/fixture-host/secret.yaml secrets/shared/secret.yaml] {
    assert equal (^sops decrypt $file | from yaml | get value) fixture
    let recipients = open $file | get sops.age.recipient
    assert ($new in $recipients)
    assert ($old not-in $recipients)
  }
  assert equal (^sops decrypt --input-type binary --output-type binary secrets/fixture-host/binary | into binary) 0x[00ff10ab]
  assert equal (^sops decrypt secrets/fixture-host/secret.env | str trim) 'VALUE=fixture'
  let untouched = $original_files | where { |f| $f.path | str ends-with secrets/other/secret.yaml } | get 0
  assert equal (open --raw $untouched.path) $untouched.content
  # Retrying a completed rotation must be harmless.
  ^$rekey fixture-host --public-key $public_key
}
