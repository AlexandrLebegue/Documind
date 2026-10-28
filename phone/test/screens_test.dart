import 'package:documind_phone/screens/home_shell.dart';
import 'package:documind_phone/state/app_state.dart';
import 'package:documind_phone/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Widget harness(Widget child, {AppState? state}) {
  return ChangeNotifierProvider<AppState>.value(
    value: state ?? AppState.withClient(FakeApiClient()),
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2532);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('dashboard shows stats and recent documents', (tester) async {
    await tester.pumpWidget(harness(const HomeShell()));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Facture EDF octobre'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bottom navigation reaches documents, chat and alerts', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Rechercher par nom, contenu, émetteur…'), findsOneWidget);
    expect(find.text('Facture EDF octobre'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Posez une question sur vos documents'), findsOneWidget);

    await tester.tap(find.text('Alertes'));
    await tester.pumpAndSettle();
    expect(find.text('Tout est en ordre'), findsOneWidget);
    expect(find.text('Expirés'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all tabs lay out at 360 dp without overflow', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(1080, 1920);
    view.devicePixelRatio = 3;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(harness(const HomeShell()));
    await tester.pumpAndSettle();
    for (final tab in ['Documents', 'Chat', 'Alertes', 'Plus']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('more tab opens settings loaded from the server', (tester) async {
    await tester.pumpWidget(harness(const HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plus'));
    await tester.pumpAndSettle();
    expect(find.text('Démarches'), findsOneWidget);
    expect(find.text('Journaux'), findsOneWidget);

    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.text('Fournisseur'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Synchronisation NAS du serveur'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Synchronisation NAS du serveur'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Version serveur'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version serveur'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
