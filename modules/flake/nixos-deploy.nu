# Detached NixOS deploy (kekkai ADR 0026, option 2). nixos-rebuild only builds (on the build
# host, copied to the target); the profile is set and switch-to-configuration runs inside a
# transient systemd unit on the target, so the activation finishes even if a kekkai-node restart
# cuts the SSH session. The client follows the unit's journal and reconnects to read its status.
# Needs nixos-rebuild and ssh on PATH.

# Runs on the target. $1 unit, $2 system path ('' = roll the profile back).
const deploy_launch = r#'
set -eu
# ssh joins arguments with spaces, so an empty $2 does not arrive at all.
unit=$1 toplevel=${2-}
dir=/run/sekkeizu-deploy profile=/nix/var/nix/profiles/system
if [ -n "$toplevel" ]; then
  # nixos-rebuild's own guard before setting the profile (NixOS/nix#13367).
  test -f "$toplevel/nixos-version"
  set -- --set "$toplevel"
  new=$toplevel
else
  set -- --rollback
  new=$profile
fi
mkdir -p "$dir"
# Profile and switch in the same unit: a dropped session cannot leave one without the other.
systemd-run --unit="$unit" --collect --no-ask-password --quiet --service-type=exec \
  --expand-environment=no -E PATH ${LOCALE_ARCHIVE:+-E LOCALE_ARCHIVE} \
  /bin/sh -c 'status=$1 profile=$2 new=$3
shift 3
nix-env -p "$profile" "$@" && "$new/bin/switch-to-configuration" switch
s=$?
echo "$s" > "$status.tmp" && mv "$status.tmp" "$status"
exit "$s"' sh "$dir/$unit.status" "$profile" "$new" "$@"
'#

# Runs on the target. $1 unit. Log on stderr, then the exit status (or `lost`) on stdout.
const deploy_wait = r#'
unit=$1 status=/run/sekkeizu-deploy/$1.status
journalctl --follow --lines=all --output=cat --unit="$unit" >&2 &
log=$!
# The unit writes its status before exiting: inactive without one means it was killed.
while [ ! -e "$status" ] && systemctl is-active --quiet "$unit"; do sleep 1; done
sleep 1
kill "$log" 2>/dev/null
if [ -e "$status" ]; then cat "$status"; else echo lost; fi
'#

# Remote shell independent of root's login shell; `null` when ssh or the script failed.
def deploy-remote [host: string, script: string, ...args: string] {
  try { $script | ^ssh $host /bin/sh -s -- ...$args | str trim } catch { null }
}

# Exit code and message for what the wait script printed.
def deploy-result [unit: string, status: string] {
  if $status == "0" { return {code: 0, message: $"($unit) succeeded."} }
  let code = try { $status | into int } catch { 1 }
  let why = if $status == "lost" { "ended without a status (killed, or the host rebooted)" } else { $"failed with status ($status)" }
  {code: $code, message: $"($unit) ($why); see `journalctl -u ($unit)` on the target."}
}

# Polls until a status arrives, reconnecting with backoff for at most `timeout`.
def deploy-wait [host: string, unit: string, timeout: duration] {
  let deadline = (date now) + $timeout
  mut delay = 1sec
  loop {
    let status = deploy-remote $host $deploy_wait $unit
    if $status != null and $status != "" { return (deploy-result $unit $status) }
    if (date now) > $deadline {
      return {code: 1, message: $"lost contact with ($host); ($unit) may still be running: check `systemctl status ($unit)` there."}
    }
    print --stderr $"connection to ($host) lost, retrying in ($delay) \(the full log is replayed\)..."
    sleep $delay
    $delay = [($delay * 2) 15sec] | math min
  }
}

def --wrapped deploy [host: string, flake: string, ...args: string] {
  # nixos-rebuild forces its own ControlPath; ours comes first in NIX_SSHOPTS and wins, so the
  # build and the activation share the master of ssh-hosts.nix: still one FIDO2 touch.
  let control = ^ssh -G $host | lines | parse "{key} {value}" | where key == controlpath | get value.0? | default none
  if $control != none {
    $env.NIX_SSHOPTS = $"($env.NIX_SSHOPTS? | default '') -o ControlPath=($control)" | str trim
  }
  # No --no-link: with --build-host, nixos-rebuild-ng also passes build flags to `nix eval`, which
  # rejects it; the build host keeps a `result` link in root's home, harmless.
  let toplevel = if "--rollback" in $args { "" } else {
    ^nixos-rebuild build --flake $flake --build-host $host --target-host $host ...$args | str trim
  }
  let unit = $"sekkeizu-switch-(date now | format date '%Y%m%d-%H%M%S')"
  if (deploy-remote $host $deploy_launch $unit $toplevel) == null {
    print --stderr $"could not start ($unit) on ($host); check `systemctl status ($unit)` there."
    exit 1
  }
  print --stderr $"activating in ($unit) on ($host)..."
  let result = deploy-wait $host $unit 3min
  print --stderr $result.message
  exit $result.code
}
