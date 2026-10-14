## A VM keeps the same identity across reinstalls when secrets/<vm>/identity.yaml exists (sops,
## admin key): SSH host key (so no re-key of secrets/<vm>/) and Tailscale state (same node, same
## IP). macOS can't mount ext4, so the files are written into the fresh image offline, with
## debugfs, before its first boot. Decrypted only into a private temporary directory, removed on
## exit and on Ctrl-C. Usage: restore-vm-identity <disk.raw> <identity.yaml>
import std/[os, osproc, posix, streams, strutils, tempfiles]

const
  sops {.strdefine.} = "sops"
  sgdisk {.strdefine.} = "sgdisk"
  debugfs {.strdefine.} = "debugfs"
  # sops key, path relative to /persist, mode.
  files = [
    ("ssh_host_ed25519_key", "/etc/ssh/ssh_host_ed25519_key", "0100600"),
    ("ssh_host_ed25519_key_pub", "/etc/ssh/ssh_host_ed25519_key.pub", "0100644"),
    ("tailscaled_state", "/var/lib/tailscale/tailscaled.state", "0100600")]
  dirs = [("/etc", "040755"), ("/etc/ssh", "040755"), ("/var", "040755"),
          ("/var/lib", "040755"), ("/var/lib/tailscale", "040700")]

var seed = ""

proc cleanup() =
  if seed != "":
    removeDir(seed)

proc die(msg: string) {.noreturn.} =
  cleanup()
  quit "restore-vm-identity: " & msg, 1

# shortcut: stderr is drained after stdout, so a command writing >64 KiB to stderr would hang;
# sops, sgdisk and debugfs print a few lines at most.
proc run(cmd: openArray[string]; input = ""): tuple[code: int, output, errors: string] =
  let p = startProcess(cmd[0], args = cmd.toOpenArray(1, cmd.high), options = {})
  p.inputStream.write input
  p.inputStream.close()
  result.output = p.outputStream.readAll()
  result.errors = p.errorStream.readAll()
  result.code = p.waitForExit()
  p.close()

proc restore(disk, identity: string) =
  for (key, _, _) in files:
    let r = run([sops, "-d", "--extract", "[\"" & key & "\"]", identity])
    if r.code != 0:
      stderr.write r.errors
      die "sops could not decrypt " & key
    writeFile(seed / key, r.output)

  # make-disk-image's "efi" layout: partition 1 is the ESP, 2 the ext4 disk (/persist).
  var first = -1
  for line in run([sgdisk, "-i", "2", disk]).output.splitLines:
    if line.startsWith("First sector:"):
      first = parseInt(line.splitWhitespace()[2])
  if first < 0:
    die "no partition 2 in " & disk
  let fs = disk & "?offset=" & $(first * 512)

  # Errors on mkdir (already there) and rm (not there) are expected; what counts is checked right
  # after.
  var script = ""
  var modes = @dirs
  for (dir, _) in dirs:
    script.add "mkdir " & dir & "\n"
  for (key, path, mode) in files:
    script.add "rm " & path & "\nwrite " & seed / key & " " & path & "\n"
    modes.add (path, mode)
  for (path, mode) in modes:
    script.add "sif " & path & " mode " & mode & "\nsif " & path & " uid 0\nsif " & path & " gid 0\n"
  discard run([debugfs, "-w", "-f", "-", fs], script)

  # debugfs exits 0 even when a command fails: read every file back.
  for (key, path, _) in files:
    if run([debugfs, "-R", "cat " & path, fs]).output != readFile(seed / key):
      die path & " badly written into the image"

proc main() =
  if paramCount() != 2:
    quit "usage: restore-vm-identity <disk.raw> <identity.yaml>", 2
  if not existsEnv("SOPS_AGE_KEY_FILE"):
    putEnv("SOPS_AGE_KEY_FILE", getHomeDir() / ".config/sops/age/keys.txt")
  discard umask(0o077)
  seed = createTempDir("vm-identity", "")
  setControlCHook(proc() {.noconv.} =
    cleanup()
    quit 130)
  try:
    restore(paramStr(1), paramStr(2))
  finally:
    cleanup()
  echo "identity restored into the image (SSH host key, Tailscale state)"

main()
