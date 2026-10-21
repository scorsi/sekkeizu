# Short-lived API tokens for the provisioning units: minted by the CLI (stdout, never argv) and
# revoked once the unit is done, whatever happened.

# Straight in the database: the API deletes tokens only under password basic auth, which Forgejo
# refuses once a security key is enrolled. Its token cache re-reads the row, so revocation is immediate.
def revoke-tokens [db: string, user: string, prefix: string] {
  if ($prefix | is-empty) { error make {msg: "Refusing to revoke Forgejo tokens without a prefix"} }
  let quote = {|s| "'" + ($s | str replace --all "'" "''") + "'" }
  let tokens = [
    'SELECT id FROM access_token WHERE uid = (SELECT id FROM "user" WHERE lower_name = lower(' (do $quote $user) '))'
    ' AND substr(name, 1, ' ($prefix | str length | into string) ') = ' (do $quote $prefix)
  ] | str join
  let sql = [
    'BEGIN; DELETE FROM access_token_resource_repo WHERE token_id IN (' $tokens ');'
    ' DELETE FROM access_token WHERE id IN (' $tokens '); COMMIT;'
  ] | str join
  ^sqlite3 -bail -cmd '.timeout 60000' $db $sql
}

def with-token [mint: closure, revoke: closure, action: closure] {
  # Also clears tokens left behind by a run that crashed before its cleanup.
  do $revoke
  let token = do $mint
  if ($token | is-empty) { error make {msg: "Forgejo returned an empty access token"} }
  try { do $action $token } catch {|err| do $revoke; $err.raw }
  do $revoke
}
