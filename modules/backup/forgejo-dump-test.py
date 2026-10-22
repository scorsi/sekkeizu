import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import time


publisher, puller = map(lambda path: str(Path(path).resolve()), sys.argv[1:])
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    staging, source, destination, binaries = [root / name for name in ("staging", "source", "pulled", "bin")]
    for directory in (staging, source, destination, binaries):
        directory.mkdir()
    # ACL support is Linux-only; the portable test checks ACL ordering with a fake command.
    acl = binaries / "setfacl"
    acl.write_text("#!/bin/sh\nset -eu\ntest -z \"$(ls -A \"$SOURCE\")\"\nprintf '%s\\n' \"$*\" >> \"$ACL_LOG\"\n")
    acl.chmod(0o755)
    env = os.environ | {
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "SOURCE": str(source),
        "ACL_LOG": str(root / "acl.log"),
    }
    fake = root / "dump.py"
    fake.write_text("""
import pathlib, sys, time
archive = pathlib.Path('forgejo-dump-123.tar')
archive.write_bytes(b'partial')
pathlib.Path(sys.argv[2]).touch()
while not pathlib.Path(sys.argv[3]).exists():
    time.sleep(0.01)
if sys.argv[1] == 'fail':
    sys.exit(1)
archive.write_bytes(b'complete archive')
archive.chmod(0o600)
""")
    ready, release = root / "ready", root / "release"

    def command(mode):
        return ["bash", publisher, str(staging), str(source), "backup", sys.executable, str(fake), mode, str(ready), str(release)]

    def pull():
        subprocess.run(["bash", puller, f"{source}/", f"{destination}/"], check=True)

    stale = []
    for mode in ("kill", "fail", "success"):
        ready.unlink(missing_ok=True)
        release.unlink(missing_ok=True)
        process = subprocess.Popen(command(mode), env=env, start_new_session=True)
        try:
            deadline = time.monotonic() + 10
            while not ready.exists():
                assert process.poll() is None, "dump exited before writing"
                assert time.monotonic() < deadline, "dump did not start"
                time.sleep(0.01)
            assert list(staging.glob("*/forgejo-dump-123.tar")), "fake dump must write a partial file"
            pull()
            assert not list(source.iterdir()), "running dump became visible"
            assert not list(destination.iterdir()), "running dump was pulled"
            if mode == "kill":
                os.killpg(process.pid, signal.SIGKILL)
                assert process.wait(timeout=10) == -signal.SIGKILL
                stale = list(staging.iterdir())
                assert len(stale) == 1, "killed dump should remain only in private staging"
                assert (stale[0] / "forgejo-dump-123.tar").read_bytes() == b"partial"
            else:
                release.touch()
                assert process.wait(timeout=10) == (1 if mode == "fail" else 0)
                assert list(staging.iterdir()) == stale, "finished run staging was not cleaned"
            pull()
            if mode != "success":
                assert not list(destination.iterdir()), "failed dump was pulled"
                assert not (root / "acl.log").exists()
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    archive = destination / "forgejo-dump-123.tar"
    assert archive.read_bytes() == b"complete archive"
    assert len((root / "acl.log").read_text().splitlines()) == 2
    original_mtime = archive.stat().st_mtime_ns
    pull()
    assert archive.stat().st_mtime_ns == original_mtime

    # A second successful dump with the same name must fail without replacing the first.
    acl.write_text("#!/bin/sh\nexit 0\n")
    (source / archive.name).write_bytes(b"older published archive")
    result = subprocess.run(command("success"), env=env, capture_output=True)
    assert result.returncode != 0
    assert (source / archive.name).read_bytes() == b"older published archive"
    assert list(staging.iterdir()) == stale
    # The pull reports the changed source and keeps the received archive.
    changed = subprocess.run(["bash", puller, f"{source}/", f"{destination}/"], capture_output=True)
    assert changed.returncode == 102
    assert archive.read_bytes() == b"complete archive"

    (source / archive.name).unlink()
    (source / archive.name).mkdir()
    result = subprocess.run(command("success"), env=env, capture_output=True)
    assert result.returncode != 0, "a directory collision must fail instead of creating a nested archive"
    assert not list((source / archive.name).iterdir())
    assert list(staging.iterdir()) == stale

    (source / archive.name).rmdir()
    acl.write_text("#!/bin/sh\nexit 1\n")
    result = subprocess.run(command("success"), env=env, capture_output=True)
    assert result.returncode != 0
    assert not list(source.iterdir()), "ACL failure must prevent publication"
    assert list(staging.iterdir()) == stale

print("Forgejo dump: running/failed/killed dumps stay private, ACL ordering, atomic publication and immutable retries passed")
