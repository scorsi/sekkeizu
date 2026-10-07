## Encode a password in macOS kcpassword format and encrypt it with sops, never touching disk in clear.
## Usage: set-autologin-password <sops> <destination>
import std/[os, osproc, streams, strutils, terminal]

# Fixed XOR key used by loginwindow to obfuscate /etc/kcpassword.
const key = [0x7D'u8, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F]

proc encode(password: string): string =
  # The trailing NUL plus padding to a multiple of 12 also covers the case where
  # the password length is itself a multiple of 12 (macOS 13+ expects a terminator).
  var data = password & '\0'
  while data.len mod 12 != 0:
    data.add '\0'
  result = newString(data.len)
  for i, c in data:
    result[i] = char(uint8(c) xor key[i mod key.len])

proc main() =
  let sops = paramStr(1)
  let dest = paramStr(2)

  var pw: string
  var confirmation: string
  if not readPasswordFromStdin("Mot de passe de la session : ", pw) or
      not readPasswordFromStdin("Confirmation : ", confirmation) or
      pw.len == 0 or pw != confirmation:
    quit "Mots de passe vides ou différents.", 1

  let p = startProcess(sops, args = [
    "--encrypt", "--input-type", "binary", "--output-type", "binary",
    "--filename-override", dest, "--output", dest, "/dev/stdin"])
  p.inputStream.write encode(pw)
  p.inputStream.close()
  let errors = p.errorStream.readAll()
  if p.waitForExit() != 0:
    quit "sops a échoué :\n" & errors.strip(), 1
  echo "Chiffré dans ", dest, " — pense à `git add ", dest, "` avant de rebuild."

main()
