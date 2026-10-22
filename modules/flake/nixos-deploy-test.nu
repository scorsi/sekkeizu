source ./nixos-deploy.nu
use std/assert

# Fake ssh: one line of $FAKE/script per remote call: `255` drops the connection, `-` succeeds
# silently, anything else is printed as the remote output.
def --env fakes [] {
  let sh = which sh | get path.0
  mkdir bin
  $"#!($sh)
if [ \"$1\" = -G ]; then echo 'controlpath /tmp/cm-test'; exit 0; fi
n=$\(\($\(cat \"$FAKE/n\" 2>/dev/null || echo 0\) + 1\)\)
echo \"$n\" > \"$FAKE/n\"
shift
echo \"$*\" >> \"$FAKE/calls\"
cat > \"$FAKE/stdin-$n\"
line=$\(sed -n \"$n p\" \"$FAKE/script\"\)
case \"$line\" in
  255\) exit 255;;
  -\) exit 0;;
  *\) echo \"$line\";;
esac
" | save --force bin/ssh
  $"#!($sh)
echo \"$NIX_SSHOPTS\" > \"$FAKE/sshopts\"
echo \"$*\" > \"$FAKE/rebuild\"
echo /nix/store/abc-nixos-system
" | save --force bin/nixos-rebuild
  ^chmod +x bin/ssh bin/nixos-rebuild
  $env.PATH = $env.PATH | prepend ($env.PWD | path join bin)
}

def scenario [name: string, script: list<string>] {
  let dir = $env.PWD | path join $name
  mkdir $dir
  $script | str join "\n" | save --force ($dir | path join script)
  $dir
}

def main [] {
  # The remote scripts must at least parse as POSIX sh.
  $deploy_launch | ^sh -n
  $deploy_wait | ^sh -n

  assert equal (deploy-result u "0").code 0
  assert equal (deploy-result u "3").code 3
  assert equal (deploy-result u "lost").code 1
  assert ((deploy-result u "lost").message | str contains "without a status")
  assert equal (deploy-result u "garbage").code 1

  fakes
  let exe = $nu.current-exe
  let deploy = { |args: list| ^$exe --no-config-file -c $"source nixos-deploy.nu; deploy ($args | each { to nuon } | str join ' ')" | complete }

  # Dropped once while waiting, then the status arrives: the client reconnects and exits with it.
  $env.FAKE = scenario reconnect [- 255 3]
  let r = do $deploy [root@host '.#host' --show-trace]
  assert equal $r.exit_code 3 $r.stderr
  assert ($r.stderr | str contains "retrying")
  assert equal (open --raw reconnect/sshopts | str trim) "-o ControlPath=/tmp/cm-test"
  assert equal (open --raw reconnect/rebuild | str trim) "build --no-link --flake .#host --build-host root@host --target-host root@host --show-trace"
  let calls = open --raw reconnect/calls | lines
  assert ($calls.0 =~ '^/bin/sh -s -- sekkeizu-switch-\d{8}-\d{6} /nix/store/abc-nixos-system$')
  assert ($calls.1 =~ '^/bin/sh -s -- sekkeizu-switch-\d{8}-\d{6}$')
  assert equal $calls.1 $calls.2
  assert equal (open --raw reconnect/stdin-1) $deploy_launch
  assert equal (open --raw reconnect/stdin-2) $deploy_wait

  # Rollback: nothing is built, the unit rolls the profile back.
  $env.FAKE = scenario rollback [- 0]
  let r = do $deploy [root@host '.#host' --rollback]
  assert equal $r.exit_code 0 $r.stderr
  assert (not ("rollback/rebuild" | path exists))
  assert ((open --raw rollback/calls | lines).0 =~ '^/bin/sh -s -- sekkeizu-switch-\d{8}-\d{6} ?$')

  # Launch failure: no wait.
  $env.FAKE = scenario launch-failed [255]
  let r = do $deploy [root@host '.#host']
  assert ($r.exit_code != 0)
  assert equal (open --raw launch-failed/calls | lines | length) 1

  # The wait gives up after its deadline.
  $env.FAKE = scenario timeout [255 255]
  let r = deploy-wait root@host u 0sec
  assert equal $r.code 1
  assert ($r.message | str contains "may still be running")
}
