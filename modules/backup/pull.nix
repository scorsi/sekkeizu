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
# on the Mac: it survives a reinstall through `rekey-host`, so the public key below never changes
# and ishizue needs no redeploy after jiban is rebuilt.
#
# Next steps, not implemented: `sekkeizu.backups.dir` is the one tree to ship elsewhere, first to an
# external disk, then off site with restic (a `backup-offsite` feature reading the same option).
{ config, lib, ... }:
let
  inherit (config.kiso) owner;
  user = "backup";
  root = "/persist/backups";
  # jiban's address as seen from the guest, on vfkit's NAT bridge.
  puller = "192.168.64.1";
  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHILNV6rStmSb0Df/qkprQRP4WZ6hWrepWIqE4LFAxd backup@jiban";
  keepDays = 30;
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
            "${pkgs.writeShellScript "backup-ishizue" ''
              set -uo pipefail
              mkdir -p ${lib.escapeShellArg dest}
              exec 2>>${lib.escapeShellArg log}

              # -F none: none of the interactive settings for ishizue (agent forwarding, shared
              # connection) apply; the host key is still checked against ~/.ssh/known_hosts.
              ${lib.getExe pkgs.rsync} -rt --chmod=D700,F600 \
                -e "${pkgs.openssh}/bin/ssh -F none -i ${key} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=30" \
                ${user}@ishizue.local:forgejo/ ${lib.escapeShellArg dest}/
              code=$?

              if [ "$code" -eq 0 ]; then
                # ishizue dumps at 04:31: a successful pull with nothing from the last day is a failure too.
                if [ -z "$(find ${lib.escapeShellArg dest} -type f -mmin -$((26 * 60)) | head -1)" ]; then
                  echo "aucun dump de moins de 26 h" >&2
                  code=100
                else
                  # Pruned only after a good pull: a broken source never empties the copies.
                  find ${lib.escapeShellArg dest} -type f -mtime +${toString keepDays} -delete
                fi
              fi

              n=$(find ${lib.escapeShellArg dest} -type f | wc -l | tr -d ' ')
              if [ "$code" -eq 0 ]; then
                line="$(date '+%F %T') ok exit=0 ($n archives)"
              else
                line="$(date '+%F %T') ÉCHEC exit=$code ($n archives)"
              fi
              echo "$line" >&2
              echo "$line" > ${lib.escapeShellArg status}
              exit "$code"
            ''}"
          ];
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
            "${pkgs.writeShellScript "backup-ishizue-notify" ''
              line=$(cat ${lib.escapeShellArg status} 2>/dev/null) || exit 0
              case "$line" in
                *ÉCHEC*) /usr/bin/osascript -e "display notification \"$line — voir ${log}\" with title \"Sauvegarde ishizue en échec\"" ;;
              esac
            ''}"
          ];
          WatchPaths = [ status ];
        };
      };
    };
}
