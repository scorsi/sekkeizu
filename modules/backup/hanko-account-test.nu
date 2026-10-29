use std/assert

let root = mktemp --directory
cd $root
let script = $env.HANKO_ACCOUNT_SCRIPT
let export = {|key: string| ^nu --no-config-file $script $key dest | complete }
mkdir dest
^openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out account.key
# The previous run's layout (one file per digest) is replaced too.
"old" | save dest/account-0000.key

assert equal (do $export account.key).exit_code 0
assert equal (open --raw dest/account.key) (open --raw account.key)
assert equal (ls --long dest/account.key | first | get mode) "rw-r-----"
assert equal (ls --all dest | get name | path basename) [account.key]

# A new key replaces the old one: azukari's snapshots keep it.
^openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out account.key
assert equal (do $export account.key).exit_code 0
assert equal (open --raw dest/account.key) (open --raw account.key)

# Never exported: an invalid key, a missing one, a symlink, a FIFO (without blocking on it).
let current = open --raw dest/account.key
"invalid" | save invalid.key
^ln -s account.key symlink.key
^mkfifo fifo.key
for bad in [invalid.key missing.key symlink.key fifo.key] {
  assert not equal (do $export $bad).exit_code 0
  assert equal (open --raw dest/account.key) $current
  assert equal (ls --all dest | get name | path basename) [account.key]
}

cd /
rm --recursive $root
print "hanko-account: ok"
