"""Generate Android signing material outside the repository, without printing secrets."""

import argparse
import base64
import hashlib
import os
import secrets
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate(output: Path) -> None:
    output = output.expanduser().resolve()
    if output == ROOT or ROOT in output.parents:
        raise ValueError("Signing material must be stored outside the repository.")
    if not shutil.which("keytool"):
        raise ValueError("keytool is required; install a JDK first.")
    # exist_ok=False intentionally refuses to replace existing signing material.
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    output.chmod(0o700)
    store_password = secrets.token_urlsafe(36)
    key_password = secrets.token_urlsafe(36)
    alias = "azusa-release"
    keystore = output / "azusa-release.jks"
    env = dict(os.environ, AZUSA_STORE_PASSWORD=store_password, AZUSA_KEY_PASSWORD=key_password)
    subprocess.run(
        ["keytool", "-genkeypair", "-noprompt", "-storetype", "JKS",
         "-keystore", str(keystore), "-alias", alias,
         "-keyalg", "RSA", "-keysize", "4096", "-validity", "10000",
         "-dname", "CN=Azusa Release, OU=Release, O=Azusa",
         "-storepass:env", "AZUSA_STORE_PASSWORD", "-keypass:env", "AZUSA_KEY_PASSWORD"],
        env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    keystore.chmod(0o600)
    values = {
        "ANDROID_KEYSTORE_BASE64": base64.b64encode(keystore.read_bytes()).decode("ascii"),
        "ANDROID_KEYSTORE_PASSWORD": store_password,
        "ANDROID_KEY_ALIAS": alias,
        "ANDROID_KEY_PASSWORD": key_password,
    }
    for name, value in values.items():
        descriptor = os.open(output / f"{name}.txt", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(value)
        (output / f"{name}.txt").chmod(0o600)
    certificate = subprocess.check_output(
        ["keytool", "-exportcert", "-keystore", str(keystore), "-alias", alias,
         "-storepass:env", "AZUSA_STORE_PASSWORD"], env=env, stderr=subprocess.PIPE,
    )
    fingerprint = hashlib.sha256(certificate).hexdigest()
    (output / "certificate-sha256.txt").write_text(fingerprint + "\n", encoding="ascii")
    (output / "certificate-sha256.txt").chmod(0o600)
    print(f"Signing material saved to: {output}")
    print("Add each ANDROID_*.txt file's content as the same-named GitHub Actions secret.")
    print(f"Certificate SHA-256: {fingerprint}")
    print("Back up this directory securely. Never regenerate the key for an existing app.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New private directory outside the repository")
    args = parser.parse_args()
    generate(args.output)
