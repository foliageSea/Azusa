"""Shared, dependency-free release version validation."""

import re
from pathlib import Path


def parse_version(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise ValueError("Version must be X.Y.Z (no v prefix or prerelease suffix).")
    parts = tuple(map(int, value.split(".")))
    if any(part > 65535 for part in parts):
        raise ValueError("Windows version components must not exceed 65535.")
    return parts


def read_version(root: Path) -> tuple[str, int]:
    text = (root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version: (\S+)\+(\d+)\s*$", text, re.MULTILINE)
    if not match:
        raise ValueError("pubspec.yaml must contain version: X.Y.Z+BUILD.")
    version, build = match.group(1), int(match.group(2))
    parse_version(version)
    if not 1 <= build <= 65535:
        raise ValueError("Build number must be between 1 and 65535.")
    return version, build


def validate_tag(root: Path, tag: str) -> tuple[str, int]:
    version, build = read_version(root)
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match pubspec.yaml (v{version}).")
    return version, build
