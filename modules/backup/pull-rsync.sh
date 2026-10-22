set -euo pipefail
# Received files are final: a source that changed one is reported (exit 102), never applied.
# Interrupted transfers stay outside their final names. Two exceptions, replaced at every pull:
# an open day's committed prefix (*.partial) and the export's freshness marker (LAST_RUN),
# whatever their size and time.
common=(-rt --partial-dir=.rsync-partial --chmod='D700,F600')
final=(--exclude='*.partial' --exclude='*.tmp' --exclude=/LAST_RUN)
replaced=(--include='*/' --include='*.partial' --include=/LAST_RUN --exclude='*')

itemized=$(rsync "${common[@]}" "${final[@]}" --dry-run --itemize-changes "$@")
changed=$(grep '^>f' <<<"$itemized" | grep -v '^>f+++++++++' || true)
rsync "${common[@]}" "${final[@]}" --ignore-existing "$@"
rsync "${common[@]}" "${replaced[@]}" --ignore-times "$@"
if [ -n "$changed" ]; then
  printf 'source changed already-received files, kept as received:\n%s\n' "$changed" >&2
  exit 102
fi
