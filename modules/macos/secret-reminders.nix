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
      check = pkgs.writeShellScript "secret-reminders" ''
        now=$(/bin/date -u +%s)
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: s: ''
            left=$(( ($(/bin/date -j -u -f '%Y-%m-%d %H:%M:%S' '${s.expires} 00:00:00' +%s) - now) / 86400 ))
            if [ "$left" -le ${toString days} ]; then
              if [ "$left" -lt 0 ]; then msg="${name} a expiré le ${s.expires}"; else msg="${name} expire dans $left j (${s.expires})"; fi
              echo "!! $msg : ${s.renew}" >&2
              [ "''${1:-}" = notify ] && /usr/bin/osascript -e "display notification \"${s.renew}\" with title \"$msg\""
            fi
          '') secrets
        )}
        exit 0
      '';
    in
    {
      launchd.user.agents.secret-reminders.serviceConfig = {
        ProgramArguments = [
          "${check}"
          "notify"
        ];
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
