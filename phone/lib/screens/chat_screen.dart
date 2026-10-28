import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';
import 'document_detail_screen.dart';

enum _ChatMode { agent, documents }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  List<ChatSession> _sessions = const [];
  String? _sessionId;
  List<ChatMessage> _messages = const [];
  _ChatMode _mode = _ChatMode.agent;
  bool _loadingSessions = true;
  bool _loadingHistory = false;
  bool _sending = false;
  String? _error;
  List<_LiveTool> _liveTools = const [];
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSessions());
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dispose');
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final sessions = await api.chatSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loadingSessions = false;
      });
      if (sessions.isNotEmpty && _sessionId == null) {
        await _selectSession(sessions.first.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSessions = false);
    }
  }

  Future<void> _selectSession(String id) async {
    if (_sessionId == id) return;
    final api = context.read<AppState>().api!;
    setState(() {
      _sessionId = id;
      _loadingHistory = true;
      _messages = const [];
      _error = null;
    });
    try {
      final messages = await api.chatHistory(id);
      if (!mounted || _sessionId != id) return;
      setState(() {
        _messages = messages;
        _loadingHistory = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _error = shortErrorMessage(error);
      });
    }
  }

  void _newConversation() {
    _cancelStreaming();
    setState(() {
      _sessionId = null;
      _messages = const [];
      _error = null;
      _liveTools = const [];
      _sending = false;
    });
    _input.clear();
    _focus.requestFocus();
  }

  void _cancelStreaming() {
    if (_sending) {
      _cancelToken?.cancel('user');
      setState(() {
        _sending = false;
        _liveTools = const [];
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(0, duration: Motion.normal, curve: Motion.curve);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final api = context.read<AppState>().api!;
    final userMessage = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      message: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, userMessage];
      _input.clear();
      _sending = true;
      _error = null;
      _liveTools = const [];
    });
    _scrollToBottom();

    if (_mode == _ChatMode.documents) {
      try {
        final reply = await api.sendChat(text, sessionId: _sessionId);
        if (!mounted) return;
        setState(() {
          _sessionId = reply.sessionId;
          _messages = [
            ..._messages,
            ChatMessage(
              id: 'reply-${DateTime.now().microsecondsSinceEpoch}',
              role: 'assistant',
              message: reply.reply,
              createdAt: DateTime.now(),
              contextDocIds: reply.sourceDocumentIds,
              contextDocs: reply.sourceDocuments,
              toolCalls: reply.toolCalls,
            ),
          ];
        });
        _scrollToBottom();
        _refreshSessions();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _error = shortErrorMessage(error);
          _messages = _messages
              .where((message) => message.id != userMessage.id)
              .toList();
          _input.text = text;
        });
        showAppSnack(context, shortErrorMessage(error), error: true);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      await for (final event in api.streamAgent(
        text,
        sessionId: _sessionId,
        cancelToken: cancelToken,
      )) {
        if (!mounted) return;
        switch (event) {
          case AgentSessionEvent():
            setState(() => _sessionId = event.sessionId);
          case AgentToolStart():
            setState(() {
              _liveTools = [
                ..._liveTools,
                _LiveTool(tool: event.tool, args: event.args),
              ];
            });
          case AgentToolDone():
            final tools = [..._liveTools];
            for (var i = tools.length - 1; i >= 0; i--) {
              if (tools[i].tool == event.tool && !tools[i].done) {
                tools[i] = tools[i].copyWith(done: true);
                break;
              }
            }
            setState(() => _liveTools = tools);
          case AgentDone():
            setState(() {
              _sessionId = event.sessionId;
              _messages = [
                ..._messages,
                ChatMessage(
                  id: 'reply-${DateTime.now().microsecondsSinceEpoch}',
                  role: 'assistant',
                  message: event.reply,
                  createdAt: DateTime.now(),
                  toolCalls: event.toolCalls,
                ),
              ];
              _liveTools = const [];
              _sending = false;
            });
            _scrollToBottom();
            _refreshSessions();
          case AgentError():
            setState(() {
              _error = event.message;
              _liveTools = const [];
              _sending = false;
            });
        }
      }
    } on DioException catch (error) {
      if (!mounted || CancelToken.isCancel(error)) return;
      setState(() {
        _sending = false;
        _error = shortErrorMessage(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = shortErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshSessions() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final sessions = await api.chatSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (_) {}
  }

  Future<void> _openSessions() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SessionsSheet(
        sessions: _sessions,
        loading: _loadingSessions,
        activeId: _sessionId,
        onDelete: (session) async {
          final api = context.read<AppState>().api!;
          await api.deleteChatSession(session.id);
          if (!mounted) return false;
          setState(() {
            _sessions = _sessions.where((s) => s.id != session.id).toList();
            if (_sessionId == session.id) {
              _sessionId = null;
              _messages = const [];
            }
          });
          return true;
        },
        onRename: (session, title) async {
          final api = context.read<AppState>().api!;
          final updated = await api.renameChatSession(session.id, title);
          if (!mounted) return;
          setState(() {
            _sessions = _sessions
                .map((s) => s.id == updated.id ? updated : s)
                .toList();
          });
        },
      ),
    );
    if (selected != null && mounted) _selectSession(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // HomeShell already resizes for the keyboard.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _focus.unfocus();
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assistant'),
            Text(
              _mode == _ChatMode.agent
                  ? 'Agent avec recherche web'
                  : 'Réponses issues de vos documents',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Conversations',
            onPressed: _sending ? null : _openSessions,
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Nouvelle conversation',
            onPressed: _newConversation,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focus.unfocus(),
        child: Column(
          children: [
            Expanded(
              child: _loadingHistory
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Shimmer(
                        child: Column(
                          children: [
                            SkeletonBox(height: 70),
                            SizedBox(height: 12),
                            SkeletonBox(height: 90),
                            Spacer(),
                          ],
                        ),
                      ),
                    )
                  : _messages.isEmpty
                  ? _emptyState()
                  : _messageList(),
            ),
            if (_liveTools.isNotEmpty) _liveToolsBar(),
            if (_error != null) _errorBar(),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    const suggestions = [
      'Quels documents expirent bientôt ?',
      'Résume mes documents administratifs',
      'Quelles démarches sont en cours ?',
    ];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        const SizedBox(height: 12),
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.accent,
            size: 27,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Posez une question sur vos documents',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'L’assistant peut retrouver un document, résumer une démarche ou '
          'chercher une information sur le web.',
          style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        const Text(
          'Exemples',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                onTap: () {
                  _input.text = suggestion;
                  _send();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(
                      color: AppColors.beige300.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestion,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      const Icon(
                        Icons.north_east,
                        size: 15,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _messageList() {
    final reversed = _messages.reversed.toList();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      itemCount: reversed.length + (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_sending && index == 0) return const _ThinkingBubble();
        final message = reversed[index - (_sending ? 1 : 0)];
        return _MessageBubble(message: message, onDocumentTap: _openDocument);
      },
    );
  }

  Widget _liveToolsBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: AppColors.accentLight.withValues(alpha: 0.45),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final tool in _liveTools)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: tool.done
                      ? const Icon(
                          Icons.check_circle,
                          size: 11,
                          color: AppColors.accent,
                        )
                      : const CircularProgressIndicator(strokeWidth: 1.4),
                ),
                const SizedBox(width: 4),
                Text(
                  _toolLabel(tool.tool),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _errorBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: AppColors.dangerBg,
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: AppColors.danger),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close, size: 15),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.beige200)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _modeChip(_ChatMode.agent, 'Agent', Icons.auto_awesome),
                const SizedBox(width: 6),
                _modeChip(
                  _ChatMode.documents,
                  'Documents',
                  Icons.folder_outlined,
                ),
                const Spacer(),
                if (_sending)
                  TextButton.icon(
                    onPressed: _cancelStreaming,
                    icon: const Icon(Icons.stop_circle_outlined, size: 17),
                    label: const Text('Arrêter'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    onTapOutside: (_) => _focus.unfocus(),
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _mode == _ChatMode.agent
                          ? 'Demandez à l’agent…'
                          : 'Interrogez vos documents…',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward, size: 21),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(_ChatMode mode, String label, IconData icon) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: _sending ? null : () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight : AppColors.beige50,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.beige300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? AppColors.accent : AppColors.muted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDocument(String id) {
    Navigator.of(
      context,
    ).push(slideFadeRoute(DocumentDetailScreen(documentId: id)));
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onDocumentTap});

  final ChatMessage message;
  final ValueChanged<String> onDocumentTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[_avatar(false), const SizedBox(width: 8)],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 310),
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
              decoration: BoxDecoration(
                color: isUser ? AppColors.accent : AppColors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 5),
                  bottomRight: Radius.circular(isUser ? 5 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: AppColors.beige300.withValues(alpha: 0.5),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.message,
                    onTapLink: (text, href, title) {
                      _handleLink(context, href);
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      strong: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      em: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      h1: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      h2: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      h3: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      listBullet: TextStyle(
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      code: TextStyle(
                        fontSize: 11.5,
                        backgroundColor: isUser
                            ? Colors.white.withValues(alpha: 0.16)
                            : AppColors.beige100,
                        color: isUser ? Colors.white : AppColors.ink,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: isUser
                            ? Colors.white.withValues(alpha: 0.1)
                            : AppColors.beige50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquotePadding: const EdgeInsets.all(8),
                      a: const TextStyle(
                        color: AppColors.accent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (!isUser && message.toolCalls.isNotEmpty)
                    _ToolCallsPanel(toolCalls: message.toolCalls),
                  if (!isUser &&
                      (message.contextDocs.isNotEmpty ||
                          message.contextDocIds.isNotEmpty))
                    _Sources(
                      docs: message.contextDocs,
                      ids: message.contextDocIds,
                      onTap: onDocumentTap,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 9,
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[const SizedBox(width: 8), _avatar(true)],
        ],
      ),
    );
  }

  Widget _avatar(bool user) {
    return Container(
      width: 27,
      height: 27,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: user ? AppColors.accent : AppColors.beige200,
        shape: BoxShape.circle,
      ),
      child: Text(
        user ? 'V' : 'D',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: user ? Colors.white : AppColors.muted,
        ),
      ),
    );
  }

  void _handleLink(BuildContext context, String? href) {
    if (href == null || href.isEmpty) return;
    final match = RegExp(r'[?&]id=([a-fA-F0-9-]{36})').firstMatch(href);
    final pathMatch = RegExp(
      r'/documents/(?:view/)?([a-fA-F0-9-]{36})',
    ).firstMatch(href);
    final id = match?.group(1) ?? pathMatch?.group(1);
    if (id != null) {
      onDocumentTap(id);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.docs, required this.ids, required this.onTap});

  final List<SourceDocument> docs;
  final List<String> ids;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final entries = docs.isNotEmpty
        ? docs.map((doc) => (id: doc.id, title: doc.title)).toList()
        : ids.map((id) => (id: id, title: 'Document')).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 7),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.beige200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sources',
            style: TextStyle(fontSize: 9.5, color: AppColors.muted),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final entry in entries)
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => onTap(entry.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.beige100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 11,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolCallsPanel extends StatefulWidget {
  const _ToolCallsPanel({required this.toolCalls});

  final List<ToolCallLog> toolCalls;

  @override
  State<_ToolCallsPanel> createState() => _ToolCallsPanelState();
}

class _ToolCallsPanelState extends State<_ToolCallsPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.beige200)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.build_outlined,
                  size: 12,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.toolCalls.length} outil(s) utilisé(s)',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            for (final tool in widget.toolCalls)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_toolLabel(tool.tool)} — ${tool.resultPreview}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.7),
            ),
            SizedBox(width: 8),
            Text(
              'L’assistant réfléchit…',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsSheet extends StatelessWidget {
  const _SessionsSheet({
    required this.sessions,
    required this.loading,
    required this.activeId,
    required this.onDelete,
    required this.onRename,
  });

  final List<ChatSession> sessions;
  final bool loading;
  final String? activeId;
  final Future<bool> Function(ChatSession) onDelete;
  final Future<void> Function(ChatSession, String) onRename;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
          const SizedBox(height: 14),
          const Text(
            'Conversations',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'Aucune conversation',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final active = session.id == activeId;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      Icons.forum_outlined,
                      size: 19,
                      color: active ? AppColors.accent : AppColors.muted,
                    ),
                    title: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppColors.accent : AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      formatRelativeDate(session.updatedAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.faint,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (value) async {
                        if (value == 'rename') {
                          final controller = TextEditingController(
                            text: session.title,
                          );
                          final title = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Renommer'),
                              content: TextField(
                                controller: controller,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Titre de la conversation',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Annuler'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(
                                    context,
                                  ).pop(controller.text.trim()),
                                  child: const Text('Renommer'),
                                ),
                              ],
                            ),
                          );
                          controller.dispose();
                          if (title != null &&
                              title.isNotEmpty &&
                              context.mounted) {
                            await onRename(session, title);
                          }
                        } else if (value == 'delete') {
                          final ok = await onDelete(session);
                          if (ok && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renommer')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Supprimer'),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.of(context).pop(session.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveTool {
  const _LiveTool({required this.tool, required this.args, this.done = false});

  final String tool;
  final Map<String, dynamic> args;
  final bool done;

  _LiveTool copyWith({bool? done}) =>
      _LiveTool(tool: tool, args: args, done: done ?? this.done);
}

String _toolLabel(String tool) {
  return switch (tool) {
    'recherche_web' => 'Recherche web',
    'scraper_page' => 'Lecture de page',
    'verifier_liens' => 'Vérification de liens',
    'crawler_procedures' => 'Crawl de site',
    'creer_procedure' => 'Création de procédure',
    _ => tool,
  };
}
