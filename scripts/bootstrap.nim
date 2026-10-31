## Bootstrap a Mac into its nix-darwin configuration, once Nix is installed: run by
## bootstrap.sh (`nim r`, Nim and clang from nixpkgs), which documents the options.
## Not built by the flake: a fresh clone can't evaluate it before this has unlocked it.
import std/[os, osproc, posix, streams, strutils]

const
  nixBin = "/nix/var/nix/profiles/default/bin/nix"
  nixFlags = ["--extra-experimental-features", "nix-command flakes"]

proc log(msg: string) = stdout.writeLine "\e[1;34m==>\e[0m ", msg
proc warn(msg: string) = stderr.writeLine "\e[1;33m!!\e[0m ", msg
proc die(msg: string) {.noreturn.} =
  stderr.writeLine "\e[1;31mxx\e[0m ", msg
  quit 1

proc run(cmd: openArray[string]; dir = ""): int =
  let p = startProcess(cmd[0], dir, cmd.toOpenArray(1, cmd.high),
    options = {poUsePath, poParentStreams})
  result = p.waitForExit()
  p.close()

proc sh(cmd: openArray[string]; dir = "") =
  if run(cmd, dir) != 0:
    die "failed: " & quoteShellCommand(cmd)

proc capture(cmd: openArray[string]): tuple[code: int, output, errors: string] =
  # shortcut: stderr is drained after stdout, so a command writing >64 KiB to stderr
  # would hang; the commands captured here print a few lines at most.
  let p = startProcess(cmd[0], args = cmd.toOpenArray(1, cmd.high), options = {poUsePath})
  result.output = p.outputStream.readAll().strip()
  result.errors = p.errorStream.readAll()
  result.code = p.waitForExit()
  p.close()

proc nix(args: varargs[string]): seq[string] = @[nixBin] & @nixFlags & @args

# Private repo on a brand-new Mac: the system ssh has no FIDO2 support (and Apple's git would
# use it), so clone with nixpkgs' openssh + git. GIT_SSH_COMMAND comes from the environment.
proc withNixSsh(cmd: varargs[string]): seq[string] =
  nix("shell", "nixpkgs#openssh", "nixpkgs#git", "--command") & @cmd

# FIDO2 key handles in ~/.ssh (as written by `ssh-keygen -K`: id_ed25519_sk_rk…), private part only.
proc fidoHandles(): seq[string] =
  for f in walkFiles(getHomeDir() / ".ssh/id_*_sk*"):
    if not f.endsWith(".pub"):
      result.add f

proc versionKey(label: string): seq[int] =
  for part in label.split(AllChars - Digits):
    if part.len > 0:
      result.add parseInt(part)

proc newer(a, b: seq[int]): bool =
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]:
      return a[i] > b[i]
  a.len > b.len

