import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import generate_android_signing
import package_release
import release
from release_version import parse_version, read_version, validate_tag


class ReleaseVersionTest(unittest.TestCase):
    def test_parse_version(self):
        self.assertEqual(parse_version("1.20.3"), (1, 20, 3))
        for version in ("v1.0.0", "01.0.0", "1.0", "1.0.0-beta.1", "1.0.0+2", "65536.0.0"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                parse_version(version)

    def test_metadata_and_tag(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "pubspec.yaml").write_text("name: azusa\nversion: 1.2.3+42\n")
            self.assertEqual(read_version(root), ("1.2.3", 42))
            self.assertEqual(validate_tag(root, "v1.2.3"), ("1.2.3", 42))
            for tag in ("v1.2.4", "1.2.3", "v1.2.3;echo bad"):
                with self.assertRaises(ValueError):
                    validate_tag(root, tag)
            for version in ("1.0.0", "1.0.0+0", "1.0.0+65536"):
                (root / "pubspec.yaml").write_text(f"version: {version}\n")
                with self.assertRaises(ValueError):
                    read_version(root)

    def test_github_remote(self):
        for url in ("https://github.com/owner/repo.git", "git@github.com:owner/repo.git",
                    "https://github.com/owner/repo"):
            self.assertEqual(release.github_repo(url), "owner/repo")
        with self.assertRaises(ValueError):
            release.github_repo("https://example.com/owner/repo.git")


class ReleaseScriptTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "pubspec.yaml").write_text("name: azusa\nversion: 1.0.0+1\n")
        (self.root / "snap").mkdir()
        (self.root / "snap/snapcraft.yaml").write_text("name: azusa\nversion: 1.0.0\n")
        (self.root / ".github/workflows").mkdir(parents=True)
        (self.root / ".github/workflows/release.yml").touch()
        (self.root / ".fvmrc").write_text('{"flutter":"3.47.6"}')
        self.calls = []
        self.dirty = False
        self.existing_tag = False
        self.existing_release = False
        self.wrong_head = False
        self.fail_push = False
        root_patch = patch.object(release, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def fake_run(self, *args, capture=False):
        self.calls.append(args)
        if args[:3] == ("git", "status", "--porcelain"):
            return " M file" if self.dirty else ""
        if args[:2] == ("git", "symbolic-ref"):
            return "main"
        if args[:3] == ("git", "remote", "get-url"):
            return "https://github.com/owner/repo.git"
        if args[:3] == ("git", "rev-parse", "--abbrev-ref"):
            return "origin/main"
        if args[:2] == ("git", "ls-remote"):
            if "refs/heads/main" in args:
                return "remote-sha\trefs/heads/main" if self.wrong_head else "abc\trefs/heads/main"
            return "abc\trefs/tags/v1.0.1" if self.existing_tag else ""
        if args == ("git", "rev-parse", "HEAD"):
            return "abc"
        if args[:3] == ("git", "tag", "--list"):
            return "v1.0.1" if self.existing_tag else ""
        if args[:2] == ("gh", "api"):
            return json.dumps([[{"tag_name": "v1.0.1"}]] if self.existing_release else [[]])
        if "--machine" in args:
            return '{"frameworkVersion":"3.47.6"}'
        if args[:2] == ("git", "push") and self.fail_push:
            raise subprocess.CalledProcessError(1, args)
        return ""

    def test_dry_run_does_not_write_or_publish(self):
        original = (self.root / "pubspec.yaml").read_bytes()
        with patch.object(release, "run", side_effect=self.fake_run):
            release.release("1.0.1", True)
        self.assertEqual((self.root / "pubspec.yaml").read_bytes(), original)
        self.assertFalse(any(args[:2] == ("git", "push") for args in self.calls))
        self.assertFalse(any(args[:3] == ("gh", "release", "create") for args in self.calls))

    def test_preflight_rejects_unsafe_states(self):
        for field in ("dirty", "existing_tag", "existing_release", "wrong_head"):
            with self.subTest(field=field):
                setattr(self, field, True)
                with patch.object(release, "run", side_effect=self.fake_run), self.assertRaises(ValueError):
                    release.release("1.0.1", True)
                setattr(self, field, False)
        with self.assertRaises(ValueError):
            release.release("1.0.0", True)

    def test_release_updates_only_version_files_and_publishes_after_push(self):
        with patch.object(release, "run", side_effect=self.fake_run):
            release.release("1.0.1", False)
        self.assertEqual(read_version(self.root), ("1.0.1", 2))
        self.assertIn("version: 1.0.1\n", (self.root / "snap/snapcraft.yaml").read_text())
        push = next(args for args in self.calls if args[:2] == ("git", "push"))
        self.assertIn("--atomic", push)
        create = next(args for args in self.calls if args[:3] == ("gh", "release", "create"))
        self.assertLess(self.calls.index(push), self.calls.index(create))
        self.assertIn("--verify-tag", create)

    def test_push_failure_does_not_create_release_or_rollback(self):
        self.fail_push = True
        with patch.object(release, "run", side_effect=self.fake_run), self.assertRaises(subprocess.CalledProcessError):
            release.release("1.0.1", False)
        self.assertFalse(any(args[:3] == ("gh", "release", "create") for args in self.calls))
        self.assertEqual(read_version(self.root), ("1.0.1", 2))

    def test_failed_tests_do_not_bump_commit_or_publish(self):
        def fail_tests(*args, capture=False):
            if args[-1] == "test":
                raise subprocess.CalledProcessError(1, args)
            return self.fake_run(*args, capture=capture)

        with patch.object(release, "run", side_effect=fail_tests), self.assertRaises(subprocess.CalledProcessError):
            release.release("1.0.1", False)
        self.assertEqual(read_version(self.root), ("1.0.0", 1))
        self.assertFalse(any(args[:2] == ("git", "commit") for args in self.calls))
        self.assertFalse(any(args[:2] == ("git", "push") for args in self.calls))


class PackagingTest(unittest.TestCase):
    def test_checksums_require_exact_asset_set(self):
        with tempfile.TemporaryDirectory() as temp:
            dist = Path(temp)
            with self.assertRaises(ValueError):
                package_release.checksums("1.0.0", dist)
            suffixes = ("android-arm64-v8a.apk", "windows-x64-setup.exe",
                        "macos-arm64.dmg", "linux-amd64.deb")
            for suffix in suffixes:
                (dist / f"Azusa-1.0.0-{suffix}").write_bytes(b"package")
            package_release.checksums("1.0.0", dist)
            lines = (dist / "SHA256SUMS.txt").read_text().splitlines()
            self.assertEqual(len(lines), 4)
            self.assertTrue(all(line.startswith(hashlib.sha256(b"package").hexdigest()) for line in lines))

    def test_signing_generator_refuses_repository_path(self):
        with self.assertRaises(ValueError):
            generate_android_signing.generate(generate_android_signing.ROOT / "private-keys")

    def test_signing_generator_refuses_existing_directory(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(generate_android_signing.shutil, "which", return_value="keytool"):
            with self.assertRaises(FileExistsError):
                generate_android_signing.generate(Path(temp))


if __name__ == "__main__":
    unittest.main()
