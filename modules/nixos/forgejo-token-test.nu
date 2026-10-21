source ./forgejo-token.nu
use std/assert

const db = 'tokens.db'
const prefix = 'sekkeizu-provision-unit-'

def fixture [] {
  if ($db | path exists) { rm $db }
  ^sqlite3 $db "
    CREATE TABLE \"user\" (id INTEGER PRIMARY KEY, lower_name TEXT);
    CREATE TABLE access_token (id INTEGER PRIMARY KEY, uid INTEGER, name TEXT);
    CREATE TABLE access_token_resource_repo (id INTEGER PRIMARY KEY, token_id INTEGER);
    INSERT INTO \"user\" VALUES (1, 'owner'), (2, 'other');
    INSERT INTO access_token VALUES
      (1, 1, 'sekkeizu-provision-unit-stale'), (2, 1, 'manual'), (3, 1, 'sekkeizu-provision-other-x'),
      (4, 2, 'sekkeizu-provision-unit-theirs'), (5, 1, 'x-sekkeizu-provision-unit-');
    INSERT INTO access_token_resource_repo VALUES (1, 1), (2, 2);
  "
}

def names [] { ^sqlite3 $db 'SELECT name FROM access_token ORDER BY id' | lines }
def revoke [] { revoke-tokens $db Owner $prefix }
def mint [] {
  ^sqlite3 $db $"INSERT INTO access_token \(uid, name) VALUES \(1, '($prefix)run')"
  'secret'
}
def kept [] { ['manual' 'sekkeizu-provision-other-x' 'sekkeizu-provision-unit-theirs' 'x-sekkeizu-provision-unit-'] }

def run-tests [] {
  fixture
  with-token { mint } { revoke } {|token|
    assert equal $token secret
    # The stale token of a crashed run is gone before the action runs.
    assert equal (names) (kept | append $'($prefix)run')
  }
  assert equal (names) (kept)
  assert equal (^sqlite3 $db 'SELECT token_id FROM access_token_resource_repo' | lines) ['2']

  fixture
  let failed = try { with-token { mint } { revoke } {|token| error make {msg: 'action failed'} }; false } catch {|err|
    assert equal $err.msg 'action failed'
    true
  }
  assert $failed
  assert equal (names) (kept)

  assert error { revoke-tokens $db owner '' }
  assert error { with-token { '' } { null } {|token| null } }
}

run-tests
rm $db
print 'forgejo-token tests passed'