proc main() =
  var
    host = "jiban"
    dir = getHomeDir() / "repositories/sekkeizu"
    repo = ""
    gitCryptKey = ""
  let params = commandLineParams()
  var i = 0
  while i < params.len:
    let flag = params[i]
    if flag notin ["--host", "--dir", "--repo", "--git-crypt-key"]:
      die "unknown option: " & flag & " (see bootstrap.sh --help)"
    if i + 1 >= params.len:
      die flag & " expects a value"
    let value = params[i + 1]
    case flag
    of "--host": host = value
    of "--dir": dir = value
    of "--repo": repo = value
    else: gitCryptKey = absolutePath(value) # unlock runs from the repo
    i += 2

  log "host: " & host & " · repo: " & dir
  sh ["sudo", "-v"] # asks for the password once, up front

  # ─── 1. Command Line Tools (git, compilers) ──────────────────────────
  if capture(["xcode-select", "-p"]).code == 0:
    log "Command Line Tools: already installed"
  else:
    log "Command Line Tools: headless install"
    const marker = "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    writeFile(marker, "")
    try:
      var label = ""
      for line in capture(["softwareupdate", "-l"]).output.splitLines:
        let l = line.strip()
        if l.startsWith("* Label: Command Line Tools"):
          let candidate = l["* Label: ".len .. ^1]
          if label == "" or newer(versionKey(candidate), versionKey(label)):
            label = candidate
      if label == "":
        die "no Command Line Tools package found via softwareupdate"
      sh ["sudo", "softwareupdate", "-i", label, "--verbose"]
    finally:
      removeFile(marker)

  # ─── 2. The repo ──────────────────────────────────────────────────────
  # The SSH key lives on the hardware key as a resident credential: `ssh-keygen -K` pulls its
  # handle into ~/.ssh.
  var sshCmd = "ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes"
  if repo.startsWith("git@") or repo.startsWith("ssh://"):
    if fidoHandles().len == 0:
      log "FIDO2 key: no handle in ~/.ssh, fetching it (plug the key in, PIN then touch)"
      let sshDir = getHomeDir() / ".ssh"
      createDir(sshDir)
      setFilePermissions(sshDir, {fpUserRead, fpUserWrite, fpUserExec})
      sh(withNixSsh("ssh-keygen", "-K"), sshDir)
    for handle in fidoHandles():
      sshCmd.add " -i " & handle
  putEnv("GIT_SSH_COMMAND", sshCmd)

  if fileExists(dir / "flake.nix"):
    log "repo: present in " & dir
  elif repo != "":
    log "repo: cloning " & repo
    sh withNixSsh("git", "clone", repo, dir)
  else:
    die "no flake in " & dir & ": pass --repo <url> or copy the repo over (e.g. scp -r from the laptop)"

  # Live clones of the owner's other repos, next to where this one came from (GitHub, FIDO2 key):
  # kanna is what ~/.config/nvim links to on a dev machine (`kanna-dev`, kiso.reposDir); kiso is
  # where its changes are made. The flake inputs don't need them.
  let reposDir = getHomeDir() / "repositories"
  for name in ["kanna", "kiso"]:
    if dirExists(reposDir / name / ".git"):
      log name & ": present in " & reposDir / name
    elif repo != "":
      let url = repo.rsplit('/', 1)[0] & "/" & name & ".git"
      log name & ": cloning " & url
      createDir(reposDir)
      sh withNixSsh("git", "clone", url, reposDir / name)
    else:
      warn name & " missing from " & reposDir & " (no --repo): clone it by hand"

  # secrets/ and modules-private/ are git-crypt encrypted (.gitattributes): unlock before anything
  # evaluates the flake. The filters call git-crypt by name, not by this store path, so a GC can't
  # break them (the home profile has it after the switch); the hook refuses to commit them in clear.
  let gitCrypt = capture(nix("build", "--no-link", "--print-out-paths", "nixpkgs#git-crypt"))
  if gitCrypt.code != 0:
    stderr.write gitCrypt.errors
    die "git-crypt not found in nixpkgs"
  putEnv("PATH", gitCrypt.output / "bin" & ":" & getEnv("PATH"))
  if capture(["git", "-C", dir, "config", "--get", "filter.git-crypt.smudge"]).code == 0:
    log "git-crypt: already unlocked"
  else:
    if gitCryptKey == "":
      die "secrets/ and modules-private/ are encrypted: pass --git-crypt-key <file> (password manager, base64 -d)"
    log "git-crypt: unlocking"
    sh(["git-crypt", "unlock", gitCryptKey], dir)
    for (key, value) in [("filter.git-crypt.smudge", "git-crypt smudge"),
                         ("filter.git-crypt.clean", "git-crypt clean"),
                         ("filter.git-crypt.required", "true"),
                         ("diff.git-crypt.textconv", "git-crypt diff")]:
      sh ["git", "-C", dir, "config", key, value]
  sh ["git", "-C", dir, "config", "core.hooksPath", "scripts/hooks"]

  # Nix only sees files tracked by git: an unadded file = "doesn't exist".
  for line in capture(["git", "-C", dir, "status", "--porcelain"]).output.splitLines:
    if line.startsWith("??"):
      warn "files untracked by git in " & dir & ": Nix will ignore them (git add?)"
      break

  # The repo's own flakes (inputs scorsi-*) come from kajiba, which a fresh machine can't reach yet
  # (no kekkai or annai yet): take them from their GitHub mirrors, at the revisions locked in
  # flake.lock. Same rewrite as scripts/via-github.nu. Fetched now as the user, with the FIDO2 key; every
  # evaluation below, root's included, then finds them in the store.
  putEnv("GIT_CONFIG_COUNT", "2")
  putEnv("GIT_CONFIG_KEY_0", "url.ssh://git@github.com/scorsi/.insteadOf")
  putEnv("GIT_CONFIG_VALUE_0", "https://kajiba.uchi.scorsi.dev/scorsi/")
  putEnv("GIT_CONFIG_KEY_1", "url.ssh://git@github.com/scorsi/.insteadOf")
  putEnv("GIT_CONFIG_VALUE_1", "ssh://git@forgejo.uchi.scorsi.dev:2222/scorsi/")
  log "inputs: fetching (GitHub mirrors)"
  sh withNixSsh(nix("flake", "archive", dir))

  # ─── 3. Checks before switching ───────────────────────────────────────
  let flake = dir & "#darwinConfigurations." & host
  log "evaluating " & host
  let configured = capture(nix("eval", "--raw", flake & ".config.system.primaryUser"))
  if configured.code != 0:
    stderr.write configured.errors
    die "evaluation failed: no host '" & host & "' or a Nix error (see above)"
  let me = $getpwuid(geteuid()).pw_name
  if configured.output != me:
    die "kiso.owner.name = '" & configured.output & "' but you are '" & me & "': fix modules/meta/owner.nix"

  # ─── 4. /etc files nix-darwin refuses to overwrite ───────────────────
  # nix-darwin aborts if it finds these files unmanaged by it: rename them once.
  for f in ["/etc/bashrc", "/etc/zshrc", "/etc/zprofile", "/etc/shells", "/etc/nix/nix.conf",
            "/etc/nix/nix.custom.conf"]:
    if fileExists(f) and not symlinkExists(f):
      log "moving aside: " & f & " -> " & f & ".before-nix-darwin"
      sh ["sudo", "mv", f, f & ".before-nix-darwin"]

  # ─── 5. Switch ─────────────────────────────────────────────────────────
  if findExe("darwin-rebuild") != "":
    log "switch (darwin-rebuild already installed)"
    sh ["sudo", "darwin-rebuild", "switch", "--flake", dir & "#" & host]
  else:
    # First switch: darwin-rebuild comes from the flake, at the version pinned in flake.lock.
    log "first switch"
    sh @["sudo", "-H"] & nix("run", dir & "#darwin-rebuild", "--", "switch", "--flake", dir & "#" & host)

  log "done. Open a new terminal (shell: fish). Later rebuilds: drs"

main()
