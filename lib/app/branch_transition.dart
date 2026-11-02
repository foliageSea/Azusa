import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Builds the container that hosts the branch navigators of the shell.
///
/// Every branch stays mounted, like [StatefulShellRoute.indexedStack] does, so
/// page state and scroll offsets survive a switch, while the branch that
/// becomes visible fades and slides in over the one that leaves.
Widget animatedBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) => AnimatedBranchContainer(
  currentIndex: navigationShell.currentIndex,
  children: children,
);

/// Keeps every branch alive and plays a fade through transition when
/// [currentIndex] changes.
///
/// The widget tree below each branch is kept identical across switches, because
/// replacing a wrapper would rebuild the branch subtree and lose the page
/// state that a shell route is supposed to preserve.
class AnimatedBranchContainer extends StatefulWidget {
  const AnimatedBranchContainer({
    required this.currentIndex,
    required this.children,
    this.duration = const Duration(milliseconds: 260),
    super.key,
  });

  /// The index of the branch currently displayed.
  final int currentIndex;

  /// The branch widgets, indexed like the branches of the shell route.
  final List<Widget> children;

  /// The length of the transition between two branches.
  final Duration duration;

  @override
  State<AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addStatusListener(_handleStatus);

  /// The branch that is displayed, which may be the incoming one mid transition.
  late int _index = widget.currentIndex;

  /// The branch fading out, set only while a transition runs.
  int? _leaving;

  /// Direction of travel, positive when moving to a branch further right.
  double _direction = 1;

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(covariant AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.currentIndex == _index) return;
    _direction = widget.currentIndex > _index ? 1 : -1;
    _leaving = _index;
    _index = widget.currentIndex;
    if (_reduceMotion) {
      _leaving = null;
      _controller.value = 1;
    } else if (_controller.isAnimating) {
      // A switch in the middle of a transition continues from the current
      // progress, so that neither branch jumps back to full opacity.
      _controller.forward();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (!status.isCompleted || _leaving == null) return;
    setState(() => _leaving = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var i = 0; i < widget.children.length; i++)
        _Branch(
          active: i == _index,
          leaving: i == _leaving,
          animation: _controller,
          direction: _direction,
          child: widget.children[i],
        ),
    ],
  );
}

class _Branch extends StatelessWidget {
  const _Branch({
    required this.active,
    required this.leaving,
    required this.animation,
    required this.direction,
    required this.child,
  });

  /// The distance the incoming branch travels, in logical pixels.
  static const _distance = 12.0;

  /// The outgoing branch is gone before the incoming one is fully opaque, so
  /// that the two never overlap as a muddy double image.
  static const _fadeIn = Interval(0.3, 1, curve: Curves.easeOut);
  static const _fadeOut = Interval(0, 0.6, curve: Curves.easeIn);

  final bool active;
  final bool leaving;
  final Animation<double> animation;
  final double direction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !active && !leaving,
    child: TickerMode(
      enabled: active || leaving,
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              final t = animation.value;
              final fade = _fadeIn.transform(t);
              return Opacity(
                opacity: active
                    ? fade
                    : leaving
                    ? 1 - _fadeOut.transform(t)
                    : 0,
                child: Transform.translate(
                  offset: active
                      ? Offset(direction * _distance * (1 - fade), 0)
                      : Offset.zero,
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
