# Existing archives are immutable; interrupted transfers stay outside their final names.
exec rsync -rt --ignore-existing --partial-dir=.rsync-partial --chmod=D700,F600 "$@"
