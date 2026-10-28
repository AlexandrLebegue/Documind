// Optional golden captures with synthetic fixtures only. No live documents.
// MOBILE_CAPTURES_DIR=/tmp/mobile-captures flutter test test/captures_test.dart --update-goldens
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documind_phone/screens/home_shell.dart';
import 'package:documind_phone/screens/document_detail_screen.dart';
import 'package:documind_phone/theme/app_theme.dart';
import 'package:documind_phone/screens/server_setup_screen.dart';
import 'package:documind_phone/screens/add_document_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens_test.dart' show harness;

void main() {
  final output = Platform.environment['MOBILE_CAPTURES_DIR'];
  testWidgets('capture main screens at 390 x 844 with synthetic data', (
    tester,
  ) async {
    await initializeDateFormatting('fr_FR');
    final fontPath = Platform.environment['MOBILE_CAPTURES_FONT'];
    if (fontPath != null) {
      for (final family in ['Roboto', 'Ahem', 'sans-serif']) {
        final font = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          );
        await font.load();
      }
      final iconsPath = Platform.environment['MOBILE_CAPTURES_ICONS'];
      if (iconsPath != null) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(iconsPath).readAsBytesSync()),
            ),
          );
        await icons.load();
      }
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const captureKey = ValueKey('capture');
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(Uri.file('$output/$name.png')),
      );
    }

    // Give standalone component styles an explicit family in the test engine.
    final base = AppTheme.light();
    ButtonStyle? fonts(ButtonStyle? style) => style?.copyWith(
      textStyle: WidgetStatePropertyAll(
        style.textStyle?.resolve({})?.copyWith(fontFamily: 'Roboto'),
      ),
    );
    final captureTheme = base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'Roboto',
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: fonts(base.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: fonts(base.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: fonts(base.textButtonTheme.style),
      ),
    );
    Widget frame(Widget child) => RepaintBoundary(
      key: captureKey,
      child: harness(child, theme: captureTheme),
    );
    await tester.pumpWidget(frame(const ServerSetupScreen()));
    await capture('01-serveur');
    await tester.pumpWidget(frame(const HomeShell()));
    await capture('02-accueil');
    for (final entry in {
      'Documents': '03-documents',
      'Chat': '04-chat',
      'Alertes': '05-alertes',
      'Plus': '06-plus',
    }.entries) {
      await tester.tap(find.text(entry.key));
      await capture(entry.value);
    }
    await tester.tap(find.text('Réglages'));
    await capture('07-reglages');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(frame(const Scaffold(body: AddDocumentSheet())));
    await capture('08-ajout');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      frame(const DocumentDetailScreen(documentId: 'doc-1')),
    );
    await capture('09-fiche');
    await tester.pumpWidget(const SizedBox());
  }, skip: output == null);
}
