"""Bump versions, commit, tag, push, and publish a GitHub Release."""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from release_version import parse_version, read_version

ROOT = Path(__file__).resolve().parents[1]


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        args, cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def clean_worktree() -> None:
    if run("git", "status", "--porcelain", capture=True):
        raise ValueError("Working tree must be clean, including untracked files.")


def github_repo(url: str) -> str:
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?", url)
    if not match:
        raise ValueError("origin must be a github.com HTTPS or SSH repository URL.")
    return match.group(1)


def release(version: str, dry_run: bool) -> None:
    current, build = read_version(ROOT)
    if parse_version(version) <= parse_version(current):
        raise ValueError(f"New version must be greater than {current}.")
    if build >= 65535:
        raise ValueError("Build number has reached the Windows version limit.")
    clean_worktree()
    branch = run("git", "symbolic-ref", "--short", "HEAD", capture=True)
    remote_url = run("git", "remote", "get-url", "origin", capture=True)
    repo = github_repo(remote_url)
    run("gh", "auth", "status", "--hostname", "github.com")
    upstream = run("git", "rev-parse", "--abbrev-ref", "@{upstream}", capture=True)
    if upstream != f"origin/{branch}":
        raise ValueError("Current branch must track the same branch on origin.")
    remote_head = run("git", "ls-remote", "--exit-code", "origin", f"refs/heads/{branch}", capture=True)
    if remote_head.split()[0] != run("git", "rev-parse", "HEAD", capture=True):
        raise ValueError("HEAD must match origin. Push or update the branch first.")
    tag = f"v{version}"
    local_tags = run("git", "tag", "--list", tag, capture=True)
    remote_tags = run("git", "ls-remote", "origin", f"refs/tags/{tag}", capture=True)
    if local_tags or remote_tags:
        raise ValueError(f"Tag {tag} already exists locally or on origin.")
    # A successful API request distinguishes an absent release from network/auth errors.
    pages = run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases", capture=True)
    if any(item["tag_name"] == tag for page in json.loads(pages) for item in page):
        raise ValueError(f"Release {tag} already exists.")
    if not (ROOT / ".github/workflows/release.yml").is_file():
        raise ValueError("Release workflow is missing.")
    print(f"{current}+{build} -> {version}+{build + 1}", flush=True)
    print(f"Branch: {branch}; repository: {repo}; tag: {tag}", flush=True)
    if dry_run:
        print("Dry run: check/test, update pubspec + snap, commit, annotated tag, "
              "atomic push, then publish Release. No files or remote refs changed.")
        return

    flutter = ["fvm", "flutter"] if shutil.which("fvm") else ["flutter"]
    sdk = json.loads(run(*flutter, "--version", "--machine", capture=True))
    required = json.loads((ROOT / ".fvmrc").read_text())["flutter"]
    if sdk["frameworkVersion"] != required:
        raise ValueError(f"Use Flutter {required}, as pinned in .fvmrc.")
    run(sys.executable, "-m", "unittest", "discover", "-s", "tool", "-p", "test_*.py")
    run(*flutter, "pub", "get", "--enforce-lockfile")
    run(*flutter, "analyze")
    run(*flutter, "test")
    clean_worktree()

    pubspec = ROOT / "pubspec.yaml"
    snap = ROOT / "snap/snapcraft.yaml"
    pubspec_text = re.sub(
        r"^version: .+$", f"version: {version}+{build + 1}",
        pubspec.read_text(encoding="utf-8"), count=1, flags=re.MULTILINE,
    )
    snap_text, count = re.subn(
        r"^version: .+$", f"version: {version}",
        snap.read_text(encoding="utf-8"), count=1, flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError("snap/snapcraft.yaml has no version field.")
    pubspec.write_text(pubspec_text, encoding="utf-8")
    snap.write_text(snap_text, encoding="utf-8")
    run("git", "add", "--", "pubspec.yaml", "snap/snapcraft.yaml")
    run("git", "commit", "-m", f"chore: release {tag}", "--", "pubspec.yaml", "snap/snapcraft.yaml")
    run("git", "tag", "-a", tag, "-m", f"Azusa {version}")
    run("git", "push", "--atomic", "origin", f"HEAD:refs/heads/{branch}", f"refs/tags/{tag}")
    run("gh", "release", "create", tag, "--repo", repo, "--verify-tag",
        "--title", f"Azusa {version}", "--generate-notes", "--target", branch)
    print(f"Published {tag}. Follow the Release workflow in GitHub Actions.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="New stable version, e.g. 1.0.1")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        release(args.version, args.dry_run)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}\nNo automatic rollback was performed. "
              "Inspect git status, local/remote tags and GitHub Releases before retrying. "
              "See docs/releasing.md.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
