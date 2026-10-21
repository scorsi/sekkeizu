source ./forgejo-keys.nu
use std/assert

def fake-request [method: string, path: string, body: record] {
  mut db = open $env.KEY_TEST_API
  $db.calls = $db.calls | append {method: $method, path: $path}
  $db | to json | save --force $env.KEY_TEST_API
  let fault = $db.faults | where method == $method and path == $path
  if ($fault | is-not-empty) { return {status: $fault.0.status, body: ($fault.0.body? | default {})} }
  let base = $path | split row '?' | first
  let resource = $db.resources | where path == $base
  if $method == GET {
    if ($resource | is-empty) { return {status: 404, body: {}} }
    # One row per page exercises servers that clamp limit=50.
    let page = ($path | parse -r 'page=(?<page>\d+)' | get 0.page | into int)
    return {status: 200, body: ($resource.0.rows | skip ($page - 1) | first 1)}
  }
  if $method == POST {
    if ($resource | is-empty) { return {status: 404, body: {}} }
    if ($resource.0.rows | any {|key| $key.key == $body.key or $key.title == $body.title }) {
      return {status: 422, body: {}}
    }
    let added = $body | insert id $db.next
    $db.next = $db.next + 1
    $db.resources = $db.resources | each {|r| if $r.path == $base { $r | update rows ($r.rows | append $added) } else { $r } }
    $db | to json | save --force $env.KEY_TEST_API
    return {status: 201, body: $added}
  }
  let parts = $base | split row '/'
  let collection = $parts | drop 1 | str join '/'
  let id = $parts | last | into int
  $db.resources = $db.resources | each {|r| if $r.path == $collection { $r | update rows ($r.rows | where id != $id) } else { $r } }
  $db | to json | save --force $env.KEY_TEST_API
  {status: 204, body: null}
}

def fixture [resources: list] {
  {resources: $resources, calls: [], faults: [], next: 100} | to json | save --force $env.KEY_TEST_API
  if ($env.KEY_TEST_STATE | path exists) { rm $env.KEY_TEST_STATE }
}

def keys [path: string = user/keys] { (open $env.KEY_TEST_API).resources | where path == $path | get 0.rows }
def writes [] { (open $env.KEY_TEST_API).calls | where method != GET }
def clear-calls [] { open $env.KEY_TEST_API | update calls [] | to json | save --force $env.KEY_TEST_API }
def fault [method: string, path: string, status: int, body: any = null] {
  open $env.KEY_TEST_API | update faults [{method: $method, path: $path, status: $status, body: $body}] | to json | save --force $env.KEY_TEST_API
}
def clear-faults [] { open $env.KEY_TEST_API | update faults [] | to json | save --force $env.KEY_TEST_API }
def owner [wanted: list] { reconcile-owner-keys { |m, p, b| fake-request $m $p $b } $wanted $env.KEY_TEST_STATE }
def deploy [repos: list<string>, key: string = 'ssh-ed25519 NEW'] {
  reconcile-deploy-keys { |m, p, b| fake-request $m $p $b } owner $repos $key $env.KEY_TEST_STATE
}

