# Off-VM copies of ishizue's backups, PULLED by jiban: ishizue holds no credential to jiban. A
# compromised VM can still send bad NEW files, stop exporting, or rewrite what is replaced at every
# pull (an open day's .partial, LAST_RUN); it cannot change a file jiban already received: those
# are final (--ignore-existing), and a source that changed one is reported as a failure, never
# applied (pull-rsync.sh). restic's earlier snapshots (offsite.nix) are the history beyond that.
#
# ishizue (`backup-source`): a `backup` account whose only key (a plain ed25519 key, not FIDO2: an
# unattended job cannot touch a hardware key) is forced into `rrsync -ro /persist/backups`, and which
# sshd accepts only from the Mac's end of the vfkit NAT bridge.
#
# jiban (`backup-pull`): a launchd job, twice a day, rsyncs forgejo, masu, nisshi and hanko into
# `sekkeizu.backups.dir`/ishizue, each on its own; keeps 30 days of Forgejo dumps; fails a store
# whose export (LAST_RUN) is older than 14 h or lists a sealed file missing here. One line per run
# with the failed sources; a failure also raises a notification.
# The private key is in sops (secrets/jiban/secrets.yaml, `backup-pull-key`) rather than generated
# on the Mac: it survives a reinstall through `rekey-host`, so its public key
# (`sekkeizu.backupPullKey`, modules-private/meta/keys.nix) never changes and ishizue needs no redeploy after
# jiban is rebuilt.
#
# Trust: the job runs as the owner, so root (or the owner) on jiban reaches every copy and the
# key; a dedicated local pull account is future work.
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
      forgejo = config.services.forgejo;
      dump = forgejo.dump;
      staging = "/persist/forgejo-dump";
      publish = pkgs.writeShellApplication {
        name = "forgejo-dump-publish";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.acl
        ];
        text = builtins.readFile ./forgejo-dump-publish.sh;
      };
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

      assertions = lib.optionals dump.enable [
        {
          assertion =
            dump.file == null
            || (
              builtins.baseNameOf dump.file == dump.file
              && !(builtins.elem dump.file [
                ""
                "."
                ".."
                "-"
              ])
            );
          message = "Forgejo dump.file must be a basename so the dump stays in private staging.";
        }
      ];

      # Staging stays outside rrsync's root; interrupted dumps must never become immutable copies.
      systemd.tmpfiles.rules = lib.optionals dump.enable [
        "d ${staging} 0700 ${forgejo.user} ${forgejo.group} ${dump.age} -"
      ];
      systemd.services.forgejo-dump = lib.mkIf dump.enable {
        serviceConfig = {
          ExecStart = lib.mkForce (
            "${lib.getExe publish} ${
              lib.escapeShellArgs [
                staging
                dump.backupDir
                user
              ]
            } "
            + "${lib.getExe forgejo.package} dump --type ${dump.type}"
            + lib.optionalString (dump.file != null) " --file ${lib.escapeShellArg dump.file}"
          );
        };
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
        launchd.daemons.backup-ishizue = {
          command = "${pkgs.writers.writeNu "backup-ishizue" ''
            def archives [dest: string] {
              glob --no-dir $"($dest)/**/*"
                | where { |f| not ('.rsync-partial' in ($f | path split)) }
                | each { |f| ls $f | first }
            }

            # rsync of ishizue's `what` into `into`; returns its exit code (102: the source changed
            # a file already received here, which was kept).
            def pull [what: string, into: string] {
              mkdir $into
              # -F none: none of the interactive settings for ishizue (agent forwarding, shared
              # connection) apply; the host key is still checked against ~/.ssh/known_hosts.
              let r = ^${lib.getExe pull} -e "${pkgs.openssh}/bin/ssh -F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30" $"${user}@ishizue.local:($what)/" $"($into)/" | complete
              print --stderr --no-newline $r.stderr
              $r.exit_code
            }

            # Each source on its own: one failing never keeps the others from being copied.
            def main [] {
              mut failed = []

              let dest = "${dest}"
              let f = pull forgejo $dest
              if $f != 0 {
                $failed = $failed | append $"forgejo=($f)"
              } else if (archives $dest | where modified > ((date now) - 26hr) | is-empty) {
                # ishizue dumps at 04:31: a successful pull with nothing from the last day is a failure too.
                print --stderr "no dump less than 26 h old"
                $failed = $failed | append "forgejo=100"
              } else {
                # Pruned only after a good pull: a broken source never empties the copies.
                archives $dest | where modified < ((date now) - ${toString keepDays}day) | each { |f| rm $f.name } | ignore
              }

              for store in [masu nisshi] {
                let into = $"${dir}/ishizue/($store)"
                let r = pull $store $into
                if $r != 0 {
                  $failed = $failed | append $"($store)=($r)"
                  continue
                }
                # Retention only after a fresh, complete pull: the export ran less than 14 h ago
                # (twice a day) and every sealed file it lists is here. Manifests keep nisshi's chain.
                let checked = ^${pkgs.python3}/bin/python3 ${./observability-archives.py} pulled $into ${toString storeKeepDays} 14 | complete
                print --stderr --no-newline $checked.stderr
                if $checked.exit_code != 0 { $failed = $failed | append $"($store)=check" }
              }

              # Account identities have no time-based expiry: CAA may still pin an older one.
              let hanko = "${dir}/ishizue/hanko"
              let h = pull hanko $hanko
              if $h != 0 {
                $failed = $failed | append $"hanko=($h)"
              } else if (glob --no-dir $"($hanko)/account-*.key" | is-empty) {
                print --stderr "no Hanko account backup"
                $failed = $failed | append "hanko=101"
              }

              let n = archives $dest | length
              let result = if ($failed | is-empty) { "ok" } else { $"FAILED ($failed | str join ' ')" }
              let line = $"(date now | format date '%F %T') ($result) \(($n) archives\)"
              print --stderr $line
              $line | save --force "${status}"
              exit (if ($failed | is-empty) { 0 } else { 1 })
            }
          ''}";
          serviceConfig = {
            UserName = owner.name;
            # Appended to by launchd, which nu can't redirect its own stderr to.
            StandardErrorPath = log;
            # 30 min after each of ishizue's exports (observability/stores.nix).
            StartCalendarInterval = [
              {
                Hour = 5;
                Minute = 15;
              }
              {
                Hour = 17;
                Minute = 15;
              }
            ];
          };
        };

        # A daemon can't post to the owner's session: this agent does, whenever the status changes.
        launchd.user.agents.backup-ishizue-notify = {
          command = "${pkgs.writers.writeNu "backup-ishizue-notify" ''
            def main [] {
              if not ("${status}" | path exists) { return }
              let line = open --raw "${status}" | str trim
              if ($line | str contains FAILED) {
                ^/usr/bin/osascript -e $"display notification \"($line) — see ${log}\" with title \"ishizue backup failed\""
              }
            }
          ''}";
          serviceConfig = {
            WatchPaths = [ status ];
          };
        };
      };
    };
}
