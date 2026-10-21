"""Keep sealed data for 400 days and every manifest needed by nisshi's hash chain."""

from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import re
import sys


def regular(path):
    if path.is_symlink():
        raise ValueError(f"Refusing symlink: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")
    return path.is_file()


def sealed(root):
    if root.is_symlink():
        raise ValueError(f"Refusing symlink: {root}")
    if not regular(root / "FORMAT"):
        raise ValueError(f"Missing FORMAT: {root}")
    formats = {"masu-archive 1\n": "archive", "nisshi-store 1\n": "."}
    base = root / formats[(root / "FORMAT").read_text()]
    if base.is_symlink():
        raise ValueError(f"Refusing symlink: {base}")
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
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", node.name):
            raise ValueError(f"Invalid node directory: {node}")
        for manifest in sorted(node.glob("*.manifest.json")):
            regular(manifest)
            day = manifest.name.removesuffix(".manifest.json")
            if datetime.strptime(day, "%Y-%m-%d").strftime("%Y-%m-%d") != day:
                raise ValueError(f"Invalid sealed day: {manifest}")
            data = node / f"{day}.ndjson.zst"
            regular(data)
            result.append((day, manifest, data))
    return result


def cutoff(days, today):
    if days <= 0:
        raise ValueError("Backup retention must be positive")
    return (today - timedelta(days=days)).isoformat()


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
        # An inactive node keeps its last complete day, even beyond the retention window.
        if day < oldest and data.exists() and data != latest[data.parent]:
            data.unlink()


def link(source, destination, days, today):
    oldest = cutoff(days, today)
    entries = sealed(source)

    # Check all destination parents before publishing anything, including a first FORMAT.
    for path in [source / "FORMAT"] + [path for _, manifest, data in entries for path in (manifest, data)]:
        parts = path.relative_to(source).parts
        for depth in range(len(parts)):
            directory = destination.joinpath(*parts[:depth])
            if directory.is_symlink():
                raise ValueError(f"Refusing symlink: {directory}")
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
    prune(destination, days, today)


if __name__ == "__main__":
    today = datetime.now(timezone.utc).date()
    if sys.argv[1] == "link":
        link(Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4]), today)
    elif sys.argv[1] == "prune":
        prune(Path(sys.argv[2]), int(sys.argv[3]), today)
    else:
        raise ValueError("Expected link or prune")
