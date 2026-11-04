"""Validate release metadata and package native Flutter build output."""

import argparse
import hashlib
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from release_version import validate_tag

ROOT = Path(__file__).resolve().parents[1]


def run(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def metadata(tag: str) -> None:
    version, build = validate_tag(ROOT, tag)
    values = f"version={version}\nbuild={build}\n"
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write(values)
    print(values, end="")


def linux(version: str, dist: Path) -> None:
    if run("dpkg", "--print-architecture") != "amd64":
        raise ValueError("Linux packages must be built on amd64.")
    bundle = ROOT / "build/linux/x64/release/bundle"
    if not (bundle / "azusa").is_file():
        raise ValueError("Linux release bundle is missing.")
    with tempfile.TemporaryDirectory(prefix="azusa-deb-") as temp:
        work = Path(temp)
        stage = work / "package"
        control = stage / "DEBIAN"
        control.mkdir(parents=True)
        app = stage / "opt/azusa"
        shutil.copytree(bundle, app, symlinks=True)
        bin_dir = stage / "usr/bin"
        bin_dir.mkdir(parents=True)
        (bin_dir / "azusa").symlink_to("/opt/azusa/azusa")
        desktop_dir = stage / "usr/share/applications"
        desktop_dir.mkdir(parents=True)
        (desktop_dir / "com.foliage.azusa.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Azusa\n"
            "Comment=WebDAV media organizer\nExec=/opt/azusa/azusa\n"
            "Icon=com.foliage.azusa\nTerminal=false\nCategories=Utility;Network;\n",
            encoding="utf-8",
        )
        icon = stage / "usr/share/icons/hicolor/scalable/apps"
        icon.mkdir(parents=True)
        shutil.copy2(ROOT / "assets/icon/icon_rounded.svg", icon / "com.foliage.azusa.svg")
        license_dir = stage / "usr/share/doc/azusa"
        license_dir.mkdir(parents=True)
        shutil.copy2(ROOT / "LICENSE", license_dir / "copyright")
        # dpkg-shlibdeps resolves system dependencies using the actual runner's
        # package database, including distro-specific names such as *t64.
        debian = work / "debian"
        debian.mkdir()
        (debian / "control").write_text(
            "Source: azusa\nSection: utils\nPriority: optional\n"
            "Maintainer: foliageSea <noreply@github.com>\n"
            "\nPackage: azusa\nArchitecture: amd64\nDescription: Azusa\n",
            encoding="utf-8",
        )
        elf_files = []
        for file in app.rglob("*"):
            if file.is_file() and not file.is_symlink():
                with file.open("rb") as stream:
                    is_elf = stream.read(4) == b"\x7fELF"
                if is_elf:
                    linked = run("ldd", str(file))
                    if "not found" in linked:
                        raise ValueError(f"Unresolved runtime library in {file}:\n{linked}")
                    elf_files.append(f"-e{file}")
        deps = run(
            "dpkg-shlibdeps", "--ignore-missing-info", f"-l{app / 'lib'}",
            "-O", *elf_files, cwd=work,
        )
        dependencies = next(line.split("=", 1)[1] for line in deps.splitlines()
                            if line.startswith("shlibs:Depends="))
        if "libsecret-1-0" not in dependencies:
            dependencies += ", libsecret-1-0"
        size = sum(file.stat().st_size for file in stage.rglob("*") if file.is_file()) // 1024 + 1
        (control / "control").write_text(
            f"Package: azusa\nVersion: {version}\nArchitecture: amd64\n"
            "Maintainer: foliageSea <noreply@github.com>\nSection: utils\nPriority: optional\n"
            f"Installed-Size: {size}\nDepends: {dependencies}\n"
            "Recommends: gnome-keyring\nHomepage: https://github.com/foliageSea/Azusa\n"
            "Description: WebDAV media organizer\n"
            " Organize and rename WebDAV media with AI-assisted suggestions.\n",
            encoding="utf-8",
        )
        for directory in stage.rglob("*"):
            if directory.is_dir() and not directory.is_symlink():
                directory.chmod(0o755)
        target = dist / f"Azusa-{version}-linux-amd64.deb"
        print(run("dpkg-deb", "--root-owner-group", "--build", str(stage), str(target)))
        print(run("dpkg-deb", "--info", str(target)))


def macos(version: str, build: int, dist: Path) -> None:
    source = ROOT / "build/macos/Build/Products/Release/azusa.app"
    with (source / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info["CFBundleShortVersionString"] != version or str(info["CFBundleVersion"]) != str(build):
        raise ValueError("macOS application version does not match release metadata.")
    # Check every Mach-O payload, not only the launcher.
    for file in source.rglob("*"):
        if file.is_file() and not file.is_symlink() and "Mach-O" in run("file", "-b", str(file)):
            archs = run("lipo", "-archs", str(file))
            if archs != "arm64":
                raise ValueError(f"Expected arm64 only, got {archs}: {file}")
    run("codesign", "--verify", "--deep", "--strict", str(source))
    with tempfile.TemporaryDirectory(prefix="azusa-dmg-") as temp:
        stage = Path(temp)
        run("ditto", str(source), str(stage / "Azusa.app"))
        (stage / "Applications").symlink_to("/Applications")
        target = dist / f"Azusa-{version}-macos-arm64.dmg"
        print(run("hdiutil", "create", "-volname", f"Azusa {version}",
                  "-srcfolder", str(stage), "-format", "UDZO", str(target)))
        print(run("hdiutil", "verify", str(target)))


def checksums(version: str, dist: Path) -> None:
    expected = {
        f"Azusa-{version}-android-arm64-v8a.apk",
        f"Azusa-{version}-windows-x64-setup.exe",
        f"Azusa-{version}-macos-arm64.dmg",
        f"Azusa-{version}-linux-amd64.deb",
    }
    actual = {file.name for file in dist.iterdir() if file.is_file()}
    if actual != expected:
        raise ValueError(f"Unexpected release assets: expected {expected}, got {actual}")
    lines = []
    for name in sorted(expected):
        file = dist / name
        if not file.stat().st_size:
            raise ValueError(f"Empty release asset: {name}")
        digest = hashlib.sha256()
        with file.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        lines.append(f"{digest.hexdigest()}  {name}\n")
    (dist / "SHA256SUMS.txt").write_text("".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["metadata", "linux", "macos", "checksums"])
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    version, build = validate_tag(ROOT, args.tag)
    if args.command == "metadata":
        metadata(args.tag)
        return
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    if args.command == "macos":
        macos(version, build, dist)
    elif args.command == "linux":
        linux(version, dist)
    else:
        checksums(version, dist)


if __name__ == "__main__":
    main()
