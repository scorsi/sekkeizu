import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


script = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    source, destination = root / "source", root / "destination"
    source.mkdir()
    destination.mkdir()

    def command(*options):
        return ["bash", script, *options, f"{source}/", f"{destination}/"]

    def pull():
        subprocess.run(command(), check=True)

    (source / "archive.tar").write_bytes(b"original archive")
    pull()
    archive = destination / "archive.tar"
    original_mtime = archive.stat().st_mtime_ns
    (source / "archive.tar").write_bytes(b"compromised replacement")
    os.utime(source / "archive.tar", (1, 1))
    (source / "new.tar").write_bytes(b"new archive")
    changed = subprocess.run(command(), capture_output=True, text=True)
    assert changed.returncode == 102, changed
    assert ">f" in changed.stderr and "archive.tar" in changed.stderr and "new.tar" not in changed.stderr
    assert archive.read_bytes() == b"original archive"
    assert archive.stat().st_mtime_ns == original_mtime
    assert (destination / "new.tar").read_bytes() == b"new archive"
    (source / "archive.tar").unlink()
    pull()
    assert archive.read_bytes() == b"original archive"

    (source / "archive.tar").mkdir()
    (source / "archive.tar" / "child").write_bytes(b"replacement directory")
    subprocess.run(command(), capture_output=True)
    assert archive.read_bytes() == b"original archive"
    shutil.rmtree(source / "archive.tar")

    content = os.urandom(4 * 1024 * 1024)
    (source / "interrupted.tar").write_bytes(content)
    # Its own process group: the interruption reaches rsync, not only the wrapping shell.
    process = subprocess.Popen(command("--bwlimit=1024"), stderr=subprocess.PIPE, start_new_session=True)
    try:
        deadline = time.monotonic() + 10
        while not list(destination.glob(".interrupted.tar.*")):
            assert process.poll() is None, "transfer finished before interruption"
            assert time.monotonic() < deadline, "transfer did not start"
            time.sleep(0.01)
        time.sleep(0.2)
        os.killpg(process.pid, signal.SIGINT)
        process.communicate(timeout=10)
        assert process.returncode != 0
        assert not (destination / "interrupted.tar").exists()
        assert (destination / ".rsync-partial" / "interrupted.tar").is_file()
        pull()
        assert (destination / "interrupted.tar").read_bytes() == content
        assert not (destination / ".rsync-partial" / "interrupted.tar").exists()
        assert archive.read_bytes() == b"original archive"
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()

    # Open days' prefixes and the marker are replaced; temporary files never travel.
    node = source / "archive" / "node-a"
    node.mkdir(parents=True)
    (node / "2026-10-21.ndjson.zst.partial").write_bytes(b"prefix")
    (node / "2026-10-21.ndjson.zst.partial.tmp").write_bytes(b"half written")
    (source / "LAST_RUN").write_text("2026-10-21T04:45:00Z\n")
    pull()
    (node / "2026-10-21.ndjson.zst.partial").write_bytes(b"longer prefix")
    (source / "LAST_RUN").write_text("2026-10-21T16:45:00Z\n")
    pull()
    received = destination / "archive" / "node-a"
    assert (received / "2026-10-21.ndjson.zst.partial").read_bytes() == b"longer prefix"
    assert (destination / "LAST_RUN").read_text() == "2026-10-21T16:45:00Z\n"
    assert not (received / "2026-10-21.ndjson.zst.partial.tmp").exists()

print("backup pull: immutable archives, reported changes, replaced partials and interrupted transfer recovery passed")
