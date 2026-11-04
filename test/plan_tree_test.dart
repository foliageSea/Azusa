import 'package:azusa/features/assistant/plan_tree.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/dav/';
  const show = '/dav/Show%20%282024%29/';
  const season = '${show}Season%2001/';

  RenameItem episode(String name, {bool enabled = true}) => RenameItem(
    source: '$root$name.mkv',
    targetName: '$name - renamed.mkv',
    targetDirectory: season,
    scope: root,
    enabled: enabled,
  );

  test('目标路径构建多层树，同目录只出现一次，保留方案索引', () {
    final tree = PlanTree.build(root, [episode('b'), episode('a')], []);
    final title = tree.root.directories.values.single;
    final folder = title.directories.values.single;
    expect(title.name, 'Show (2024)');
    expect(folder.name, 'Season 01');
    expect(folder.files.map((file) => file.index), [0, 1]);
    expect(folder.files.map((file) => file.name), [
      'b - renamed.mkv',
      'a - renamed.mkv',
    ]);
    expect(tree.newDirectories, {show, season});
  });

  test('取消勾选保留预览，但不计入新建目录', () {
    final tree = PlanTree.build(root, [episode('a', enabled: false)], []);
    expect(tree.root.directories, hasLength(1));
    expect(tree.newDirectories, isEmpty);
  });

  test('已存在目录和由源文件推断的父目录不标为新建', () {
    final existing = PlanTree.build(
      root,
      [episode('a')],
      [DavEntry(show, true)],
    );
    expect(existing.newDirectories, {season});

    final inferred = PlanTree.build(root, [
      episode('a'),
      const RenameItem(source: '${season}old.mkv', targetName: 'old.mkv'),
    ], []);
    expect(inferred.newDirectories, isEmpty);
  });

  test('未移动文件在原目录，根目录文件不额外包一层', () {
    final tree = PlanTree.build(root, const [
      RenameItem(source: '/dav/root.mkv', targetName: 'renamed.mkv'),
      RenameItem(source: '/dav/Original/file.mkv', targetName: 'file.mkv'),
    ], []);
    expect(tree.root.files.single.path, '/dav/renamed.mkv');
    expect(tree.root.directories.values.single.name, 'Original');
    expect(tree.newDirectories, isEmpty);
  });

  test('旧方案的目标在所选目录之外时使用公共祖先', () {
    final tree = PlanTree.build('/dav/Show/', const [
      RenameItem(
        source: '/dav/Show/old.mkv',
        targetName: 'new.mkv',
        targetDirectory: '/dav/',
      ),
    ], []);
    expect(tree.root.path, '/dav/');
    expect(tree.root.files.single.path, '/dav/new.mkv');
  });
}
