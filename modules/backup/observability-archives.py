"""Export masu's and nisshi's days for backup, and check and thin the pulled copies.

ishizue (`export`, then `marker` once the whole job succeeded): hard-links the sealed days of the
last `keep` days (data before manifest), copies the committed prefix of each open day to
`<day>.ndjson.zst.partial`, and drops older links. jiban (`pulled`): checks the export's freshness
and inventory, then keeps sealed data for `days` days and every manifest needed by nisshi's chain.
"""

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import sys

NODE = r"[a-z0-9][a-z0-9-]{0,62}"
DAY = r"\d{4}-\d{2}-\d{2}"
# The data directory below the root, and state.json's map of open day files to committed lengths.
FORMATS = {"masu-archive 1\n": ("archive", "files"), "nisshi-store 1\n": (".", "days")}
STAMP = "%Y-%m-%dT%H:%M:%SZ"


def regular(path):
    if path.is_symlink():
        raise ValueError(f"Refusing symlink: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")
    return path.is_file()


def layout(root):
    if root.is_symlink():
        raise ValueError(f"Refusing symlink: {root}")
    if not regular(root / "FORMAT"):
        raise ValueError(f"Missing FORMAT: {root}")
    prefix, lengths = FORMATS[(root / "FORMAT").read_text()]
    base = root / prefix
    if base.is_symlink():
        raise ValueError(f"Refusing symlink: {base}")
    return base, lengths


def nodes(base):
    if not base.exists():
        return []
    result = []
    for node in sorted(base.iterdir()):
        if node.name == ".rsync-partial":
            continue
        if node.is_symlink():
            raise ValueError(f"Refusing symlink: {node}")
        if not node.is_dir():
            continue
        if not re.fullmatch(NODE, node.name):
            raise ValueError(f"Invalid node directory: {node}")
        result.append(node)
    return result


def sealed(root):
    base, _ = layout(root)
    result = []
    for node in nodes(base):
        for manifest in sorted(node.glob("*.manifest.json")):
            regular(manifest)
            day = manifest.name.removesuffix(".manifest.json")
            if datetime.strptime(day, "%Y-%m-%d").strftime("%Y-%m-%d") != day:
                raise ValueError(f"Invalid sealed day: {manifest}")
            data = node / f"{day}.ndjson.zst"
            regular(data)
            result.append((day, manifest, data))
    return result


def partial(data):
    return data.with_name(f"{data.name}.partial")


def cutoff(days, today):
    if days <= 0:
        raise ValueError("Backup retention must be positive")
    return (today - timedelta(days=days)).isoformat()


def unsymlinked(destination, relative):
    """Refuse a destination whose existing parents redirect writes elsewhere."""
    parts = Path(relative).parts
    for depth in range(len(parts)):
        directory = destination.joinpath(*parts[:depth])
        if directory.is_symlink():
            raise ValueError(f"Refusing symlink: {directory}")


def write(path, chunks):
    """Replace `path` atomically with a private file; the `.tmp` name is never pulled."""
    temporary = path.with_name(f"{path.name}.tmp")
    temporary.unlink(missing_ok=True)
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        for chunk in chunks:
            os.write(fd, chunk)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.rename(temporary, path)


def prune(root, days, today):
    oldest = cutoff(days, today)
    entries = sealed(root)
    latest = {}
    for day, manifest, data in entries:
        if day >= oldest and not data.exists():
            raise ValueError(f"Missing retained data for {manifest}")
        if data.exists():
            latest[data.parent] = data
    for day, _, data in entries:
        # Restoring renames each .partial into place: a sealed day must not have one too.
        partial(data).unlink(missing_ok=True)
        # An inactive node keeps its last complete day, even beyond the retention window.
        if day < oldest and data.exists() and data != latest[data.parent]:
            data.unlink()


def expire(root, keep, today):
    """Drop every file of the days older than `keep` (jiban's copies and restic keep them)."""
    oldest = cutoff(keep, today)
    base, _ = layout(root)
    pattern = rf"({DAY})\.(manifest\.json|ndjson\.zst(\.partial)?)(\.tmp)?"
    for node in nodes(base):
        # Data before manifest, as when linking: an interrupted run never leaves data unsealed.
        for path in sorted(node.iterdir(), key=lambda p: "manifest" in p.name):
            match = re.fullmatch(pattern, path.name)
            if match and match[1] < oldest:
                path.unlink()


