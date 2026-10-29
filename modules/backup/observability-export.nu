# azukari export of masu's or nisshi's closed days (backup/azukari.nix, azukari ADR 0022), run as
# the store's own user. A day is closed once its manifest exists, and its files never change again:
# each gets the export's group and mode 0640, then a hard link in the export directory (no extra
# space). The open day is never exported: it is still appended to. The export mirrors the store:
# links of days the store's own retention dropped go too, and azukari's snapshots keep them.
# FORMAT is copied, not linked: the store's own file keeps its group.
def main [store: path, dest: path, group: string] {
  let base = match (open --raw ($store | path join FORMAT)) {
    "masu-archive 1\n" => "archive"
    "nisshi-store 1\n" => "."
    _ => { error make { msg: $"($store)/FORMAT: unknown store format" } }
  }
  # A link across filesystems fails (EXDEV); say why rather than leave a half export.
  if (^stat -c %d $store) != (^stat -c %d $dest) {
    error make { msg: $"($store) and ($dest) are on different filesystems: cannot hard-link" }
  }

  let days = glob --no-dir --no-symlink ($store | path join $base "*" "*.manifest.json")
    | each {|manifest|
      let node = $manifest | path dirname | path basename
      let day = $manifest | path basename | str replace ".manifest.json" ""
      let data = $manifest | path dirname | path join $"($day).ndjson.zst"
      if ($node =~ '^[a-z0-9][a-z0-9-]{0,62}$') and ($day =~ '^\d{4}-\d{2}-\d{2}$') and ($data | path type) == "file" {
        # Data before manifest: an interrupted run never leaves a manifest without its data.
        [$data $manifest]
      }
    }
    | flatten

  for file in $days {
    let info = ls --long $file | first
    if $info.group != $group { ^chgrp $group $file }
    if $info.mode != "rw-r-----" { ^chmod 0640 $file }
    let target = $dest | path join ($file | path relative-to $store)
    if not ($target | path exists) {
      mkdir ($target | path dirname)
      ^ln $file $target
    }
  }

  let format = $dest | path join FORMAT
  if not ($format | path exists) or (open --raw $format) != (open --raw ($store | path join FORMAT)) {
    ^cp ($store | path join FORMAT) $format
  }

  let wanted = $days | each { path relative-to $store } | append FORMAT
  glob --no-dir ($dest | path join "**" "*")
    | where { ($in | path relative-to $dest) not-in $wanted }
    | each { rm $in }
    | ignore
  # Nodes left empty, deepest first.
  glob --no-file ($dest | path join "**" "*")
    | where ($it | path relative-to $dest) != ""
    | sort --reverse
    | where { ls --all $in | is-empty }
    | each { rm $in }
    | ignore
}
