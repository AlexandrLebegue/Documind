import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/common.dart';
import 'analysis_screen.dart';
import 'scanner_flow.dart';

Future<bool?> showAddDocumentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
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
    builder: (context) => const AddDocumentSheet(),
  );
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
            onTap: () async {
              Navigator.of(context).pop();
              await startScannerFlow(context);
            },
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.upload_file_outlined,
            title: 'Choisir un fichier',
            subtitle: 'PDF, JPG, JPEG, PNG ou TXT (max 50 Mo).',
            onTap: () async {
              Navigator.of(context).pop();
              await _pickFiles(context);
            },
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Depuis la galerie',
            subtitle: 'Sélectionnez une ou plusieurs images à envoyer.',
            onTap: () async {
              Navigator.of(context).pop();
              await _pickGallery(context);
            },
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

  Future<void> _pickFiles(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;
    if (!context.mounted) return;
    await uploadAndTrack(context, paths.map(File.new).toList());
  }

  Future<void> _pickGallery(BuildContext context) async {
    final images = await ImagePicker().pickMultiImage(
      imageQuality: 90,
      maxWidth: 2400,
    );
    if (images.isEmpty || !context.mounted) return;
    await uploadAndTrack(context, images.map((x) => File(x.path)).toList());
  }
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

/// Uploads a list of files sequentially with a live progress sheet, then
/// opens the analysis tracker for the first created document.
Future<void> uploadAndTrack(
  BuildContext context,
  List<File> files, {
  String source = 'phone',
}) async {
  final api = context.read<AppState>().api;
  if (api == null || files.isEmpty) return;

  final progress = ValueNotifier<double>(0);
  final currentName = ValueNotifier<String>('');
  final state = ValueNotifier<_UploadPhase>(_UploadPhase.uploading);
  final uploaded = <String>[];
  final errors = <String>[];

  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _UploadProgressSheet(
      progress: progress,
      currentName: currentName,
      state: state,
      fileCount: files.length,
    ),
  );

  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    currentName.value = file.path.split(Platform.pathSeparator).last;
    progress.value = 0;
    try {
      final size = await file.length();
      final result = await api.uploadDocument(
        file,
        source: source,
        onProgress: (sent, total) {
          if (total > 0) progress.value = (sent / total).clamp(0.0, 1.0);
        },
      );
      uploaded.add(result.id);
      progress.value = 1;
      if (size <= 0) {
        errors.add('${currentName.value} : fichier vide');
      }
    } catch (error) {
      errors.add('${currentName.value} : ${shortErrorMessage(error)}');
    }
    if (i < files.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  if (!context.mounted) return;
  state.value = _UploadPhase.done;
  Navigator.of(context, rootNavigator: true).pop();

  if (uploaded.isEmpty) {
    showAppSnack(
      context,
      errors.isEmpty ? 'Aucun fichier envoyé.' : errors.first,
      error: true,
    );
    return;
  }

  if (errors.isNotEmpty) {
    showAppSnack(
      context,
      '${uploaded.length} envoyé(s), ${errors.length} erreur(s)',
    );
  } else {
    showAppSnack(context, 'Document ajouté à la file de traitement');
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AnalysisScreen(documentIds: uploaded),
    ),
  );
}

enum _UploadPhase { uploading, done }

class _UploadProgressSheet extends StatelessWidget {
  const _UploadProgressSheet({
    required this.progress,
    required this.currentName,
    required this.state,
    required this.fileCount,
  });

  final ValueNotifier<double> progress;
  final ValueNotifier<String> currentName;
  final ValueNotifier<_UploadPhase> state;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 34),
      child: ValueListenableBuilder<_UploadPhase>(
        valueListenable: state,
        builder: (context, phase, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_upload_outlined,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    phase == _UploadPhase.done
                        ? 'Envoi terminé'
                        : 'Envoi vers DocuMind…',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ValueListenableBuilder<String>(
              valueListenable: currentName,
              builder: (context, name, _) => Text(
                name.isEmpty ? '$fileCount fichier(s)' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 7,
                  backgroundColor: AppColors.beige200,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => Text(
                '${(value * 100).round()} %',
                style: const TextStyle(fontSize: 11, color: AppColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
