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
        self.assertEqual(len(list((self.root / "剧集测试").rglob("*.mkv"))), 3)
        self.assertEqual(len(list((self.root / "批量整理测试").rglob("*.mkv"))), 12)

    def test_batch_fixture_has_multiple_series_seasons_and_matching_subtitles(self):
        create_fixture(self.root)
        batch = self.root / "批量整理测试"
        self.assertEqual({p.name for p in batch.iterdir()}, {"绝命毒师", "风骚律师"})
        for series in batch.iterdir():
            self.assertEqual({p.name for p in series.iterdir()}, {"Season 01", "Season 02"})
        subtitles = list(batch.rglob("*.zh.srt"))
        self.assertEqual(len(subtitles), 4)
        for subtitle in subtitles:
            self.assertTrue(subtitle.with_name(subtitle.name.removesuffix(".zh.srt") + ".mkv").is_file())
        self.assertEqual(len(list(batch.rglob("说明.txt"))), 4)

    def test_cleanup_fixture_has_empty_trees_and_nonempty_protection_cases(self):
        create_fixture(self.root)
        cleanup = self.root / "空目录清理测试"
        for relative in [
            "可删除-单层空目录",
            "可删除-嵌套空目录/第二层/第三层",
            "应保留-含普通文件/可删除的空子目录",
        ]:
            self.assertEqual(list((cleanup / relative).iterdir()), [])
        for relative in [
            "应保留-含隐藏文件/.keep",
            "应保留-含NFO/tvshow.nfo",
            "应保留-含字幕/episode.zh.srt",
            "应保留-含普通文件/说明.txt",
        ]:
            self.assertTrue((cleanup / relative).is_file())
        self.assertTrue((cleanup / "应保留-含隐藏目录/.hidden").is_dir())
        self.assertTrue((cleanup / "应保留-含回收站/#recycle").is_dir())

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
