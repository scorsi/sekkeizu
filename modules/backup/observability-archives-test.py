from datetime import date, datetime, timedelta, timezone
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
        rejected(lambda: archives.link(source, redirected, days, days, today))
        assert list(outside.iterdir()) == [], "backup escaped through a destination parent"
        assert not (redirected / "FORMAT").exists(), "destination validation happened after writes"
        redirected_root = root / "redirected-root"
        redirected_root.symlink_to(outside, target_is_directory=True)
        rejected(lambda: archives.link(source, redirected_root, days, days, today))
        assert list(outside.iterdir()) == []
        redirected_source = root / "redirected-source"
        redirected_source.symlink_to(source, target_is_directory=True)
        rejected(lambda: archives.link(redirected_source, backup, days, days, today))
        assert not backup.exists()

        archives.link(source, backup, days, days, today)
        saved = backup / prefix / "node-a"
        assert not (saved / f"{old}.ndjson.zst").exists()
        assert (node / f"{old}.ndjson.zst").is_file(), "pruning removed source data"
        assert (saved / f"{boundary}.ndjson.zst").stat().st_ino == (node / f"{boundary}.ndjson.zst").stat().st_ino
        # Days older than the export window leave ishizue entirely: jiban keeps them.
        assert not (backup / prefix / "inactive").exists()
        assert not (saved / f"{today}.ndjson.zst").exists(), "open day was backed up"
        assert not (saved / manifests[0].name).exists()
        for manifest in manifests[1:]:
            assert (saved / manifest.name).read_bytes() == manifest.read_bytes()

        # A second run cannot recreate expired data or change the manifest chain.
        archives.link(source, backup, days, days, today)
        assert not (saved / f"{old}.ndjson.zst").exists()
        # Heal a manifest left without its data by the previous backup implementation.
        (saved / f"{boundary}.ndjson.zst").unlink()
        archives.link(source, backup, days, days, today)
        assert (saved / f"{boundary}.ndjson.zst").is_file()

        shutil.copytree(backup, pulled)
        copied = pulled / prefix / "node-a"
        # jiban received the old day while it was still exported.
        shutil.copy(manifests[0], copied / manifests[0].name)
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
        rejected(lambda: archives.link(source, backup, days, days, today))
        assert not (saved / f"{broken_day}.manifest.json").exists()
        assert (saved / f"{old}.ndjson.zst").read_bytes() == b"safe before failed link"
        (node / f"{broken_day}.manifest.json").unlink()
        (node / f"{broken_day}.manifest.json").symlink_to(manifests[-1])
        rejected(lambda: archives.link(source, backup, days, days, today))


# Twice-daily export: open days' committed prefixes, a 90-day window on ishizue, the marker.
keep = 90
now = datetime(2026, 10, 21, 4, 45, tzinfo=timezone.utc)
with tempfile.TemporaryDirectory() as temporary:
    for store, format_line, prefix, key in [
        ("masu", "masu-archive 1\n", "archive", "files"),
        ("nisshi", "nisshi-store 1\n", ".", "days"),
    ]:
        root = Path(temporary) / store
        source, backup, pulled = root / "source", root / "backup", root / "pulled"
        node = source / prefix / "node-a"
        node.mkdir(parents=True)
        (source / "FORMAT").write_text(format_line)
        expired, kept, yesterday = today - timedelta(days=keep + 1), today - timedelta(days=keep), today - timedelta(days=1)
        for day in [expired, kept]:
            (node / f"{day}.ndjson.zst").write_bytes(f"sealed {day}".encode())
            (node / f"{day}.manifest.json").write_text("{}")
        # yesterday: open in state.json but sealed since; today: open, with an uncommitted tail.
        (node / f"{yesterday}.ndjson.zst").write_bytes(b"recompressed")
        (node / f"{yesterday}.manifest.json").write_text("{}")
        (node / f"{today}.ndjson.zst").write_bytes(b"committed|uncommitted")
        (source / "state.json").write_text(json.dumps({key: {f"node-a/{yesterday}": 5, f"node-a/{today}": 9}}))
        saved = backup / prefix / "node-a"
        saved.mkdir(parents=True)
        # Links of an expired day, and yesterday's partial from the previous run.
        (saved / f"{expired}.ndjson.zst").write_bytes(b"old link")
        (saved / f"{expired}.manifest.json").write_text("{}")
        (saved / f"{yesterday}.ndjson.zst.partial").write_bytes(b"older")

        archives.export(source, backup, days, keep, today)
        open_day = saved / f"{today}.ndjson.zst.partial"
        assert open_day.read_bytes() == b"committed", "partial is not the committed prefix"
        assert open_day.stat().st_ino != (node / f"{today}.ndjson.zst").stat().st_ino, "partial is a link"
        assert open_day.stat().st_mode & 0o077 == 0
        assert not (saved / f"{today}.ndjson.zst").exists()
        assert not (saved / f"{yesterday}.ndjson.zst.partial").exists(), "sealed day kept its partial"
        assert (saved / f"{yesterday}.ndjson.zst").stat().st_ino == (node / f"{yesterday}.ndjson.zst").stat().st_ino
        assert not (saved / f"{expired}.ndjson.zst").exists() and not (saved / f"{expired}.manifest.json").exists()
        assert (node / f"{expired}.ndjson.zst").exists(), "expiry touched the store"
        assert (saved / f"{kept}.manifest.json").exists()
        # A partial is replaced, never appended to.
        (node / f"{today}.ndjson.zst").write_bytes(b"committed+more|tail")
        (source / "state.json").write_text(json.dumps({key: {f"node-a/{today}": 14}}))
        archives.export(source, backup, days, keep, today)
        assert open_day.read_bytes() == b"committed+more"

        # A store's state.json cannot point outside its data directory or past its file.
        for bad in [{"../escape/2026-10-21": 1}, {f"node-a/{today}": 999}, {f"node-a/{today}": -1}]:
            (source / "state.json").write_text(json.dumps({key: bad}))
            rejected(lambda: archives.export(source, backup, days, keep, today))
        (source / "state.json").write_text(json.dumps({key: {f"node-a/{today}": 14}}))

        archives.marker(backup, now)
        inventory = (backup / "LAST_RUN").read_text().splitlines()
        assert inventory[0] == "2026-10-21T04:45:00Z"
        prefixed = lambda name: str(Path(prefix) / "node-a" / name)
        assert set(inventory[1:]) == {prefixed(f"{d}.{s}") for d in [kept, yesterday] for s in ["ndjson.zst", "manifest.json"]}
        assert not (backup / "LAST_RUN.tmp").exists()

        shutil.copytree(backup, pulled)
        copied = pulled / prefix / "node-a"
        archives.check(pulled, 14, now + timedelta(hours=13))
        rejected(lambda: archives.check(pulled, 14, now + timedelta(hours=15)))
        (copied / f"{kept}.ndjson.zst").unlink()
        rejected(lambda: archives.check(pulled, 14, now))
        (copied / f"{kept}.ndjson.zst").write_bytes(b"restored")
        (pulled / "LAST_RUN").write_text("2026-10-21T04:45:00Z\n../outside\n")
        rejected(lambda: archives.check(pulled, 14, now))
        # jiban drops a received partial once its day arrives sealed.
        (copied / f"{yesterday}.ndjson.zst.partial").write_bytes(b"stale")
        archives.prune(pulled, days, today)
        assert not (copied / f"{yesterday}.ndjson.zst.partial").exists()
        assert (copied / f"{today}.ndjson.zst.partial").exists()

print("observability backups: retention, complete pairs, hardlinks, partials, expiry and marker passed")
