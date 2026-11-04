import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import 'dav_paths.dart';

class DirectoryBreadcrumb extends StatelessWidget {
  const DirectoryBreadcrumb({
    required this.directory,
    required this.root,
    required this.onOpen,
    this.locked = false,
    this.currentKey,
    super.key,
  });

  final String directory;
  final String root;
  final ValueChanged<String> onOpen;
  final bool locked;
  final Key? currentKey;

  @override
  Widget build(BuildContext context) {
    final crumbs = <(String, String)>[];
    if (directory.startsWith(root)) {
      crumbs.add((context.l10n.rootDirectory, root));
      var path = root;
      for (final segment
          in directory
              .substring(root.length)
              .split('/')
              .where((s) => s.isNotEmpty)) {
        path = '$path$segment/';
        crumbs.add((Uri.decodeComponent(segment), path));
      }
    } else if (directory.isNotEmpty) {
      crumbs.add((displayDavPath(directory), directory));
    }

    return FBreadcrumb(
      children: [
        if (crumbs.length > 1)
          FBreadcrumbItem(
            onPress: locked ? null : () => onOpen(root),
            child: Text(crumbs.first.$1),
          ),
        if (crumbs.length > 2)
          FBreadcrumbItem.collapsed(
            key: const ValueKey('directory-ancestors'),
            semanticsLabel: context.l10n.parentDirectories,
            maxHeight: 320,
            menu: [
              FItemGroup(
                children: [
                  for (final (label, path)
                      in crumbs.skip(1).take(crumbs.length - 2))
                    FItem(
                      key: ValueKey('directory-ancestor-$path'),
                      title: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPress: locked ? null : () => onOpen(path),
                    ),
                ],
              ),
            ],
          ),
        if (crumbs.isNotEmpty)
          Expanded(
            child: FTooltip(
              tipBuilder: (_, _) => Text(displayDavPath(directory)),
              child: FBreadcrumbItem(
                current: true,
                child: Text(
                  crumbs.last.$1,
                  key: currentKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
