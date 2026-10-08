# Push mirrors to GitHub: Forgejo is where the owner's repositories live, GitHub keeps an up-to-date
# copy, pushed at every commit (sync_on_commit) and every 8 h otherwise. GitHub stays what a rebuild
# reads from (the bootstrap clones from there, flake inputs point there): rebuilding must never need
# the forge it rebuilds.
#
# Secret (secrets/ishizue/secrets.yaml): forgejo-github-mirror-token, a fine-grained GitHub token
# limited to the mirrored repositories, permission "Contents: read and write". It expires: its date
# is declared below (reminded on jiban), and the oneshot fails when GitHub reports another one, so a
# renewed token can't leave a stale date behind.
#
# Set by a oneshot through the API, idempotent: a mirror already pointing at its GitHub URL is left
# alone, unless the token changed (its hash is kept in Forgejo's state directory), in which case the
# mirrors are recreated with the new one. A repository that does not exist on Forgejo yet is skipped
# (push it, then `systemctl restart forgejo-mirrors`).
{ config, ... }:
let
  inherit (config.kiso) owner;
  githubAccount = "scorsi";
  # Forgejo repository (under the owner's account) → GitHub repository.
  mirrors = {
    sekkeizu = "sekkeizu";
    kanna = "kanna";
    kiso = "kiso";
  };
  tokenExpires = "2026-12-07";
in
{
  sekkeizu.expiringSecrets.github-mirror-token = {
    expires = tokenExpires;
    renew = "nouveau jeton fine-grained (sekkeizu, kanna, kiso ; Contents RW), sops edit secrets/ishizue/secrets.yaml, date dans forgejo-mirrors.nix, deploy";
  };

  flake.modules.nixos.forgejo-mirrors =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.forgejo;
      base = "http://127.0.0.1:${toString cfg.settings.server.HTTP_PORT}/api";
      api = "${base}/v1";
    in
    {
      sops.secrets.forgejo-github-mirror-token.restartUnits = [ "forgejo-mirrors.service" ];

      systemd.services.forgejo-mirrors = {
        description = "Forgejo: push mirrors to GitHub";
        wantedBy = [
          "multi-user.target"
          "forgejo.service"
        ];
        after = [
          "forgejo.service"
          "forgejo-admin.service"
        ];
        partOf = [ "forgejo.service" ];
        path = [
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
          pkgs.gawk
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "forgejo-mirrors";
          User = cfg.user;
          Group = cfg.group;
          LoadCredential = [
            "admin-password:${config.sops.secrets.forgejo-admin-password.path}"
            "github-token:${config.sops.secrets.forgejo-github-mirror-token.path}"
          ];
        };
        script = ''
          for _ in $(seq 120); do
            curl -fsS ${base}/healthz >/dev/null 2>&1 && break
            sleep 1
          done

          # Basic auth over loopback; credentials go through curl configs, not the command line.
          call() {
            curl -sS --config <(printf 'user = "%s:%s"\n' ${lib.escapeShellArg owner.name} "$(< "$CREDENTIALS_DIRECTORY/admin-password")") \
              -H 'Content-Type: application/json' "$@"
          }

          # GitHub states a fine-grained token's expiry on every API answer.
          expiry=$(curl -sS -D - -o /dev/null \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$(< "$CREDENTIALS_DIRECTORY/github-token")") \
            https://api.github.com/repos/${githubAccount}/${mirrors.kanna} |
            tr -d '\r' | awk -F': ' 'tolower($1) == "github-authentication-token-expiration" { print substr($2, 1, 10) }')
          if [ "$expiry" != ${tokenExpires} ]; then
            echo "jeton GitHub : expiration annoncée « ''${expiry:-aucune (jeton refusé ?)} », déclarée ${tokenExpires} dans forgejo-mirrors.nix" >&2
            exit 1
          fi

          token_hash=$(sha256sum < "$CREDENTIALS_DIRECTORY/github-token" | cut -d' ' -f1)
          hash_file=${cfg.stateDir}/github-mirror-token.sha256
          token_changed=no
          [ "$(cat "$hash_file" 2>/dev/null)" = "$token_hash" ] || token_changed=yes

          failed=0
          mirror() {
            local repo=$1 url=$2 code existing
            code=$(call -o "$RUNTIME_DIRECTORY/mirrors.json" -w '%{http_code}' ${api}/repos/${owner.name}/"$repo"/push_mirrors)
            case $code in
              200) ;;
              404) echo "$repo : absent de Forgejo, ignoré (pousse-le puis relance forgejo-mirrors)" >&2; return ;;
              *) echo "$repo : liste des mirrors, HTTP $code" >&2; failed=1; return ;;
            esac

            existing=$(jq -r --arg url "$url" '.[] | select(.remote_address == $url) | .remote_name' "$RUNTIME_DIRECTORY/mirrors.json")
            if [ -n "$existing" ] && [ "$token_changed" = no ]; then
              return
            fi
            for name in $existing; do
              call -o /dev/null -X DELETE ${api}/repos/${owner.name}/"$repo"/push_mirrors/"$name"
            done

            code=$(call -o /dev/null -w '%{http_code}' -X POST ${api}/repos/${owner.name}/"$repo"/push_mirrors \
              -d "$(jq -n --arg url "$url" --arg user ${githubAccount} --rawfile token "$CREDENTIALS_DIRECTORY/github-token" \
                '{remote_address: $url, remote_username: $user, remote_password: ($token | rtrimstr("\n")),
                  interval: "8h0m0s", sync_on_commit: true}')")
            case $code in
              200 | 201) echo "$repo : mirror vers $url configuré" ;;
              *) echo "$repo : création du mirror, HTTP $code" >&2; failed=1 ;;
            esac
          }
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              repo: gh: "mirror ${repo} https://github.com/${githubAccount}/${gh}.git"
            ) mirrors
          )}

          [ "$failed" = 0 ] && printf '%s\n' "$token_hash" > "$hash_file"
          exit "$failed"
        '';
      };
    };
}
