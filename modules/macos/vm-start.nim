## Starts a vfkit VM from its state directory (see vfkit-host.nix), then becomes vfkit: launchd's
## SIGTERM must reach vfkit itself, which powers the guest off cleanly.
## Usage: vm-start <state dir> <name> <vfkit> <cpus> <memory MiB> <mac>
import std/[os, posix, times]

proc main() =
  if paramCount() != 6:
    quit "usage: vm-start <state dir> <name> <vfkit> <cpus> <memory MiB> <mac>", 2
  let
    state = paramStr(1)
    name = paramStr(2)
    vfkit = paramStr(3)
  createDir(state)
  setCurrentDir(state)

  # vfkit never reopens its files (and Virtualization.framework rewrites the console from the
  # start), so newsyslog can't rotate them live: rotate at each start instead. Empty files are
  # skipped, so a crash loop doesn't push the useful logs out.
  for f in ["vfkit.log", "console.log"]:
    if fileExists(f) and getFileSize(f) > 0:
      for i in [2, 1]:
        if fileExists(f & "." & $i):
          moveFile(f & "." & $i, f & "." & $(i + 1))
      moveFile(f, f & ".1")
  let log = open("vfkit.log", fmAppend)
  discard dup2(log.getFileHandle, 1)
  discard dup2(log.getFileHandle, 2)

  if not fileExists("disk.raw"):
    stdout.writeLine now().format("yyyy-MM-dd HH:mm:ss"), " no disk: nix run .#install-", name
    quit 0

  # Left behind by a power cut: vfkit won't bind over it (launchd runs one instance).
  removeFile("vm.sock")
  let create = if fileExists("efi-vars"): "" else: ",create"
  let args = allocCStringArray([vfkit,
    "--cpus", paramStr(4), "--memory", paramStr(5),
    "--bootloader", "efi,variable-store=" & state / "efi-vars" & create,
    "--device", "virtio-rng",
    "--device", "virtio-blk,path=" & state / "disk.raw",
    "--device", "virtio-net,nat,mac=" & paramStr(6),
    "--device", "virtio-serial,logFilePath=" & state / "console.log",
    "--restful-uri", "unix://" & state / "vm.sock"])
  discard execv(vfkit.cstring, args)
  quit "exec " & vfkit & ": " & $strerror(errno), 1

main()
