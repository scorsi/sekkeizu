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
      address = "100.108.175.2";
      port = 443;
    };
    forgejo-ssh = {
      inherit host;
      scheme = "ssh";
      port = 2222;
      # Forgejo's built-in SSH server (its key lives in Forgejo's state, it survives restarts).
      hostKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfvN7jb9RDzATcQn4VL/m67kKLnaRHGVEogQaA5f4TfmbqiLoE4HXiFR8MTLzJVQlEdBtP62J5z58VImS+ALmBohgcTl5eYNoYSzTJmA64jBVIqyeGgSjsiMzSId0tZkCBF6WwtLB1jjf+nC9Nrgih58EA/mpc40dP86Ewvk3qD3iKxDmzn3E21zqRt2hGdgVt7fVXMpaTM0ivD+AepCN869GC8tpdCCZ049K1v1Da9knWYjd5j0VvZMW2I41bK6mzyELqIa6eUsginQoLWBKzCW+i83f7e30crcJGrbLUpB2liPkgB8loYnT+D97JEgyGaeGbUQwbmeqo6C/bik4KSbg5IoesSfzsICBZ2IIX3INeckUHUJlHapb6CWYuBbJ9Rg7Evj5mTFzU95g4vUM1jz/NH41CY63bq496Vy5SLa/PPSsACPX6iOJM8tHC5ibRkXpxhYxB4k491S2mE9P23PRIJj61xDFwkWftPGQNSwc4GWp55VlrPeE0XPOYhPs3uSQH1BjIMEvev9HrkiuYePcVSeX/M4CZKVe312IzHKFW4hi6QkOhkecaUB2v/JDGHwrMlR0E0dwA1iG2zGU0IkKHtp6bYaQuOXVUOtUDHOt/1rPSSAjC7CG7m7pETPUNRERzXjd0h5PP+8wnPAu17IVAKpccfaPHVQCYgRX7qw==";
    };
    site = {
      inherit host;
      port = 8443;
    };
  };

  # Private flakes on Forgejo that CI fetches (the `scorsi-*` inputs of flake.nix).
  sekkeizu.forgejoCi = {
    readKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBu5LRhn8S9nSgkns5be0UtUo27ZcfIgg9dhYU+bHrYE forgejo-ci";
    readRepos = [
      "kiso"
      "kanna"
      "sekkeizu-private"
    ];
  };

  sekkeizu.forgejoRunners = {
    ishizue.labels = [ "linux:host" ];
    jiban.labels = [ "macos:host" ];
  };
}
