import 'package:flutter/material.dart';

/// Shared motion language: 150–300 ms, easeOutCubic, respects reduced motion.
class Motion {
  Motion._();

  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 300);
  static const transition = Duration(milliseconds: 950);

  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}

Route<T> slideFadeRoute<T>(Widget page, {String? name}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name),
    transitionDuration: Motion.normal,
    reverseTransitionDuration: Motion.fast,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (Motion.reduced(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Cascade entrance used by list items.
class CascadeIn extends StatelessWidget {
  const CascadeIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 10,
  });

  final Widget child;
  final int index;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    final delay = Duration(milliseconds: (index.clamp(0, 12) * 25));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.normal + delay,
      curve: Motion.curve,
      builder: (context, value, child) {
        final adjusted = value == 0
            ? 0.0
            : ((value - (delay.inMilliseconds / 1000)).clamp(0.0, 1.0));
        return Opacity(
          opacity: adjusted.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offset * (1 - adjusted)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Soft tactile feedback on tap when the platform supports it.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.985,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            },
      onTap: widget.onTap == null ? null : () {},
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: Motion.fast,
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}