def snapshot(source, destination):
    """Copy each open day's committed prefix: a valid day file for a restore."""
    base, key = layout(source)
    try:
        # state.json is replaced by rename: one read is one consistent version.
        state = json.loads((source / "state.json").read_bytes())
    except FileNotFoundError:
        return
    for name, length in sorted((state.get(key) or {}).items()):
        if not re.fullmatch(f"{NODE}/{DAY}", name) or type(length) is not int or length < 0:
            raise ValueError(f"Invalid open day in state.json: {name!r}: {length!r}")
        if (base / name).parent.is_symlink():
            raise ValueError(f"Refusing symlink: {(base / name).parent}")
        data = base / f"{name}.ndjson.zst"
        fd = os.open(data, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            # Sealing writes the manifest before renaming the recompressed file over the day file:
            # without a manifest now, fd is the appended file, whose committed prefix never
            # changes. A sealed day is linked instead.
            if (base / f"{name}.manifest.json").exists():
                continue
            if os.fstat(fd).st_size < length:
                raise ValueError(f"{data}: shorter than its committed length {length}")
            target = partial(destination / data.relative_to(source))
            unsymlinked(destination, target.relative_to(destination))
            target.parent.mkdir(parents=True, exist_ok=True)

            def chunks():
                offset = 0
                while offset < length:
                    chunk = os.pread(fd, min(1 << 20, length - offset), offset)
                    if not chunk:
                        raise ValueError(f"{data}: truncated while copying")
                    offset += len(chunk)
                    yield chunk

            write(target, chunks())
        finally:
            os.close(fd)


def link(source, destination, days, keep, today):
    oldest = cutoff(days, today)
    exported = cutoff(keep, today)
    entries = [entry for entry in sealed(source) if entry[0] >= exported]

    # Check all destination parents before publishing anything, including a first FORMAT.
    for path in [source / "FORMAT"] + [path for _, manifest, data in entries for path in (manifest, data)]:
        unsymlinked(destination, path.relative_to(source))
    destination.mkdir(parents=True, exist_ok=True)

    def copy(path):
        target = destination / path.relative_to(source)
        if not regular(target):
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(path, target)

    copy(source / "FORMAT")
    if (destination / "FORMAT").read_bytes() != (source / "FORMAT").read_bytes():
        raise ValueError(f"Backup FORMAT differs from source: {destination}")
    for day, manifest, data in entries:
        target_data = destination / data.relative_to(source)
        if data.exists():
            try:
                copy(data)
            except FileNotFoundError:
                # Store retention may unlink expired data between discovery and hard-linking.
                if day >= oldest:
                    raise
        if day >= oldest and not regular(target_data):
            raise ValueError(f"Missing retained data for {manifest}")
        copy(manifest)
    expire(destination, keep, today)
    prune(destination, days, today)


def export(source, destination, days, keep, today):
    # Partials first: a day sealed meanwhile is then linked, and its partial dropped by prune.
    snapshot(source, destination)
    link(source, destination, days, keep, today)


def marker(root, now):
    """LAST_RUN: when the export last succeeded, then every sealed file it holds."""
    lines = [now.strftime(STAMP)]
    for _, manifest, data in sealed(root):
        lines += [str(path.relative_to(root)) for path in (data, manifest) if path.exists()]
    unsymlinked(root, "LAST_RUN")
    write(root / "LAST_RUN", ["".join(f"{line}\n" for line in lines).encode()])


def check(root, hours, now):
    if not regular(root / "LAST_RUN"):
        raise ValueError(f"No export marker: {root / 'LAST_RUN'}")
    stamp, *inventory = (root / "LAST_RUN").read_text().splitlines()
    age = now - datetime.strptime(stamp, STAMP).replace(tzinfo=timezone.utc)
    if age > timedelta(hours=hours):
        raise ValueError(f"Last export {stamp} is older than {hours} h: {root}")
    missing = []
    for line in inventory:
        if Path(line).is_absolute() or ".." in Path(line).parts:
            raise ValueError(f"Invalid inventory entry: {line!r}")
        if not regular(root / line):
            missing.append(line)
    if missing:
        raise ValueError(f"Exported but missing after the pull: {' '.join(missing)}")


def main(command, root, *rest):
    now = datetime.now(timezone.utc)
    if command == "export":
        destination, days, keep = rest
        export(Path(root), Path(destination), int(days), int(keep), now.date())
    elif command == "marker":
        marker(Path(root), now)
    elif command == "pulled":
        days, hours = rest
        # Retention only after a fresh and complete pull.
        check(Path(root), int(hours), now)
        prune(Path(root), int(days), now.date())
    else:
        raise ValueError("Expected export, marker or pulled")


if __name__ == "__main__":
    try:
        main(*sys.argv[1:])
    except ValueError as error:
        # One line in the job's log rather than a traceback.
        sys.exit(f"{sys.argv[1]} {sys.argv[2]}: {error}")
