"""Restore a local WebDAV workspace's share directory using only the stdlib."""

import argparse
import json
import shutil
from pathlib import Path


def create_fixture(root):
    episodes = root / "剧集测试" / "绝命毒师" / "Season 01"
    episodes.mkdir(parents=True)
    for number in [1, 2, 3]:
        (episodes / f"Breaking.Bad.S01E{number:02d}.1080p.mkv").write_bytes(
            f"AZU TEST VIDEO PLACEHOLDER EPISODE {number}\n".encode())
    (episodes / "Breaking.Bad.S01E01.zh.srt").write_text(
        "1\n00:00:01,000 --> 00:00:02,000\n这只是测试字幕。\n", encoding="utf-8")
    (episodes / "说明 100%.txt").write_text("仅用于 WebDAV 路径测试。", encoding="utf-8")
    (root / "操作测试").mkdir()
    create_batch_fixture(root / "批量整理测试")
    create_cleanup_fixture(root / "空目录清理测试")


def create_batch_fixture(root):
    for title, filename in [
        ("绝命毒师", "Breaking.Bad"),
        ("风骚律师", "Better.Call.Saul"),
    ]:
        for season in [1, 2]:
            # Extra release folders exercise traversal beyond one child level.
            directory = root / title / f"Season {season:02d}" / "发布组 100%"
            directory.mkdir(parents=True)
            for episode in [1, 2, 3]:
                stem = f"{filename}.S{season:02d}E{episode:02d}.1080p"
                (directory / f"{stem}.mkv").write_bytes(
                    f"AZU TEST VIDEO PLACEHOLDER {stem}\n".encode())
                if episode == 1:
                    (directory / f"{stem}.zh.srt").write_text(
                        "1\n00:00:01,000 --> 00:00:02,000\n这只是测试字幕。\n",
                        encoding="utf-8")
            (directory / "说明.txt").write_text(
                "非视频文件，整理后应留在原目录。", encoding="utf-8")


def create_cleanup_fixture(root):
    for relative in [
        "可删除-单层空目录",
        "可删除-嵌套空目录/第二层/第三层",
        "应保留-含隐藏文件",
        "应保留-含NFO",
        "应保留-含字幕",
        "应保留-含普通文件/可删除的空子目录",
        "应保留-含隐藏目录/.hidden",
        "应保留-含回收站/#recycle",
    ]:
        (root / relative).mkdir(parents=True)
    for relative, content in [
        ("应保留-含隐藏文件/.keep", "hidden file\n"),
        ("应保留-含NFO/tvshow.nfo", "<tvshow><title>测试</title></tvshow>\n"),
        ("应保留-含字幕/episode.zh.srt", "1\n00:00:01,000 --> 00:00:02,000\n测试\n"),
        ("应保留-含普通文件/说明.txt", "该目录不能删除。\n"),
    ]:
        (root / relative).write_text(content, encoding="utf-8")


def validate_workspace(path):
    path = Path(path).expanduser().absolute()
    workspace = path.resolve(strict=True)
    base = Path("/tmp/opencode").resolve(strict=True)
    if path.is_symlink() or workspace.parent != base or not workspace.name.startswith("azu-webdav-"):
        raise ValueError("只允许重置 /tmp/opencode/azu-webdav-* 测试工作目录")
    info_path = workspace / "server.json"
    if info_path.is_symlink():
        raise ValueError("server.json 不能是符号链接")
    info = json.loads(info_path.read_text(encoding="utf-8"))
    if not isinstance(info, dict) or info.get("workspace") != str(workspace):
        raise ValueError("server.json 中的 workspace 与指定目录不一致")
    root = workspace / "share"
    if root.is_symlink() or (root.exists() and not root.is_dir()):
        raise ValueError("share 必须是普通目录，不能是符号链接")
    return workspace


def reset_workspace(path):
    workspace = validate_workspace(path)
    root = workspace / "share"
    if root.exists():
        shutil.rmtree(root)
    create_fixture(root)
    return root


def main():
    parser = argparse.ArgumentParser(description="清空本地 WebDAV share 目录并恢复初始测试数据")
    parser.add_argument("workspace", type=Path, help="启动服务时输出的 workspace 路径，不是 share 路径")
    parser.add_argument("--yes", action="store_true", help="跳过删除确认")
    args = parser.parse_args()
    try:
        workspace = validate_workspace(args.workspace)
        if not args.yes:
            answer = input(f"将删除 {workspace / 'share'} 中的全部内容，输入 yes 确认：")
            if answer.strip() != "yes":
                print("已取消重置。")
                return
        root = reset_workspace(workspace)
    except (OSError, ValueError, EOFError) as error:
        parser.exit(1, f"重置失败：{error}\n")
    print(f"已恢复测试目录：{root}")


if __name__ == "__main__":
    main()
