import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:documind_phone/main.dart';

void main() {
  testWidgets('affiche l’écran de chargement au démarrage', (tester) async {
    await tester.pumpWidget(const DocuMindApp());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
