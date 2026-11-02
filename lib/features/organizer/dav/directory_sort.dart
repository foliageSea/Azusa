import 'dart:io';

import '../../../core/settings/directory_sort.dart';
import 'webdav.dart';

List<DavEntry> sortDirectoryEntries(
  List<DavEntry> entries,
  DirectorySort order,
) {
  DateTime? modified(DavEntry entry) {
    final value = entry.modified;
    if (value == null) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    try {
      return HttpDate.parse(value);
    } on HttpException {
      return null;
    }
  }

  final dates = {
    if (order == DirectorySort.modifiedAscending ||
        order == DirectorySort.modifiedDescending)
      for (final entry in entries) entry.path: modified(entry),
  };
  int compareKnown<T extends Comparable<T>>(T? a, T? b, bool descending) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  return [...entries]..sort((a, b) {
    if (a.directory != b.directory) return a.directory ? -1 : 1;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final comparison = switch (order) {
      DirectorySort.nameAscending => name,
      DirectorySort.nameDescending => -name,
      DirectorySort.modifiedAscending => compareKnown(
        dates[a.path],
        dates[b.path],
        false,
      ),
      DirectorySort.modifiedDescending => compareKnown(
        dates[a.path],
        dates[b.path],
        true,
      ),
      DirectorySort.sizeAscending => compareKnown(a.size, b.size, false),
      DirectorySort.sizeDescending => compareKnown(a.size, b.size, true),
    };
    if (comparison != 0) return comparison;
    if (name != 0) return name;
    return a.path.compareTo(b.path);
  });
}
