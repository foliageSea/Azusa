import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

/// A two-row month header keeps date navigation usable at large text scales.
Widget responsiveCalendarHeader(
  BuildContext context,
  FGridCalendarController controller,
  FDateSelectionController<Object?> selection,
  Widget child,
) {
  final locale = FLocalizations.of(context)!;
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat.yMMMM(locale.localeName).format(controller.currentMonth),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FButton.icon(
              variant: .ghost,
              semanticsLabel: locale.calendarPreviousMonthSemanticsLabel,
              onPress: controller.day.hasPrevious
                  ? controller.day.previous
                  : null,
              child: const Icon(FLucideIcons.chevronLeft),
            ),
            FButton.icon(
              variant: .ghost,
              semanticsLabel: locale.calendarNextMonthSemanticsLabel,
              onPress: controller.day.hasNext ? controller.day.next : null,
              child: const Icon(FLucideIcons.chevronRight),
            ),
          ],
        ),
      ],
    ),
  );
}
