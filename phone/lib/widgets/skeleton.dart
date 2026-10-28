import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (_controller.value * 2 - 0.5);
            return LinearGradient(
              colors: const [
                AppColors.beige200,
                AppColors.beige50,
                AppColors.beige200,
              ],
              stops: const [0.25, 0.5, 0.75],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 12,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.beige200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 5,
    this.height = 86,
    this.grid = false,
  });

  final int count;
  final double height;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return Shimmer(
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              SkeletonBox(height: height),
              if (i != count - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      );
    }
    return Shimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        itemCount: count,
        itemBuilder: (context, index) => SkeletonBox(height: height),
      ),
    );
  }
}
