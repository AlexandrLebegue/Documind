import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/transfer_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/common.dart';
import 'scanner_flow.dart';
import 'transfer_sheet.dart';

enum _DocumentSource { scanner, file, gallery }

Future<bool?> showAddDocumentSheet(BuildContext context) async {
  // Only return the choice from the transient sheet. All asynchronous native
  // work belongs to the caller, which survives the sheet's reverse animation.
  final source = await showModalBottomSheet<_DocumentSource>(
    context: context,
    sheetAnimationStyle: Motion.reduced(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Motion.normal,
            reverseDuration: Motion.fast,
          ),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddDocumentSheet(),
  );
  if (source == null || !context.mounted) return false;
  try {
    switch (source) {
      case _DocumentSource.scanner:
        await startScannerFlow(context);
      case _DocumentSource.file:
        await _pickFiles(context);
      case _DocumentSource.gallery:
        await _pickGallery(context);
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      showAppSnack(
        context,
        'Import impossible : ${shortErrorMessage(error)}',
        error: true,
      );
    }
    return false;
  }
}

class AddDocumentSheet extends StatelessWidget {
  const AddDocumentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
          const SizedBox(height: 18),
          const Text(
            'Ajouter un document',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choisissez la source du document à analyser.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _SourceTile(
            icon: Icons.document_scanner_outlined,
            title: 'Scanner un document',
            subtitle:
                'Caméra, détection des bords, recadrage et plusieurs pages en un seul PDF.',
            highlighted: true,
            onTap: () => Navigator.of(context).pop(_DocumentSource.scanner),
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.upload_file_outlined,
            title: 'Choisir un fichier',
            subtitle: 'PDF, JPG, JPEG, PNG ou TXT (max 50 Mo).',
            onTap: () => Navigator.of(context).pop(_DocumentSource.file),
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Depuis la galerie',
            subtitle: 'Sélectionnez une ou plusieurs images à envoyer.',
            onTap: () => Navigator.of(context).pop(_DocumentSource.gallery),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: AppColors.faint),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'L’analyse OCR et IA démarre automatiquement sur le serveur.',
                  style: TextStyle(fontSize: 11, color: AppColors.faint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _pickFiles(BuildContext context) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'txt'],
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty || !context.mounted) return;
  await uploadInputsAndTrack(context, [
    for (final file in result.files)
      UploadInput(file.name, () => materializePickedFile(file)),
  ]);
}

// Native pickers normally cache a local path. Keep byte/stream fallbacks for
// providers that return no usable path; never discard a selected file silently.
Future<File> materializePickedFile(PlatformFile picked) async {
  final path = picked.path;
  if (path != null && !path.startsWith('content:')) {
    final file = path.startsWith('file:')
        ? File.fromUri(Uri.parse(path))
        : File(path);
    if (await file.exists()) return file;
  }
  if (picked.bytes == null && picked.readStream == null) {
    throw Exception(
      'Fichier inaccessible. Copiez-le sur le téléphone puis réessayez.',
    );
  }
  final directory = await getTemporaryDirectory();
  final imports = await Directory(
    '${directory.path}/documind_imports',
  ).create(recursive: true);
  final cache = await imports.createTemp('upload_');
  final name = picked.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${cache.path}/$name');
  if (picked.bytes != null) {
    await file.writeAsBytes(picked.bytes!, flush: true);
  } else {
    await picked.readStream!.pipe(file.openWrite());
  }
  return file;
}

Future<void> _pickGallery(BuildContext context) async {
  final images = await ImagePicker().pickMultiImage(
    imageQuality: 90,
    maxWidth: 2400,
  );
  if (images.isEmpty || !context.mounted) return;
  await uploadAndTrack(context, images.map((x) => File(x.path)).toList());
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted
          ? AppColors.accent.withValues(alpha: 0.06)
          : AppColors.beige50,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: highlighted
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.beige300,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: highlighted ? AppColors.accent : AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 23,
                  color: highlighted ? Colors.white : AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts transfers in application state so closing the tracker never cancels
/// an upload or loses its retry action.
Future<void> uploadAndTrack(
  BuildContext context,
  List<File> files, {
  String source = 'phone',
}) => uploadInputsAndTrack(context, [
  for (final file in files)
    UploadInput(file.uri.pathSegments.last, () async => file),
], source: source);

Future<void> uploadInputsAndTrack(
  BuildContext context,
  List<UploadInput> files, {
  String source = 'phone',
}) async {
  final app = context.read<AppState>();
  final transfers = app.transfers;
  if (transfers == null) {
    throw Exception('Connectez-vous à un serveur avant l’envoi.');
  }
  if (files.isEmpty) return;
  transfers.add(files, source: source);
  await showTransferSheet(context);
}
