# azukari export of hanko's ACME account key (backup/azukari.nix): the current key only, as
# `account.key`, replacing the export's previous content. hanko never replaces the key by itself
# (hanko ADR-0008), and azukari's snapshots keep every earlier one.
def main [key: path, dest: path] {
  # Refuses a symlink or a FIFO before reading it: only the key file itself is exported.
  if ($key | path type) != "file" {
    error make { msg: $"($key): not a regular file" }
  }
  let target = $dest | path join account.key
  let temporary = $dest | path join .account.key.tmp
  rm --force $temporary
  ^cp $key $temporary
  ^chmod 0640 $temporary
  try { ^openssl pkey -in $temporary -check -noout } catch {|e| rm --force $temporary; error make $e }
  ^mv $temporary $target
  ls --all $dest | where ($it.name | path basename) != account.key | each { rm --recursive $in.name } | ignore
}
