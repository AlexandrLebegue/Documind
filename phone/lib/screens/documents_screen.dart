import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/document_card.dart';
import '../widgets/skeleton.dart';
import 'add_document_sheet.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    this.queryListenable,
    this.embedded = true,
  });

  final ValueListenable<String>? queryListenable;
  final bool embedded;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  List<DocumentModel> _documents = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  String _docType = '';
  String _sort = 'newest';
  DocumentViewMode _view = DocumentViewMode.grid;

  static const _pageSize = 24;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.queryListenable?.addListener(_onExternalQuery);
    final initial = widget.queryListenable?.value ?? '';
    if (initial.isNotEmpty) {
      _query = initial;
      _searchController.text = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    widget.queryListenable?.removeListener(_onExternalQuery);
    super.dispose();
  }

  void _onExternalQuery() {
    final value = widget.queryListenable?.value ?? '';
    if (value == _query && _searchController.text == value) return;
    _searchController.text = value;
    _query = value;
    _load(reset: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 320) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (value.trim() == _query) return;
      setState(() => _query = value.trim());
      _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || _documents.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await api.documents(
        query: _query,
        docType: _docType,
        limit: _pageSize,
        offset: reset ? 0 : _documents.length,
      );
      final sorted = _sortDocuments(page.documents);
      if (!mounted) return;
      setState(() {
        _documents = reset ? sorted : [..._documents, ...sorted];
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = shortErrorMessage(error);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _documents.length >= _total) return;
    final previousLength = _documents.length;
    await _load(reset: false);
    if (!mounted || _documents.length == previousLength) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  List<DocumentModel> _sortDocuments(List<DocumentModel> docs) {
    final sorted = [...docs];
    switch (_sort) {
      case 'oldest':
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'name':
        sorted.sort(
          (a, b) =>
              a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
        );
      case 'type':
        sorted.sort((a, b) => (a.docType ?? '').compareTo(b.docType ?? ''));
      default:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return sorted;
  }

  Future<void> _openAddSheet() async {
    final changed = await showAddDocumentSheet(context);
    if (changed == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, widget.embedded ? 16 : 8, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.embedded)
                    IconButton(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  PageHeader(
                    title: 'Mes documents',
                    subtitle: '$_total document${_total == 1 ? '' : 's'}',
                    action: IconButton.filled(
                      tooltip: 'Ajouter un document',
                      onPressed: _openAddSheet,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Rechercher par nom, contenu, émetteur…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 19),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterDropdown(
                          value: _docType,
                          hint: 'Tous les types',
                          items: [
                            const MapEntry('', 'Tous les types'),
                            ...docTypeOptions,
                          ],
                          onChanged: (value) {
                            setState(() => _docType = value);
                            _load(reset: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterDropdown(
                          value: _sort,
                          hint: 'Trier',
                          items: const [
                            MapEntry('newest', 'Plus récents'),
                            MapEntry('oldest', 'Plus anciens'),
                            MapEntry('name', 'Nom'),
                            MapEntry('type', 'Type'),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _sort = value;
                              _documents = _sortDocuments(_documents);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ViewToggle(
                        mode: _view,
                        onChanged: (mode) => setState(() => _view = mode),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              sliver: SliverToBoxAdapter(
                child: SkeletonList(
                  count: 6,
                  height: _view == DocumentViewMode.grid ? 190 : 84,
                  grid: _view == DocumentViewMode.grid,
                ),
              ),
            )
          else if (_error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              sliver: SliverToBoxAdapter(
                child: ErrorState(
                  message: _error!,
                  onRetry: () => _load(reset: true),
                ),
              ),
            )
          else if (_documents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.description_outlined,
                title: 'Aucun document',
                message: _query.isNotEmpty || _docType.isNotEmpty
                    ? 'Aucun résultat pour ces critères de recherche.'
                    : 'Commencez par ajouter votre premier document.',
                action: _query.isEmpty && _docType.isEmpty
                    ? FilledButton.icon(
                        onPressed: _openAddSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter un document'),
                      )
                    : null,
              ),
            )
          else if (_view == DocumentViewMode.grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => CascadeIn(
                    index: index,
                    child: DocumentCard(document: _documents[index]),
                  ),
                  childCount: _documents.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              sliver: SliverList.separated(
                itemCount: _documents.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => CascadeIn(
                  index: index,
                  child: DocumentCard(
                    document: _documents[index],
                    view: DocumentViewMode.list,
                  ),
                ),
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 90),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final List<MapEntry<String, String>> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.beige300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((item) => item.key == value)
              ? value
              : items.first.key,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: const TextStyle(fontSize: 12, color: AppColors.ink),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.key,
                  child: Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mode, required this.onChanged});

  final DocumentViewMode mode;
  final ValueChanged<DocumentViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.beige300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(Icons.grid_view_rounded, DocumentViewMode.grid),
          _toggleButton(Icons.view_list_rounded, DocumentViewMode.list),
        ],
      ),
    );
  }

  Widget _toggleButton(IconData icon, DocumentViewMode target) {
    final selected = mode == target;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: () => onChanged(target),
      child: Container(
        width: 40,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius - 2),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? Colors.white : AppColors.muted,
        ),
      ),
    );
  }
}
