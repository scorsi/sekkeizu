from datetime import date, timedelta
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


spec = importlib.util.spec_from_file_location("archives", sys.argv[1])
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)
days = json.loads(Path(sys.argv[2]).read_text())
today = date(2026, 10, 21)
cutoff = today - timedelta(days=days)
old, boundary, recent = cutoff - timedelta(days=1), cutoff, today - timedelta(days=1)


def rejected(action):
    try:
        action()
    except ValueError:
        return
    raise AssertionError("Invalid backup was accepted")


with tempfile.TemporaryDirectory() as temporary:
    for store, format_line, prefix in [
        ("masu", "masu-archive 1\n", "archive"),
        ("nisshi", "nisshi-store 1\n", "."),
    ]:
        root = Path(temporary) / store
        source, backup, pulled = root / "source", root / "backup", root / "pulled"
        source.mkdir(parents=True)
        (source / "FORMAT").write_text(format_line)
        node = source / prefix / "node-a"
        node.mkdir(parents=True)
        previous = None
        manifests = []
        for day in [old, boundary, recent]:
            manifest = node / f"{day}.manifest.json"
            manifest.write_text(json.dumps({
                "day": str(day),
                "prev_day": previous.name[:10] if previous else None,
                "prev_manifest_sha256": hashlib.sha256(previous.read_bytes()).hexdigest() if previous else None,
            }))
            (node / f"{day}.ndjson.zst").write_bytes(f"sealed {day}".encode())
            previous = manifest
            manifests.append(manifest)
        inactive = source / prefix / "inactive"
        inactive.mkdir()
        (inactive / f"{old}.manifest.json").write_text("{}")
        (inactive / f"{old}.ndjson.zst").write_bytes(b"last complete day")
        (node / f"{today}.ndjson.zst").write_bytes(b"open day")

        outside = root / "outside"
        outside.mkdir()
        redirected = root / "redirected"
        (redirected / prefix).mkdir(parents=True, exist_ok=True)
        (redirected / prefix / "node-a").symlink_to(outside, target_is_directory=True)
        rejected(lambda: archives.link(source, redirected, days, today))
        assert list(outside.iterdir()) == [], "backup escaped through a destination parent"
        assert not (redirected / "FORMAT").exists(), "destination validation happened after writes"
        redirected_root = root / "redirected-root"
        redirected_root.symlink_to(outside, target_is_directory=True)
        rejected(lambda: archives.link(source, redirected_root, days, today))
        assert list(outside.iterdir()) == []
        redirected_source = root / "redirected-source"
        redirected_source.symlink_to(source, target_is_directory=True)
        rejected(lambda: archives.link(redirected_source, backup, days, today))
        assert not backup.exists()

        archives.link(source, backup, days, today)
        saved = backup / prefix / "node-a"
        assert not (saved / f"{old}.ndjson.zst").exists()
        assert (node / f"{old}.ndjson.zst").is_file(), "pruning removed source data"
        assert (saved / f"{boundary}.ndjson.zst").stat().st_ino == (node / f"{boundary}.ndjson.zst").stat().st_ino
        assert (backup / prefix / "inactive" / f"{old}.ndjson.zst").is_file()
        assert not (saved / f"{today}.ndjson.zst").exists(), "open day was backed up"
        for manifest in manifests:
            assert (saved / manifest.name).read_bytes() == manifest.read_bytes()

        # A second run cannot recreate expired data or change the manifest chain.
        archives.link(source, backup, days, today)
        assert not (saved / f"{old}.ndjson.zst").exists()
        # Heal a manifest left without its data by the previous backup implementation.
        (saved / f"{boundary}.ndjson.zst").unlink()
        archives.link(source, backup, days, today)
        assert (saved / f"{boundary}.ndjson.zst").is_file()

        shutil.copytree(backup, pulled)
        copied = pulled / prefix / "node-a"
        # mtime is irrelevant: retention follows sealed UTC days, including the boundary.
        os.utime(copied / f"{recent}.ndjson.zst", (1, 1))
        (copied / f"{old}.ndjson.zst").write_bytes(b"old pulled data")
        (pulled / ".rsync-partial").mkdir()
        (pulled / ".rsync-partial" / "unfinished").write_bytes(b"partial")
        archives.prune(pulled, days, today)
        assert not (copied / f"{old}.ndjson.zst").exists()
        assert (copied / f"{boundary}.ndjson.zst").is_file()
        assert (copied / f"{recent}.ndjson.zst").is_file()
        assert (pulled / "FORMAT").read_text() == format_line
        for manifest in manifests:
            assert (copied / manifest.name).read_bytes() == manifest.read_bytes()

        # A successful transport with a missing retained pair must not authorize any deletion.
        (copied / f"{old}.ndjson.zst").write_bytes(b"last safe old copy")
        (copied / f"{recent}.ndjson.zst").unlink()
        rejected(lambda: archives.prune(pulled, days, today))
        assert (copied / f"{old}.ndjson.zst").read_bytes() == b"last safe old copy"

        broken_day = today - timedelta(days=2)
        (saved / f"{old}.ndjson.zst").write_bytes(b"safe before failed link")
        (node / f"{broken_day}.manifest.json").write_text("{}")
        rejected(lambda: archives.link(source, backup, days, today))
        assert not (saved / f"{broken_day}.manifest.json").exists()
        assert (saved / f"{old}.ndjson.zst").read_bytes() == b"safe before failed link"
        (node / f"{broken_day}.manifest.json").unlink()
        (node / f"{broken_day}.manifest.json").symlink_to(manifests[-1])
        rejected(lambda: archives.link(source, backup, days, today))

print("observability backups: retention, complete pairs, hardlinks and manifest chain passed")
