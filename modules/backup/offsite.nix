# Off-site copy of `sekkeizu.backups.dir` (declared by backup-pull, which must be imported too):
# restic over SFTP to the Hetzner Storage Box (infra/stacks/storage), as its `backup` subaccount.
#
# jiban (`backup-offsite`): a daily launchd job at 06:00, after the 05:15 pull, creates the
# repository on its first run, backs up the whole tree, then thins the snapshots. One line per run in
# the log, a notification on failure, like backup-pull.
#
# The SSH key is backup-pull-key: one plain ed25519 key for jiban's unattended backup jobs, whose
# public half goes by hand into the subaccount's .ssh/authorized_keys (README, Infrastructure).
# The repository password is restic-password in sops: without it the copy is unreadable, and
# secrets/jiban/ survives jiban (FIDO2 and admin recipients).
#
# Deleting snapshots here does not reach the box's own weekly snapshots (.zfs/), so a compromised
# jiban cannot wipe the history.
{ config, lib, ... }:
let
  inherit (config.kiso) owner;
  box = config.sekkeizu.services.backup-offsite;
  # A subaccount's login is the first label of its host name (u123456-sub1.your-storagebox.de).
  user = builtins.head (lib.splitString "." box.host);
in
{
  flake.modules.darwin.backup-offsite =
    { config, pkgs, ... }:
    let
      log = "/Users/${owner.name}/Library/Logs/backup-offsite.log";
      status = "${log}.status";
      key = config.sops.secrets.backup-pull-key.path;
    in
    {
      sops.secrets.restic-password.owner = owner.name;

      programs.ssh.knownHosts.backup-offsite = {
        hostNames = [ "[${box.host}]:${toString box.port}" ];
        publicKey = box.hostKey;
      };

      # A daemon running as the owner, like backup-pull: it runs without a session.
      launchd.daemons.backup-offsite.serviceConfig = {
        UserName = owner.name;
        ProgramArguments = [
          "${pkgs.writers.writeNu "backup-offsite" ''
            # Runs restic, its output to the log; returns the exit code.
            def --wrapped restic [...args: string] {
              let r = ^${lib.getExe pkgs.restic} -o "sftp.args=-F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=60" ...$args | complete
              print --stderr --no-newline $r.stdout $r.stderr
              $r.exit_code
            }

            def main [] {
              $env.RESTIC_REPOSITORY = "sftp://${user}@${box.host}:${toString box.port}/restic"
              $env.RESTIC_PASSWORD_FILE = "${config.sops.secrets.restic-password.path}"

              mut code = restic cat config
              # 10: no repository there yet, the first run creates it.
              if $code == 10 { $code = restic init }
              if $code == 0 { $code = restic backup --no-scan --quiet "${config.sekkeizu.backups.dir}" }
              # 3: some file could not be read; the snapshot exists but the run still counts as failed.
              if $code == 0 {
                $code = restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12
              }

              let result = if $code == 0 { "ok" } else { "FAILED" }
              let line = $"(date now | format date '%F %T') ($result) exit=($code)"
              print --stderr $line
              $line | save --force "${status}"
              exit $code
            }
          ''}"
        ];
        StandardErrorPath = log;
        StartCalendarInterval = [
          {
            Hour = 6;
            Minute = 0;
          }
        ];
      };

      launchd.user.agents.backup-offsite-notify.serviceConfig = {
        ProgramArguments = [
          "${pkgs.writers.writeNu "backup-offsite-notify" ''
            def main [] {
              if not ("${status}" | path exists) { return }
              let line = open --raw "${status}" | str trim
              if ($line | str contains FAILED) {
                ^/usr/bin/osascript -e $"display notification \"($line) — see ${log}\" with title \"off-site backup failed\""
              }
            }
          ''}"
        ];
        WatchPaths = [ status ];
      };
    };
}
