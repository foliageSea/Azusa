import json
import tempfile
import unittest
from pathlib import Path

from reset_webdav import create_fixture, reset_workspace


class ResetWorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="azu-webdav-", dir="/tmp/opencode")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name).resolve()
        self.info = self.workspace / "server.json"
        self.info.write_text(json.dumps({"workspace": str(self.workspace)}), encoding="utf-8")
        self.root = self.workspace / "share"

    def test_restores_fixture_and_preserves_metadata(self):
        create_fixture(self.root)
        expected = {p.relative_to(self.root): p.read_bytes()
                    for p in self.root.rglob("*") if p.is_file()}
        next(self.root.rglob("*.mkv")).unlink()
        (self.root / "extra.txt").write_text("extra", encoding="utf-8")
        log = self.workspace / "requests.jsonl"
        log.write_text("test log\n", encoding="utf-8")
        original_info = self.info.read_bytes()
        for _ in range(2):
            reset_workspace(self.workspace)
            actual = {p.relative_to(self.root): p.read_bytes()
                      for p in self.root.rglob("*") if p.is_file()}
            self.assertEqual(actual, expected)
            self.assertTrue((self.root / "操作测试").is_dir())
            self.assertEqual(self.info.read_bytes(), original_info)
            self.assertEqual(log.read_text(encoding="utf-8"), "test log\n")

    def test_creates_missing_share(self):
        reset_workspace(self.workspace)
        self.assertEqual(len(list(self.root.rglob("*.mkv"))), 3)

    def test_rejects_mismatched_workspace(self):
        self.info.write_text('{"workspace": "/elsewhere"}', encoding="utf-8")
        with self.assertRaises(ValueError):
            reset_workspace(self.workspace)
        self.assertFalse(self.root.exists())

    def test_rejects_missing_metadata(self):
        self.info.unlink()
        with self.assertRaises(OSError):
            reset_workspace(self.workspace)

    def test_rejects_share_symlink_without_touching_target(self):
        outside = self.workspace / "outside"
        outside.mkdir()
        sentinel = outside / "keep.txt"
        sentinel.write_text("keep", encoding="utf-8")
        self.root.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            reset_workspace(self.workspace)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_does_not_follow_symlinks_inside_share(self):
        self.root.mkdir()
        outside = self.workspace / "outside"
        outside.mkdir()
        sentinel = outside / "keep.txt"
        sentinel.write_text("keep", encoding="utf-8")
        (self.root / "link").symlink_to(outside, target_is_directory=True)
        reset_workspace(self.workspace)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_rejects_directory_outside_fixture_base(self):
        with self.assertRaises(ValueError):
            reset_workspace(Path(__file__).resolve().parent)


if __name__ == "__main__":
    unittest.main()
