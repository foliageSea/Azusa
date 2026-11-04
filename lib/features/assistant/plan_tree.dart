import '../organizer/ai/folder_layout.dart';
import '../organizer/dav/dav_paths.dart';
import '../organizer/dav/webdav.dart';
import '../organizer/rename_plan.dart';

sealed class PlanTreeNode {
  const PlanTreeNode(this.path, this.name);

  final String path;
  final String name;
}

class PlanTreeDirectory extends PlanTreeNode {
  PlanTreeDirectory(super.path, super.name);

  final directories = <String, PlanTreeDirectory>{};
  final files = <PlanTreeFile>[];

  Iterable<PlanTreeNode> get children sync* {
    final folders = directories.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    yield* folders;
    yield* files;
  }
}

class PlanTreeFile extends PlanTreeNode {
  PlanTreeFile(this.index, this.item) : super(item.target, item.targetName);

  final int index;
  final RenameItem item;
}

class PlanTree {
  PlanTree._(this.root, this.newDirectories);

  factory PlanTree.build(
    String directory,
    List<RenameItem> plan,
    List<DavEntry> entries,
  ) {
    // Keep every destination inside the tree, even for older plans without a scope.
    var rootPath = directory;
    for (final item in plan) {
      final parent = item.targetDirectory ?? item.parent;
      while (!parent.startsWith(rootPath) && rootPath != '/') {
        rootPath = rootPath.substring(0, rootPath.length - 1);
        rootPath = rootPath.substring(0, rootPath.lastIndexOf('/') + 1);
      }
    }
    final root = PlanTreeDirectory(rootPath, _name(rootPath));
    for (final (index, item) in plan.indexed) {
      var node = root;
      final parent = item.targetDirectory ?? item.parent;
      for (final segment in parent.substring(rootPath.length).split('/')) {
        if (segment.isEmpty) continue;
        final path = '${node.path}$segment/';
        node = node.directories.putIfAbsent(
          path,
          () => PlanTreeDirectory(path, Uri.decodeComponent(segment)),
        );
      }
      node.files.add(PlanTreeFile(index, item));
    }

    final existing = <String>{rootPath};
    void addAncestors(String path) {
      while (path.startsWith(rootPath) && path.length > rootPath.length) {
        existing.add(path);
        path = path.substring(0, path.length - 1);
        path = path.substring(0, path.lastIndexOf('/') + 1);
      }
    }

    for (final entry in entries) {
      addAncestors(
        entry.directory
            ? entry.path
            : entry.path.substring(0, entry.path.lastIndexOf('/') + 1),
      );
    }
    for (final item in plan) {
      addAncestors(item.parent);
    }
    final newDirectories = plannedFolders(plan).toSet()..removeAll(existing);
    return PlanTree._(root, newDirectories);
  }

  final PlanTreeDirectory root;

  /// Selected destinations not already known to exist in the scanned entries.
  final Set<String> newDirectories;

  static String _name(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? '/' : displayDavPath(segments.last);
  }
}
