set -euo pipefail
umask 027
source_key=$1
destination=$2
test -f "$source_key"
test ! -L "$source_key"
install -d -m 0750 "$destination"
temporary=$(mktemp "$destination/.account.XXXXXX")
trap 'rm -f "$temporary"' EXIT
install -m 0640 "$source_key" "$temporary"
openssl pkey -in "$temporary" -check -noout >/dev/null
digest=$(sha256sum "$temporary")
archive="$destination/account-${digest%% *}.key"
# Keep every account identity: an older key may still be pinned in CAA or needed for recovery.
if [ -e "$archive" ]; then
  cmp "$temporary" "$archive"
else
  ln "$temporary" "$archive"
fi
