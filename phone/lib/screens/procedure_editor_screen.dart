import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/procedure.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';

class ProcedureEditorScreen extends StatefulWidget {
  const ProcedureEditorScreen({super.key, this.procedure});

  final Procedure? procedure;

  bool get isEdit => procedure != null;

  @override
  State<ProcedureEditorScreen> createState() => _ProcedureEditorScreenState();
}

class _ProcedureEditorScreenState extends State<ProcedureEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _remarks;

  late String _type;
  late List<Map<String, String>> _required;
  File? _image;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final procedure = widget.procedure;
    _name = TextEditingController(text: procedure?.name ?? '');
    _description = TextEditingController(text: procedure?.description ?? '');
    _remarks = TextEditingController(text: procedure?.remarks ?? '');
    _type = procedure?.procedureType ?? 'administrative';
    _required = (procedure?.requiredDocuments ?? const [])
        .map(
          (doc) => {
            'doc_type': doc.docType,
            'label': doc.label,
            if (doc.description != null) 'description': doc.description!,
          },
        )
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _image = File(path));
  }

  Future<void> _addRequired() async {
    final label = TextEditingController();
    var type = 'administratif';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Document requis'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Libellé',
                  hintText: 'Ex. Justificatif de domicile',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final option in docTypeOptions)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(option.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => type = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final text = label.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop({'doc_type': type, 'label': text});
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (result == null || !mounted) return;
    setState(() => _required = [..._required, result]);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, 'Donnez un nom à la démarche.', error: true);
      return;
    }
    if (!widget.isEdit && _required.isEmpty && _image == null) {
      showAppSnack(
        context,
        'Ajoutez au moins un document ou une image de la liste.',
        error: true,
      );
      return;
    }
    final api = context.read<AppState>().api!;
    setState(() => _saving = true);
    try {
      Procedure result;
      if (widget.isEdit) {
        result = await api.updateProcedure(
          widget.procedure!.id,
          name: name,
          procedureType: _type,
          description: _description.text.trim(),
          remarks: _remarks.text.trim(),
          requiredDocuments: _required
              .map(
                (item) => {
                  'doc_type': item['doc_type'] ?? 'autre',
                  'label': item['label'] ?? '',
                  if (item['description'] != null)
                    'description': item['description']!,
                },
              )
              .toList(),
        );
      } else {
        String? imageBase64;
        if (_image != null) {
          imageBase64 = base64Encode(await _image!.readAsBytes());
        }
        result = await api.createProcedure(
          procedureType: _type,
          name: name,
          manualDocuments: _required
              .map((item) => item['label'] ?? '')
              .where((label) => label.isNotEmpty)
              .toList(),
          remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          imageBase64: imageBase64,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(
        context,
        'Enregistrement impossible : ${shortErrorMessage(error)}',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEdit ? 'Modifier la démarche' : 'Nouvelle démarche',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Type de démarche'),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  items: [
                    for (final entry in procedureTypeLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 12),
                const _Label('Nom'),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ex. Renouvellement de titre de séjour',
                  ),
                ),
                const SizedBox(height: 12),
                const _Label('Description'),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'À quoi sert cette démarche ?',
                  ),
                ),
                const SizedBox(height: 12),
                const _Label('Remarques'),
                TextField(
                  controller: _remarks,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Informations complémentaires, délais…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Documents requis',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addRequired,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
                if (_required.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aucun document requis pour le moment.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  )
                else
                  for (var i = 0; i < _required.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.description_outlined,
                        size: 19,
                        color: AppColors.accent,
                      ),
                      title: Text(
                        _required[i]['label'] ?? '',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      subtitle: Text(
                        docTypeLabel(_required[i]['doc_type']),
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 17),
                        onPressed: () => setState(() {
                          _required = [..._required]..removeAt(i);
                        }),
                      ),
                    ),
                if (!widget.isEdit) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined, size: 17),
                    label: Text(
                      _image == null
                          ? 'Joindre une image de la liste'
                          : 'Image jointe : ${_image!.path.split('/').last}',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'L’IA analysera le nom saisi, la liste et l’image pour '
                    'structurer les documents requis.',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AsyncButton(
            label: _saving
                ? 'Enregistrement…'
                : widget.isEdit
                ? 'Enregistrer les modifications'
                : 'Créer la démarche',
            icon: widget.isEdit ? Icons.save_outlined : Icons.auto_awesome,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
