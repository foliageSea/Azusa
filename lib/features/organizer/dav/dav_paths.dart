String canonicalDavPath(String path) {
  if (!path.startsWith('/') || path.contains('?') || path.contains('#')) {
    throw const FormatException('WebDAV 路径必须为绝对路径');
  }
  return path
      .split('/')
      .map((part) {
        final decoded = Uri.decodeComponent(part);
        if (decoded == '.' ||
            decoded == '..' ||
            decoded.contains(RegExp(r'[/\\\x00-\x1F]'))) {
          throw const FormatException('WebDAV 路径包含不安全的字符');
        }
        return Uri.encodeComponent(decoded);
      })
      .join('/');
}

String displayDavPath(String path) => Uri.decodeComponent(path);

const _fileNameReplacements = {
  '/': '／',
  '\\': '＼',
  ':': '：',
  '*': '＊',
  '?': '？',
  '"': '＂',
  '<': '＜',
  '>': '＞',
  '|': '｜',
};

String? fileNameError(String name) {
  if (name.trim().isEmpty) return '文件名无效：文件名不能为空';
  if (name == '.' || name == '..') return '文件名无效：不能使用“$name”';
  if (name.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
    return '文件名无效：不能包含控制字符';
  }
  for (final entry in _fileNameReplacements.entries) {
    if (name.contains(entry.key)) {
      return '文件名无效：不能包含“${entry.key}”，请替换为“${entry.value}”或“-”';
    }
  }
  if (name.endsWith('.') || name.endsWith(' ')) {
    return '文件名无效：不能以空格或句点结尾';
  }
  return null;
}

bool validFileName(String name) => fileNameError(name) == null;

String sanitizeSuggestedFileName(String name, {required String originalName}) {
  var sanitized = name.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  for (final entry in _fileNameReplacements.entries) {
    sanitized = sanitized.replaceAll(entry.key, entry.value);
  }
  sanitized = sanitized.replaceFirst(RegExp(r'[. ]+$'), '');
  final extensionIndex = originalName.lastIndexOf('.');
  if (extensionIndex > 0 && extensionIndex < originalName.length - 1) {
    final extension = originalName.substring(extensionIndex);
    final suggestedExtensionIndex = sanitized.lastIndexOf('.');
    if (suggestedExtensionIndex > 0) {
      sanitized = sanitized.substring(0, suggestedExtensionIndex);
    }
    sanitized = sanitized.replaceFirst(RegExp(r'[. ]+$'), '');
    if (sanitized.isEmpty) {
      sanitized = originalName.substring(0, extensionIndex);
    }
    return '$sanitized$extension';
  }
  return sanitized.isEmpty ? originalName : sanitized;
}

String childDavPath(String parent, String name, {bool directory = false}) {
  if (!validFileName(name)) throw const FormatException('文件名包含非法字符');
  return '${parent.endsWith('/') ? parent : '$parent/'}${Uri.encodeComponent(name)}${directory ? '/' : ''}';
}
