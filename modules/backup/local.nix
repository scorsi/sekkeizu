# Local copy of `sekkeizu.backups.dir` (declared by backup-pull, which must be imported too): restic
# to the USB hard disk plugged into jiban, a second medium next to the SSD, restorable without the
# network. Same repository password as backup-offsite (restic-password in sops).
#
# jiban (`backup-local`): a launchd job at 05:45 and 17:45, 30 minutes after each pull, so the local
# RPO matches the pull's 12 h. It runs only when the volume carries the `.backup-local` marker: an
# unplugged disk leaves an empty /Volumes path, and restic would fill the SSD there. A missing disk
# is a failure, notified like the others. Creates the repository on its first run, backs up the
# whole tree, thins the snapshots, and on Sundays reads back 5% of the data to catch a dying disk
# (SMART does not reliably cross the USB bridge).
#
# The disk: APFS volume `ishizue-backup`, with `.metadata_never_index` (no Spotlight) and `.backup-local` at
# its root (README, Backups).
{ config, lib, ... }:
let
  inherit (config.kiso) owner;
  volume = "/Volumes/ishizue-backup";
in
{
  flake.modules.darwin.backup-local =
    { config, pkgs, ... }:
    let
      log = "/Users/${owner.name}/Library/Logs/backup-local.log";
      status = "${log}.status";
    in
    {
      sops.secrets.restic-password.owner = owner.name;

      # A daemon running as the owner, like backup-pull: it runs without a session.
      launchd.daemons.backup-local = {
        command = "${pkgs.writers.writeNu "backup-local" ''
          # Runs restic, its output to the log; returns the exit code.
          def --wrapped restic [...args: string] {
            let r = ^${lib.getExe pkgs.restic} ...$args | complete
            print --stderr --no-newline $r.stdout $r.stderr
            $r.exit_code
          }

          def main [] {
            $env.RESTIC_REPOSITORY = "${volume}/restic"
            $env.RESTIC_PASSWORD_FILE = "${config.sops.secrets.restic-password.path}"

            mut code = 0
            mut why = ""
            if not ("${volume}/.backup-local" | path exists) {
              $code = 1
              $why = " disk not mounted"
            }
            if $code == 0 { $code = restic cat config }
            # 10: no repository there yet, the first run creates it.
            if $code == 10 { $code = restic init }
            if $code == 0 { $code = restic backup --no-scan --quiet "${config.sekkeizu.backups.dir}" }
            # 3: some file could not be read; the snapshot exists but the run still counts as failed.
            if $code == 0 {
              $code = restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12
            }
            if $code == 0 and (date now | format date '%u') == "7" and (date now | format date '%H') == "05" {
              $code = restic check --read-data-subset "5%"
            }

            let result = if $code == 0 { "ok" } else { "FAILED" }
            let line = $"(date now | format date '%F %T') ($result) exit=($code)($why)"
            print --stderr $line
            $line | save --force "${status}"
            exit $code
          }
        ''}";
        serviceConfig = {
          UserName = owner.name;
          StandardErrorPath = log;
          StartCalendarInterval = [
            {
              Hour = 5;
              Minute = 45;
            }
            {
              Hour = 17;
              Minute = 45;
            }
          ];
        };
      };

      launchd.user.agents.backup-local-notify = {
        command = "${pkgs.writers.writeNu "backup-local-notify" ''
          def main [] {
            if not ("${status}" | path exists) { return }
            let line = open --raw "${status}" | str trim
            if ($line | str contains FAILED) {
              ^/usr/bin/osascript -e $"display notification \"($line) — see ${log}\" with title \"local backup failed\""
            }
          }
        ''}";
        serviceConfig = {
          WatchPaths = [ status ];
        };
      };
    };
}
