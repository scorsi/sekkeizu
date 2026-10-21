# Off-VM copies of ishizue's backups, PULLED by jiban: ishizue holds no credential to jiban, so a
# compromised VM can neither reach nor rewrite the copies.
#
# ishizue (`backup-source`): a `backup` account whose only key (a plain ed25519 key, not FIDO2: an
# unattended job cannot touch a hardware key) is forced into `rrsync -ro /persist/backups`, and which
# sshd accepts only from the Mac's end of the vfkit NAT bridge.
#
# jiban (`backup-pull`): a daily launchd job rsyncs into `sekkeizu.backups.dir`/ishizue/forgejo,
# keeps 30 days, logs one line per run with the exit code; a failure also raises a notification.
# The private key is in sops (secrets/jiban/secrets.yaml, `backup-pull-key`) rather than generated
# on the Mac: it survives a reinstall through `rekey-host`, so its public key
# (`sekkeizu.backupPullKey`, modules-private/meta/keys.nix) never changes and ishizue needs no redeploy after
# jiban is rebuilt.
#
# `sekkeizu.backups.dir` is the one tree shipped elsewhere: off site by `backup-offsite` (offsite.nix);
# an external disk is not implemented.
{ config, lib, ... }:
let
  inherit (config.kiso) owner;
  user = "backup";
  root = "/persist/backups";
  # jiban's address as seen from the guest, on vfkit's NAT bridge.
  puller = "192.168.64.1";
  publicKey = config.sekkeizu.backupPullKey;
  keepDays = 30;
  storeKeepDays = builtins.fromJSON (builtins.readFile ./observability-retention-days.json);
in
{
  flake.modules.nixos.backup-source =
    { config, pkgs, ... }:
    let
      dump = config.services.forgejo.dump;
    in
    {
      users.users.${user} = {
        isSystemUser = true;
        group = user;
        home = "/var/empty";
        # sshd runs the forced command through the login shell.
        shell = pkgs.bash;
        openssh.authorizedKeys.keys = [
          ''restrict,command="${lib.getExe pkgs.rrsync} -ro ${root}" ${publicKey}''
        ];
      };
      users.groups.${user} = { };

      services.openssh.settings.AllowUsers = [ "${user}@${puller}" ];

      # `forgejo dump` chmods each archive 0600, so neither a group nor a default ACL can open it:
      # grant read access after every dump instead (the + runs this step as root).
      systemd.services.forgejo-dump = lib.mkIf dump.enable {
        serviceConfig.ExecStartPost = [
          "+${pkgs.acl}/bin/setfacl -R -m u:${user}:rX ${dump.backupDir}"
        ];
      };
    };

  flake.modules.darwin.backup-pull =
    { config, pkgs, ... }:
    let
      dir = config.sekkeizu.backups.dir;
      dest = "${dir}/ishizue/forgejo";
      log = "/Users/${owner.name}/Library/Logs/backup-ishizue.log";
      # Last result, one line; its change wakes the notifier agent below.
      status = "${log}.status";
      key = config.sops.secrets.backup-pull-key.path;
      pull = pkgs.writeShellApplication {
        name = "backup-pull-rsync";
        runtimeInputs = [ pkgs.rsync ];
        text = builtins.readFile ./pull-rsync.sh;
      };
    in
    {
      options.sekkeizu.backups.dir = lib.mkOption {
        type = lib.types.str;
        default = "/Users/${owner.name}/Backups";
        description = "Where pulled backups land, one subdirectory per source machine; the tree a future off-site job ships.";
      };

      config = {
        sops.secrets.backup-pull-key.owner = owner.name;

        # A daemon running as the owner, not a LaunchAgent: macOS's Local Network privacy silently
        # blocks agents from reaching the NAT bridge ("No route to host"); daemons are exempt.
        launchd.daemons.backup-ishizue.serviceConfig = {
          UserName = owner.name;
          ProgramArguments = [
            "${pkgs.writers.writeNu "backup-ishizue" ''
              def archives [dest: string] {
                glob --no-dir $"($dest)/**/*"
                  | where { |f| not ('.rsync-partial' in ($f | path split)) }
                  | each { |f| ls $f | first }
              }

              def main [] {
                let dest = "${dest}"
                mkdir $dest

                # -F none: none of the interactive settings for ishizue (agent forwarding, shared
                # connection) apply; the host key is still checked against ~/.ssh/known_hosts.
                let rsync = ^${lib.getExe pull} -e "${pkgs.openssh}/bin/ssh -F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30" ${user}@ishizue.local:forgejo/ $"($dest)/" | complete
                print --stderr --no-newline $rsync.stderr
                mut code = $rsync.exit_code

                if $code == 0 {
                  # ishizue dumps at 04:31: a successful pull with nothing from the last day is a failure too.
                  if (archives $dest | where modified > ((date now) - 26hr) | is-empty) {
                    print --stderr "no dump less than 26 h old"
                    $code = 100
                  } else {
                    # Pruned only after a good pull: a broken source never empties the copies.
                    archives $dest | where modified < ((date now) - ${toString keepDays}day) | each { |f| rm $f.name } | ignore
                  }
                }

                # Only a successful, complete pull permits retention; manifests keep nisshi's chain.
                if $code == 0 {
                  for store in [masu nisshi] {
                    let r = ^${lib.getExe pull} -e "${pkgs.openssh}/bin/ssh -F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30" $"${user}@ishizue.local:($store)/" $"${dir}/ishizue/($store)/" | complete
                    print --stderr --no-newline $r.stderr
                    if $r.exit_code != 0 {
                      $code = $r.exit_code
                    } else {
                      let retained = ^${pkgs.python3}/bin/python3 ${./observability-archives.py} prune $"${dir}/ishizue/($store)" ${toString storeKeepDays} | complete
                      print --stderr --no-newline $retained.stderr
                      if $retained.exit_code != 0 { $code = $retained.exit_code }
                    }
                  }
                }

                # Account identities have no time-based expiry: CAA may still pin an older one.
                let hanko = "${dir}/ishizue/hanko"
                let h = ^${lib.getExe pull} -e "${pkgs.openssh}/bin/ssh -F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30" ${user}@ishizue.local:hanko/ $"($hanko)/" | complete
                print --stderr --no-newline $h.stderr
                if $h.exit_code != 0 {
                  $code = $h.exit_code
                } else if (glob --no-dir $"($hanko)/account-*.key" | is-empty) {
                  print --stderr "no Hanko account backup"
                  $code = 101
                }

                let n = archives $dest | length
                let result = if $code == 0 { "ok" } else { "FAILED" }
                let line = $"(date now | format date '%F %T') ($result) exit=($code) \(($n) archives\)"
                print --stderr $line
                $line | save --force "${status}"
                exit $code
              }
            ''}"
          ];
          # Appended to by launchd, which nu can't redirect its own stderr to.
          StandardErrorPath = log;
          StartCalendarInterval = [
            {
              Hour = 5;
              Minute = 15;
            }
          ];
        };

        # A daemon can't post to the owner's session: this agent does, whenever the status changes.
        launchd.user.agents.backup-ishizue-notify.serviceConfig = {
          ProgramArguments = [
            "${pkgs.writers.writeNu "backup-ishizue-notify" ''
              def main [] {
                if not ("${status}" | path exists) { return }
                let line = open --raw "${status}" | str trim
                if ($line | str contains FAILED) {
                  ^/usr/bin/osascript -e $"display notification \"($line) — see ${log}\" with title \"ishizue backup failed\""
                }
              }
            ''}"
          ];
          WatchPaths = [ status ];
        };
      };
    };
}
