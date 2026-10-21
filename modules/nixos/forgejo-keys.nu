def key-content [key: string] {
  let parts = $key | str trim | split row --regex '\s+'
  if ($parts | length) < 2 { error make {msg: "Invalid SSH public key"} }
  $parts | first 2 | str join ' '
}

def api-ok [request: closure, method: string, path: string, body: record, expected: int] {
  let response = do $request $method $path $body
  if $response.status != $expected {
    error make {msg: $"Forgejo ($method) ($path): HTTP ($response.status), expected ($expected)"}
  }
  $response.body
}

def api-list [request: closure, path: string] {
  mut rows = []
  mut page = 1
  loop {
    let batch = api-ok $request GET $"($path)?limit=50&page=($page)" {} 200
    if ($batch | describe) !~ '^(list|table)' { error make {msg: $"Invalid list from Forgejo: ($path)"} }
    if ($batch | is-empty) { break }
    let seen = $rows
    if ($batch | any {|row| $row in $seen }) { error make {msg: $"Repeated Forgejo page: ($path)"} }
    $rows = $rows | append $batch
    # The server may clamp the requested page size; only an empty page ends the listing.
    $page = $page + 1
  }
  $rows
}

def save-key-state [state: string, keys: list] {
  let temporary = $"($state).tmp"
  try {
    $keys | to json | save --force $temporary
    ^sync -- $temporary
    mv --force $temporary $state
    ^sync -- ($state | path dirname)
  } catch {|err|
    if ($temporary | path exists) { rm $temporary }
    error make {msg: $"Saving Forgejo key ownership: ($err.msg)"}
  }
}

def reconcile-keys [request: closure, targets: list, prefix: string, state: string] {
  let previous = if ($state | path exists) { open $state } else {
    print --stderr "Forgejo key migration: unmarked keys absent from the current configuration are preserved; review them manually."
    []
  }
  if ($previous | describe) !~ '^(list|table)' { error make {msg: "Invalid Forgejo key ownership state"} }
  mut adopted = []
  mut creates = []
  mut removes = []
  mut replaces = []
  # Complete every listing and ownership check before the first mutation.
  for target in $targets {
    let desired = $target.keys | update key {|k| key-content $k.key } | uniq-by key
    let current = api-list $request $target.path | each {|key|
      if ($key.id | describe) != int or $key.id < 1 { error make {msg: "Invalid Forgejo key ID"} }
      let identity = {path: $target.path, id: $key.id, key: (key-content $key.key), title: $key.title}
      let managed = ($key.title | str starts-with $prefix) or ($identity in $previous)
      $key | merge $identity | insert managed $managed
    }
    for wanted in $desired {
      let matches = $current | where key == $wanted.key
      if ($matches | is-not-empty) {
        let found = $matches | first
        if not $found.managed {
          # Old units used these exact titles and contents; a title alone proves no ownership.
          if $found.title != $wanted.title or ($target.deploy and not $found.read_only) {
            error make {msg: $"Unmanaged key conflicts with configuration at ($target.path): ($found.id)"}
          }
          $adopted = $adopted | append ($found | select path id key title)
        } else if not ($found.title | str starts-with $prefix) {
          $adopted = $adopted | append ($found | select path id key title)
        }
        if not $target.deploy or $found.read_only { continue }
        # Forgejo cannot change deploy-key permissions or add the same content twice.
        $replaces = $replaces | append $found
      }
      $creates = $creates | append {
        path: $target.path,
        body: {title: $"($prefix)($wanted.key | hash sha256)", key: $wanted.key, read_only: true}
      }
    }
    $removes = $removes | append ($current | where {|key| $key.managed and $key.key not-in $desired.key })
  }
  # Persist adoption before revoking anything so a failed run remains recoverable.
  save-key-state $state ($previous | append $adopted | uniq)
  for key in $replaces {
    api-ok $request DELETE $"($key.path)/($key.id)" {} 204 | ignore
  }
  # Distinct titles let a replacement be installed before the previous key is revoked.
  for key in $creates { api-ok $request POST $key.path $key.body 201 | ignore }
  for key in $removes {
    api-ok $request DELETE $"($key.path)/($key.id)" {} 204 | ignore
  }
  save-key-state $state $adopted
}

def reconcile-owner-keys [request: closure, keys: list, state: string] {
  reconcile-keys $request [{path: user/keys, keys: $keys, deploy: false}] 'sekkeizu:owner:' $state
}

def reconcile-deploy-keys [request: closure, owner: string, repos: list<string>, key: string, state: string] {
  let user = $owner | url encode --all
  # Include repositories removed from readRepos, even after a failed POST or lost local state.
  let all = (api-list $request $"users/($user)/repos" | each {|repo| $repo.name }) | append $repos | uniq
  let targets = $all | each {|repo|
    {
      path: $"repos/($user)/($repo | url encode --all)/keys",
      keys: (if $repo in $repos { [{title: forgejo-ci, key: $key}] } else { [] }),
      deploy: true
    }
  }
  reconcile-keys $request $targets 'sekkeizu:ci:' $state
}
