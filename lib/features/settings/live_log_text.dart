import 'package:forui/forui.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/logging/live_log_store.dart';

class LiveLogText extends StatelessWidget {
  const LiveLogText({required this.entry, this.compact = false, super.key});

  final LiveLogEntry entry;
  final bool compact;

  static final _header = RegExp(
    r'^([A-Z]+)(?=[:\s]|$)'
    r'((?:: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?:)?'
    r'(?: \[[^\]\r\n]*\]){0,2} ?)',
  );

  static final _stackFrame = RegExp(r'^(#\d+\s|<asynchronous suspension>)');

  static String withoutStack(String text) {
    final lines = text.split('\n');
    final kept = lines.where((line) => !_stackFrame.hasMatch(line)).toList();
    if (kept.length == lines.length) return text;
    return kept.join('\n').trimRight();
  }

  Color _levelColor(FColors colors) {
    final dark = colors.brightness == Brightness.dark;
    if (entry.level >= Level.SHOUT) {
      return dark ? const Color(0xffd8b4fe) : const Color(0xff7e22ce);
    }
    if (entry.level >= Level.SEVERE) {
      return dark ? const Color(0xfffca5a5) : const Color(0xffb91c1c);
    }
    if (entry.level >= Level.WARNING) {
      return dark ? const Color(0xfffcd34d) : const Color(0xff92400e);
    }
    if (entry.level >= Level.INFO) {
      return dark ? const Color(0xff93c5fd) : const Color(0xff1d4ed8);
    }
    if (entry.level >= Level.CONFIG) {
      return dark ? const Color(0xff5eead4) : const Color(0xff0f766e);
    }
    return colors.mutedForeground;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = withoutStack(entry.text);
    final header = _header.firstMatch(text);
    final hasHeader = header != null && header.group(1) == entry.level.name;
    final span = TextSpan(
      children: hasHeader
          ? [
              TextSpan(
                text: header.group(1),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: header.group(2),
                style: TextStyle(color: theme.colors.mutedForeground),
              ),
              TextSpan(text: text.substring(header.end)),
            ]
          : [TextSpan(text: text)],
    );
    final style =
        (compact ? theme.typography.body.xs : theme.typography.body.sm)
            .copyWith(
              fontFamily: 'monospace',
              color: _levelColor(theme.colors),
            );
    return compact
        ? Text.rich(span, style: style)
        : SelectableText.rich(span, style: style);
  }
}
