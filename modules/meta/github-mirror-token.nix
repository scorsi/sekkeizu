# The token Forgejo's push mirrors use to reach GitHub. The mirrors and the token are koseki's
# (secrets/tofu.yaml there); the reminder stays here, since jiban is what notifies.
_: {
  sekkeizu.expiringSecrets.github-mirror-token = {
    expires = "2026-12-07";
    renew = "new fine-grained token (mirror repos; Contents RW), sops edit secrets/tofu.yaml in koseki, tofu apply (recreates the mirrors), date in modules/meta/github-mirror-token.nix";
  };
}
