import 'package:documind_phone/screens/chat_screen.dart';
import 'package:documind_phone/screens/home_shell.dart';
import 'package:documind_phone/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens_test.dart' show harness;
import 'support/fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets(
    'chat back stays above keyboard at 360dp and returns to previous tab',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final state = AppState.withClient(FakeApiClient());
      await tester.pumpWidget(harness(const HomeShell(), state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(TextField),
      );
      final focus = tester.widget<TextField>(input).focusNode!;
      await tester.tap(input);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final back = find.byTooltip('Retour');
      expect(back.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(back).dy, lessThan(780 - 300));
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(
        find.text('Rechercher par nom, contenu, émetteur…'),
        findsOneWidget,
      );
      expect(focus.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('chat dismisses keyboard on outside tap and drag', (
    tester,
  ) async {
    final state = AppState.withClient(FakeApiClient());
    await tester.pumpWidget(harness(const HomeShell(), state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.byType(TextField),
    );
    final focus = tester.widget<TextField>(input).focusNode!;
    await tester.tap(input);
    await tester.pump();
    await tester.tap(find.text('Posez une question sur vos documents'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tap(input);
    await tester.pump();
    final list = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
