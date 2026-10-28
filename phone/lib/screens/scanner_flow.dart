import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'add_document_sheet.dart';

Future<void> startScannerFlow(BuildContext context) async {
  List<String>? pages;
  try {
    pages = await CunningDocumentScanner.getPictures(
      noOfPages: 20,
      androidScannerMode: AndroidScannerMode.full,
      scannerSource: ScannerSource.camera,
    );
  } on CunningDocumentScannerException catch (error) {
    if (!context.mounted) return;
    final permission = error.code == 'permission_denied';
    showAppSnack(
      context,
      permission
          ? 'Accès à la caméra refusé. Autorisez la caméra dans les réglages du téléphone.'
          : 'Le scanner n’a pas pu démarrer : ${error.message}',
      error: true,
    );
    return;
  } catch (error) {
    if (!context.mounted) return;
    showAppSnack(context, 'Scanner indisponible : $error', error: true);
    return;
  }

  if (pages == null || pages.isEmpty) return;
  if (!context.mounted) return;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ScanReviewSheet(pages: pages!),
  );
  if (confirmed != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PdfBuildingDialog(progress: progress),
  );

  try {
    final pdfFile = await buildPdfFromPages(
      pages,
      onProgress: (value) => progress.value = value,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await uploadAndTrack(context, [pdfFile], source: 'phone_scan');
    try {
      await CunningDocumentScanner.cleanCache();
    } catch (_) {
      // Cache cleanup is best effort.
    }
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    showAppSnack(context, 'Création du PDF impossible : $error', error: true);
  }
}

/// Compresses each page (longest side ≤ 2000 px, JPEG 85 %) and assembles a
/// single A4 PDF on the phone before upload.
Future<File> buildPdfFromPages(
  List<String> paths, {
  ValueChanged<double>? onProgress,
  Directory? outputDirectory,
}) async {
  final directory = outputDirectory ?? await getTemporaryDirectory();
  final output = Directory('${directory.path}/documind_phone');
  if (!await output.exists()) await output.create(recursive: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;

  final document = pw.Document();
  for (var i = 0; i < paths.length; i++) {
    final pageFile = await _preparePage(
      paths[i],
      '${output.path}/page_${stamp}_$i.jpg',
    );
    if (pageFile == null) {
      throw StateError(
        'La page ${i + 1} du scan est illisible. Recommencez le scan.',
      );
    }
    final jpeg = await pageFile.readAsBytes();
    if (jpeg.isEmpty) {
      throw StateError(
        'La page ${i + 1} du scan est vide. Recommencez le scan.',
      );
    }
    final image = pw.MemoryImage(jpeg);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        build: (context) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    onProgress?.call((i + 1) / paths.length);
  }
  if (document.document.pdfPageList.pages.isEmpty) {
    throw StateError('Aucune page exploitable dans le scan.');
  }
  final file = File('${output.path}/scan_$stamp.pdf');
  await file.writeAsBytes(await document.save(), flush: true);
  return file;
}

Future<File?> _preparePage(String source, String target) async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source,
        target,
        quality: 85,
        minWidth: 2000,
        minHeight: 2000,
        format: CompressFormat.jpeg,
      );
      if (compressed != null) return File(compressed.path);
    } catch (_) {
      // Fall through to the portable encoder.
    }
  }
  try {
    final bytes = await File(source).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final resized = longest > 2000
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? 2000
                : (oriented.width * 2000 / longest).round(),
            height: oriented.height > oriented.width
                ? 2000
                : (oriented.height * 2000 / longest).round(),
            interpolation: img.Interpolation.average,
          )
        : oriented;
    final jpeg = img.encodeJpg(resized, quality: 85);
    return File(target)..writeAsBytesSync(jpeg, flush: true);
  } catch (_) {
    return null;
  }
}

class _ScanReviewSheet extends StatelessWidget {
  const _ScanReviewSheet({required this.pages});

  final List<String> pages;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.beige300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${pages.length} page${pages.length > 1 ? 's' : ''} scannée${pages.length > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Les pages recadrées seront assemblées en un seul PDF compressé.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(pages[index]),
                  width: 110,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 110,
                    color: AppColors.beige100,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      await CunningDocumentScanner.cleanCache();
                    } catch (_) {}
                    if (context.mounted) Navigator.of(context).pop(false);
                  },
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check, size: 19),
                  label: const Text('Créer le PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdfBuildingDialog extends StatelessWidget {
  const _PdfBuildingDialog({required this.progress});

  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Préparation du PDF',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Compression des pages…',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value == 0 ? null : value,
                  minHeight: 7,
                  backgroundColor: AppColors.beige200,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
