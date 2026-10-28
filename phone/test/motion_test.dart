import 'package:documind_phone/theme/motion.dart';
import 'package:documind_phone/widgets/skeleton.dart';
import 'package:documind_phone/screens/server_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('last cascade item becomes fully visible and stops moving', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CascadeIn(index: 12, child: Text('Document'))),
    );
    await tester.pumpAndSettle();
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(CascadeIn),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 1);
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(CascadeIn),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.getTranslation().y, 0);
  });

  testWidgets('reduced motion disables shimmer ticker and cascade', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Shimmer(child: CascadeIn(index: 12, child: Text('Document'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('reduced motion skips geometric transition immediately', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GeometricTransition(onFinished: () => finished = true),
        ),
      ),
    );
    expect(finished, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
