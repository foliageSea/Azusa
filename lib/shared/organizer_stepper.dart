import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'localization.dart';

class OrganizerStepper extends StatelessWidget {
  const OrganizerStepper({
    required this.currentStep,
    required this.onStepSelected,
    this.locked = false,
    super.key,
  });

  final int currentStep;
  final ValueChanged<int> onStepSelected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final labels = [
      context.l10n.nasDirectory,
      context.l10n.organizingRequirements,
      context.l10n.renamePreview,
    ];
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              for (var index = 0; index < 2; index++)
                PositionedDirectional(
                  start: constraints.maxWidth * (index + .5) / 3 + 24,
                  top: 23,
                  width: constraints.maxWidth / 3 - 48,
                  child: Container(
                    height: 1,
                    color: index < currentStep
                        ? theme.colors.primary.withValues(alpha: .35)
                        : theme.colors.border,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: Semantics(
                        selected: index == currentStep,
                        child: FTappable(
                          key: ValueKey('organizer-step-$index'),
                          onPress: !locked && index < currentStep
                              ? () => onStepSelected(index)
                              : null,
                          builder: (context, states, child) => AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: states.contains(FTappableVariant.pressed)
                                ? .65
                                : 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: theme.style.borderRadius.md,
                                border:
                                    states.contains(FTappableVariant.focused)
                                    ? Border.all(color: theme.colors.primary)
                                    : null,
                              ),
                              child: child,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == currentStep
                                        ? theme.colors.primary
                                        : index < currentStep
                                        ? theme.colors.primary.withValues(
                                            alpha: .09,
                                          )
                                        : theme.colors.background,
                                    border: Border.all(
                                      color: index <= currentStep
                                          ? theme.colors.primary.withValues(
                                              alpha: index == currentStep
                                                  ? 1
                                                  : .25,
                                            )
                                          : theme.colors.border,
                                    ),
                                    boxShadow: index == currentStep
                                        ? [
                                            BoxShadow(
                                              color: theme.colors.primary
                                                  .withValues(alpha: .1),
                                              spreadRadius: 4,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: index < currentStep
                                      ? Icon(
                                          FLucideIcons.check,
                                          size: 16,
                                          color: theme.colors.primary,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: theme.typography.body.sm
                                              .copyWith(
                                                color: index == currentStep
                                                    ? theme
                                                          .colors
                                                          .primaryForeground
                                                    : theme
                                                          .colors
                                                          .mutedForeground,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  labels[index],
                                  textAlign: TextAlign.center,
                                  style: theme.typography.body.sm.copyWith(
                                    color: index == currentStep
                                        ? theme.colors.primary
                                        : theme.colors.mutedForeground,
                                    fontWeight: index == currentStep
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
