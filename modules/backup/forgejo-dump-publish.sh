set -euo pipefail
umask 077
staging=$1
destination=$2
reader=$3
shift 3
temporary=$(mktemp -d "$staging/dump.XXXXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
(
  cd "$temporary"
  "$@"
)
shopt -s nullglob dotglob
archives=("$temporary"/*)
if [ "${#archives[@]}" -ne 1 ] || [ ! -f "${archives[0]}" ] || [ -L "${archives[0]}" ] || [ ! -s "${archives[0]}" ]; then
  echo "Expected one complete Forgejo dump archive" >&2
  exit 1
fi
archive=${archives[0]}
# Forgejo chmods the finished archive 0600, so grant access only after it exits successfully.
setfacl -m "u:$reader:r" "$archive"
setfacl -m "u:$reader:rX" "$destination"
# Linking publishes atomically on the same filesystem and refuses to overwrite an older dump.
ln -T -- "$archive" "$destination/$(basename "$archive")"
