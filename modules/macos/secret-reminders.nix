# Reminders for sekkeizu.expiringSecrets, on jiban because it is the machine with a screen: a daily
# LaunchAgent posts a notification from `days` days before the date (and every day once expired),
# and every switch prints the same warning. Nix itself can't do it at evaluation: no clock in a
# pure flake.
{ config, lib, ... }:
let
  secrets = config.sekkeizu.expiringSecrets;
  days = 30;
in
{
  flake.modules.darwin.secret-reminders =
    { pkgs, ... }:
    let
      # Prints one line per secret within `days` days of its date; "notify" also posts it.
      check = pkgs.writers.writeNu "secret-reminders" ''
        def main [mode?: string] {
          let secrets = open ${pkgs.writeText "expiring-secrets.json" (builtins.toJSON secrets)}
          for name in ($secrets | columns) {
            let s = $secrets | get $name
            let left = (($"($s.expires)T00:00:00Z" | into datetime) - (date now)) / 1day | math floor
            if $left <= ${toString days} {
              let msg = if $left < 0 { $"($name) expired on ($s.expires)" } else { $"($name) expires in ($left) d \(($s.expires)\)" }
              print --stderr $"!! ($msg): ($s.renew)"
              if $mode == "notify" {
                # A failed notification must not fail the switch.
                try { ^/usr/bin/osascript -e $"display notification \"($s.renew)\" with title \"($msg)\"" }
              }
            }
          }
        }
      '';
    in
    {
      # `command` waits for /nix/store (see vfkit-host.nix).
      launchd.user.agents.secret-reminders.command = "${check} notify";
      launchd.user.agents.secret-reminders.serviceConfig = {
        StartCalendarInterval = [
          {
            Hour = 10;
            Minute = 0;
          }
        ];
      };

      system.activationScripts.postActivation.text = lib.mkAfter "${check}";
    };
}
