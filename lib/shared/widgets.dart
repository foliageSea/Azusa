import 'responsive_button.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_exception.dart';
import 'localization.dart';

/// The width below which the application switches to its mobile layout.
const mobileBreakpoint = 600.0;

/// Whether the application is currently laid out for mobile.
bool isMobileLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < mobileBreakpoint;

class PageContent extends StatelessWidget {
  const PageContent({
    required this.children,
    this.fill = false,
    this.topPadding,
    super.key,
  });

  static const maxWidth = 1440.0;

  static double paddingOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < mobileBreakpoint
        ? 16.0
        : width < 1024
        ? 24.0
        : 32.0;
  }

  final List<Widget> children;
  final bool fill;
  final double? topPadding;
  @override
  Widget build(BuildContext context) {
    final padding = paddingOf(context);
    return ColoredBox(
      color: context.theme.colors.background,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: fill
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      topPadding ?? padding,
                      padding,
                      padding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      topPadding ?? padding,
                      padding,
                      padding,
                    ),
                    children: children,
                  ),
          ),
        ),
      ),
    );
  }
}

class Surface extends StatelessWidget {
  const Surface({
    required this.child,
    this.padding = 24,
    this.expand = false,
    super.key,
  });
  final Widget child;
  final double padding;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final card = FCard(
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
    return expand ? SizedBox.expand(child: card) : card;
  }
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({required this.children, this.minWidth = 280, super.key});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + 16) / (minWidth + 16)).floor().clamp(
        1,
        children.length.clamp(1, 4),
      );
      final width = (box.maxWidth - (columns - 1) * 16) / columns;
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        ),
      );
    },
  );
}

String failureMessage(BuildContext context, Object error) {
  final l = context.l10n;
  return switch (error) {
    AppException(kind: FailureKind.storage) => l.storageError,
    AppException(kind: FailureKind.timeout) => l.timeoutError,
    AppException(kind: FailureKind.server) => l.serverError,
    AppException(kind: FailureKind.invalidData) => l.invalidDataError,
    AppException(kind: FailureKind.cancelled) => l.cancelledError,
    _ => l.networkError,
  };
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.error, {this.onRetry, super.key});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FAlert(
        variant: .destructive,
        title: Text(context.l10n.errorTitle),
        subtitle: Text(failureMessage(context, error)),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        FButton(
          builder: responsiveButtonContent,
          variant: .outline,
          onPress: onRetry,
          child: Text(context.l10n.retry),
        ),
      ],
    ],
  );
}

class LoadingNotice extends StatelessWidget {
  const LoadingNotice({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const FCircularProgress(),
        const SizedBox(height: 16),
        Text(context.l10n.loading),
      ],
    ),
  );
}

class EmptyNotice extends StatelessWidget {
  const EmptyNotice(this.message, {this.child, super.key});
  final String message;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      children: [
        Icon(
          FLucideIcons.inbox,
          size: 32,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        if (child != null) ...[const SizedBox(height: 16), child!],
      ],
    ),
  );
}

enum NoticeType { success, error, warning, info }

void notifyUser(
  BuildContext context,
  String message, {
  NoticeType type = NoticeType.info,
}) {
  final dark = context.theme.colors.background.computeLuminance() < .5;
  final (icon, color, label) = switch (type) {
    NoticeType.success => (
      FLucideIcons.circleCheck,
      dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      '成功',
    ),
    NoticeType.error => (
      FLucideIcons.circleX,
      context.theme.colors.destructive,
      '错误',
    ),
    NoticeType.warning => (
      FLucideIcons.triangleAlert,
      dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      '警告',
    ),
    NoticeType.info => (
      FLucideIcons.info,
      dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      '信息',
    ),
  };
  showFToast(
    context: context,
    variant: type == NoticeType.error ? .destructive : .primary,
    icon: Icon(icon, color: color, semanticLabel: label),
    title: Text(message),
    alignment: FToastAlignment.topCenter,
  );
}

Future<void> openDocumentation(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ) &&
        context.mounted) {
      notifyUser(context, context.l10n.linkError, type: NoticeType.error);
    }
  } catch (_) {
    if (context.mounted) {
      notifyUser(context, context.l10n.linkError, type: NoticeType.error);
    }
  }
}

Future<void> copySource(BuildContext context, String source) async {
  await Clipboard.setData(ClipboardData(text: source));
  if (context.mounted) {
    notifyUser(context, context.l10n.copied, type: NoticeType.success);
  }
}

class EscapeDismiss extends StatelessWidget {
  const EscapeDismiss({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    },
    child: child,
  );
}
