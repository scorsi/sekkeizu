"""Encode a password in macOS kcpassword format and encrypt it with sops, never touching disk in clear.

Usage: set-autologin-password.py <sops> <destination>
"""

import getpass
import subprocess
import sys

# Fixed XOR key used by loginwindow to obfuscate /etc/kcpassword.
KEY = bytes([0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F])


def encode(password: str) -> bytes:
    # The trailing NUL plus padding to a multiple of 12 also covers the case where
    # the password length is itself a multiple of 12 (macOS 13+ expects a terminator).
    data = password.encode() + b"\0"
    data += b"\0" * (-len(data) % 12)
    return bytes(b ^ KEY[i % len(KEY)] for i, b in enumerate(data))


def main() -> None:
    sops, dest = sys.argv[1:3]
    pw = getpass.getpass("Mot de passe de la session : ")
    if not pw or pw != getpass.getpass("Confirmation : "):
        sys.exit("Mots de passe vides ou différents.")

    out = subprocess.run(
        [
            sops, "--encrypt",
            "--input-type", "binary", "--output-type", "binary",
            "--filename-override", dest,
            "/dev/stdin",
        ],
        input=encode(pw),
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    with open(dest, "wb") as f:
        f.write(out)
    print(f"Chiffré dans {dest} — pense à `git add {dest}` avant de rebuild.")


if __name__ == "__main__":
    main()
