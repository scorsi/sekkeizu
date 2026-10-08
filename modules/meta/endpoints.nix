# The one place that says where the services live. For now: one Tailscale name for the whole
# machine, services told apart by port. With a real domain, point `host` at e.g. git.lab.<domain>
# and the port back to 443; Caddy, Forgejo's ROOT_URL and the runners follow.
# (Caddy's Tailscale certificates only exist for *.ts.net names: a real domain needs ACME.)
_:
let
  # Tailnet name: admin console → DNS. Node name = hostname, hence `ishizue`.
  tailnet = "tail9883f3.ts.net";
  host = "ishizue.${tailnet}";
in
{
  sekkeizu.services = {
    forgejo = {
      inherit host;
      # ishizue's Tailscale IP (`tailscale ip -4 ishizue`): stable as long as the node is not re-registered.
      address = "REDACTED";
      port = 443;
    };
    forgejo-ssh = {
      inherit host;
      scheme = "ssh";
      port = 2222;
      # Forgejo's built-in SSH server (its key lives in Forgejo's state, it survives restarts).
      hostKey = "ssh-rsa REDACTED";
    };
    site = {
      inherit host;
      port = 8443;
    };
  };

  # Private flakes on Forgejo that CI fetches (the `scorsi-*` inputs of flake.nix).
  sekkeizu.forgejoCi = {
    readKey = "ssh-ed25519 REDACTED forgejo-ci";
    readRepos = [
      "kiso"
      "kanna"
    ];
  };

  sekkeizu.forgejoRunners = {
    ishizue.labels = [ "linux:host" ];
    jiban.labels = [ "macos:host" ];
  };
}
