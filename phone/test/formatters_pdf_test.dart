import 'dart:io';

import 'package:documind_phone/screens/scanner_flow.dart';
import 'package:documind_phone/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  group('formatters', () {
    test('formats dates and money in French', () {
      expect(formatDate('2026-10-28'), '28 oct. 2026');
      expect(formatLongDate('2026-10-28'), '28 octobre 2026');
      expect(formatShortDateTime('2026-10-28T14:05:00'), '28/10/26 14:05');
      expect(formatMoney(1234.5), contains('1'));
      expect(formatMoney(null), '');
      expect(formatFileSize(900), '900 o');
      expect(formatFileSize(2048), '2.0 Ko');
      expect(formatFileSize(2 * 1024 * 1024), '2.0 Mo');
    });

    test('resolves doc types and expiry rules', () {
      expect(docTypeLabel('facture'), 'Facture');
      expect(docTypeLabel('cni'), 'Identité');
      expect(docTypeLabel('inconnu'), 'Autre');
      expect(isExpirableType('identite'), isTrue);
      expect(isExpirableType('facture'), isFalse);
    });

    test('relative time handles today and yesterday', () {
      final now = DateTime.now();
      expect(formatRelativeDate(now), startsWith('Aujourd’hui à '));
      expect(formatRelativeDate(now.subtract(const Duration(days: 1))), 'Hier');
      expect(formatRelativeDate(null), '—');
    });

    test('daysUntil is calendar based', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final value =
          '${tomorrow.year.toString().padLeft(4, '0')}-'
          '${tomorrow.month.toString().padLeft(2, '0')}-'
          '${tomorrow.day.toString().padLeft(2, '0')}';
      expect(daysUntil(value), 1);
      expect(daysUntil(null), 0);
    });
  });

  test('buildPdfFromPages produces a PDF from a test image', () async {
    final directory = await Directory.systemTemp.createTemp('documind_pdf_');
    addTearDown(() => directory.delete(recursive: true));
    final image = img.Image(width: 300, height: 400);
    img.fill(image, color: img.ColorRgb8(120, 160, 210));
    final source = File('${directory.path}/page.png')
      ..writeAsBytesSync(img.encodePng(image));

    final progress = <double>[];
    final pdf = await buildPdfFromPages(
      [source.path],
      onProgress: progress.add,
      outputDirectory: directory,
    );

    expect(await pdf.exists(), isTrue);
    expect(await pdf.length(), greaterThan(500));
    final bytes = await pdf.readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(progress, isNotEmpty);
    expect(progress.last, closeTo(1, 0.001));
  });
}
