use std/assert

let root = mktemp --directory
let group = ^id -gn | str trim
let export = {|store: string, dest: string| ^nu --no-config-file observability-export.nu $store $dest $group }

def day [dir: string, name: string, sealed: bool] {
  mkdir $dir
  $"data ($name)" | save ($dir | path join $"($name).ndjson.zst")
  if $sealed { "{}" | save ($dir | path join $"($name).manifest.json") }
}

for format in [["masu-archive 1\n" archive] ["nisshi-store 1\n" "."]] {
  let store = $root | path join (random uuid)
  let dest = $root | path join (random uuid)
  mkdir $store $dest
  $format.0 | save ($store | path join FORMAT)
  let node = $store | path join $format.1 node-a | path expand
  day $node 2026-10-27 true
  day $node 2026-10-28 true
  # The open day: no manifest yet.
  day $node 2026-10-29 false
  ^chmod 0644 ...(glob ($node | path join "*"))

  do $export $store $dest
  let out = $dest | path join $format.1 node-a
  for name in [2026-10-27.ndjson.zst 2026-10-27.manifest.json 2026-10-28.ndjson.zst] {
    let a = ls --long ($node | path join $name) | first
    let b = ls --long ($out | path join $name) | first
    assert equal $a.inode $b.inode
    assert equal $a.mode "rw-r-----"
    assert equal $a.group $group
  }
  assert not (($out | path join 2026-10-29.ndjson.zst) | path exists)
  assert equal (ls --long ($node | path join 2026-10-29.ndjson.zst) | first | get mode) "rw-r--r--"
  assert equal (open --raw ($dest | path join FORMAT)) $format.0

  # Idempotent, then the store's retention drops a day and seals the open one.
  do $export $store $dest
  rm ($node | path join 2026-10-27.ndjson.zst) ($node | path join 2026-10-27.manifest.json)
  "{}" | save ($node | path join 2026-10-29.manifest.json)
  do $export $store $dest
  let left = glob --no-dir ($dest | path join "**" "*") | each { path relative-to $dest } | sort
  let prefix = if $format.1 == "." { [] } else { [$format.1] }
  let expected = [2026-10-28.manifest.json 2026-10-28.ndjson.zst 2026-10-29.manifest.json 2026-10-29.ndjson.zst]
    | each {|f| $prefix | append [node-a $f] | path join }
    | append FORMAT | sort
  assert equal $left $expected

  # A node the store dropped entirely leaves no empty directory.
  rm --recursive $node
  do $export $store $dest
  assert equal (glob ($dest | path join "**" "*") | each { path relative-to $dest } | where $it != "") [FORMAT]

  # A day with a manifest but no data (or a node with an invalid name) is never exported.
  let odd = $store | path join $format.1 "Bad_Node"
  day $odd 2026-10-28 true
  do $export $store $dest
  assert equal (glob ($dest | path join "**" "*") | each { path relative-to $dest } | where $it != "") [FORMAT]
}

# An unknown store format stops the export.
let store = $root | path join unknown
mkdir $store
"other 1\n" | save ($store | path join FORMAT)
let r = do $export $store $root | complete
assert not equal $r.exit_code 0

rm --recursive $root
print "observability-export: ok"