def run-tests [] {
  let old = {id: 1, title: yubikey, key: 'ssh-ed25519 OLD'}
  let manual = {id: 2, title: manual, key: 'ssh-ed25519 MANUAL'}
  let wanted = {title: yubikey, key: 'ssh-ed25519 NEW'}
  fixture [{path: user/keys, rows: [$old $manual]}]
  owner [$old]
  assert equal (writes) []
  assert equal ((open $env.KEY_TEST_STATE) | get id) [1]
  owner [$wanted]
  assert equal ((writes) | get method) [POST DELETE]
  assert equal ((keys) | get key) [$manual.key $wanted.key]
  clear-calls
  owner [($wanted | update key 'ssh-ed25519 NEW a changed comment')]
  assert equal (writes) []
  owner []
  assert equal ((keys) | get key) [$manual.key]

  fixture [{path: user/keys, rows: [$old $manual]}]
  owner []
  assert equal (keys) [$old $manual]
  assert error { owner [{title: different, key: $manual.key}] }
  assert equal (writes) []

  for status in [401 403 500] {
    fixture [{path: user/keys, rows: [$old $manual]}]
    fault GET 'user/keys?limit=50&page=2' $status
    assert error { owner [$wanted] }
    assert equal (writes) []
    assert not ($env.KEY_TEST_STATE | path exists)
  }
  fixture [{path: user/keys, rows: [$old]}]
  fault GET 'user/keys?limit=50&page=1' 200 {message: invalid}
  assert error { owner [] }
  assert equal (writes) []
  fault GET 'user/keys?limit=50&page=2' 200 [$old]
  assert error { owner [] }
  assert equal (writes) []
  clear-faults
  assert error {
    reconcile-owner-keys { |m, p, b| fake-request $m $p $b } [$wanted] ($env.KEY_TEST_STATE | path join missing.json)
  }
  assert equal (writes) []

  let sync_bin = $env.KEY_TEST_STATE | path dirname | path join bin
  mkdir $sync_bin
  '#!/bin/sh
[ "$2" != "$KEY_TEST_SYNC_FAIL" ]
' | save ($sync_bin | path join sync)
  ^chmod +x ($sync_bin | path join sync)
  for failed_path in [$"($env.KEY_TEST_STATE).tmp" ($env.KEY_TEST_STATE | path dirname)] {
    fixture [{path: user/keys, rows: [$old]}]
    with-env {PATH: ($env.PATH | prepend $sync_bin), KEY_TEST_SYNC_FAIL: $failed_path} {
      assert error { owner [$old $wanted] }
    }
    assert equal (writes) []
    assert not ($"($env.KEY_TEST_STATE).tmp" | path exists)
  }

  fixture [{path: user/keys, rows: [$old]}]
  owner [$old]
  for status in [401 422 500] {
    fault POST user/keys $status
    assert error { owner [$wanted] }
    assert equal (keys) [$old]
    assert equal ((open $env.KEY_TEST_STATE) | get id) [1]
  }
  clear-faults
  fault DELETE user/keys/1 500
  assert error { owner [$wanted] }
  assert equal ((keys) | length) 2
  clear-faults
  clear-calls
  owner [$wanted]
  assert equal ((writes) | get method) [DELETE]
  assert equal ((keys) | get key) [$wanted.key]

  let deploy_old = $old | update title forgejo-ci | insert read_only true
  let deploy_manual = $manual | insert read_only false
  fixture [
    {path: users/owner/repos, rows: [{name: alpha} {name: beta}]}
    {path: repos/owner/alpha/keys, rows: [$deploy_old $deploy_manual]}
    {path: repos/owner/beta/keys, rows: []}
  ]
  deploy [alpha] $old.key
  assert equal (writes) []
  deploy [beta]
  assert equal ((keys repos/owner/alpha/keys) | get key) [$manual.key]
  assert equal ((keys repos/owner/beta/keys) | get read_only) [true]
  clear-calls
  deploy [beta]
  assert equal (writes) []
  deploy [beta] 'ssh-ed25519 ROTATED'
  assert equal ((writes) | get method) [POST DELETE]
  assert equal ((keys repos/owner/beta/keys) | get key) ['ssh-ed25519 ROTATED']
  # The marker survives a lost state file, including withdrawal of the repository.
  rm $env.KEY_TEST_STATE
  deploy []
  assert equal (keys repos/owner/beta/keys) []
  assert equal (keys repos/owner/alpha/keys) [$deploy_manual]

  deploy [beta]
  clear-calls
  fault GET 'users/owner/repos?limit=50&page=2' 500
  assert error { deploy [] }
  assert equal (writes) []
  clear-faults
  assert error { deploy [missing] }
  assert equal (writes) []
  assert equal ((keys repos/owner/beta/keys) | length) 1

  # Permission drift of a managed deploy key must not leave write access behind.
  open $env.KEY_TEST_API | update resources {|db|
    $db.resources | each {|r|
      if $r.path == 'repos/owner/beta/keys' { $r | update rows ($r.rows | update read_only false) } else { $r }
    }
  } | to json | save --force $env.KEY_TEST_API
  deploy [beta]
  assert equal ((keys repos/owner/beta/keys) | get read_only) [true]
  print 'Forgejo key reconciliation: all assertions passed'
}

def main [] {
  let temporary = mktemp -d
  $env.KEY_TEST_API = $temporary | path join api.json
  $env.KEY_TEST_STATE = $temporary | path join ownership.json
  try { run-tests } catch {|err|
    rm --recursive $temporary
    error make $err
  }
  rm --recursive $temporary
}
