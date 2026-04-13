import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/features/messaging/data/trip_message.dart';
import 'package:planzers/features/messaging/data/trip_messages_repository.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Trip-scoped text chat; history is visible to all current [Trip] members.
class TripMessagingPage extends ConsumerStatefulWidget {
  const TripMessagingPage({super.key});

  @override
  ConsumerState<TripMessagingPage> createState() => _TripMessagingPageState();
}

class _TripMessagingPageState extends ConsumerState<TripMessagingPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _selectedMessageId;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _clearSelection() {
    if (_selectedMessageId != null) {
      setState(() => _selectedMessageId = null);
    }
  }

  TripMessage? _messageById(List<TripMessage> messages, String? id) {
    if (id == null) return null;
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send(String tripId) async {
    final text = _textController.text;
    if (_sending) return;

    setState(() => _sending = true);
    try {
      await ref.read(tripMessagesRepositoryProvider).sendMessage(
            tripId: tripId,
            text: text,
          );
      if (!mounted) return;
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Envoi impossible : $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// Returns `true` if the message was updated.
  Future<bool> _editMessage(String tripId, TripMessage message) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _EditTripMessageDialog(initialText: message.text),
    );

    if (newText == null || !mounted) return false;
    try {
      await ref.read(tripMessagesRepositoryProvider).updateMessage(
            tripId: tripId,
            messageId: message.id,
            text: newText,
          );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $e')),
      );
      return false;
    }
  }

  /// Returns `true` if the message was deleted.
  Future<bool> _deleteMessage(String tripId, TripMessage message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Supprimer ce message ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return false;
    try {
      await ref.read(tripMessagesRepositoryProvider).deleteMessage(
            tripId: tripId,
            messageId: message.id,
          );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $e')),
      );
      return false;
    }
  }

  void _copyMessage(TripMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copié')),
    );
  }

  String _timeLine(TripMessage m, DateFormat timeFmt) {
    final t = m.wasEdited
        ? timeFmt.format(m.updatedAt!.toLocal())
        : timeFmt.format(m.createdAt.toLocal());
    return m.wasEdited ? '$t · modifié' : t;
  }

  List<_ChatListEntry> _buildChatEntries(
    List<TripMessage> messages,
    DateFormat dateFmt,
  ) {
    final entries = <_ChatListEntry>[];
    DateTime? previousDate;
    for (final message in messages) {
      final localDate = message.createdAt.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      if (previousDate == null || day != previousDate) {
        entries.add(
          _ChatListEntry.separator(
            _dayLabelFor(day, dateFmt),
          ),
        );
        previousDate = day;
      }
      entries.add(_ChatListEntry.message(message));
    }
    return entries;
  }

  String _dayLabelFor(DateTime day, DateFormat dateFmt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return "Aujourd'hui";
    if (day == yesterday) return 'Hier';
    return dateFmt.format(day);
  }

  /// Mouse / trackpad: tap should open the action bar (long-press is unreliable).
  static bool _pointerSelectsMessage(BuildContext context) {
    if (kIsWeb) return true;
    return switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        false,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final messagesAsync = ref.watch(tripMessagesStreamProvider(trip.id));

    ref.listen(tripMessagesStreamProvider(trip.id), (_, next) {
      next.whenData((_) => _scrollToBottom());
    });

    return PopScope(
      canPop: _selectedMessageId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedMessageId != null) {
          _clearSelection();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: messagesAsync.when(
          data: (messages) {
            final timeFmt = DateFormat.Hm('fr_FR');
            final dateFmt = DateFormat('d MMMM yyyy', 'fr_FR');
            final selected = _messageById(messages, _selectedMessageId);
            if (_selectedMessageId != null && selected == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _clearSelection();
              });
            }
            final selectedIsMine =
                selected != null && myUid != null && selected.authorId == myUid;

            final labelUserIds = <String>{
              for (final id in trip.memberIds)
                if (id.trim().isNotEmpty) id.trim(),
              for (final m in messages)
                if (m.authorId.trim().isNotEmpty) m.authorId.trim(),
            }.toList();

            return StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: ref
                  .read(usersRepositoryProvider)
                  .watchUsersDataByIds(labelUserIds),
              builder: (context, userSnap) {
                final userDocs =
                    userSnap.data ?? const <String, Map<String, dynamic>>{};
                final authorLabels = tripMemberLabelsFromUserDocsById(
                  userDocs,
                  labelUserIds,
                  tripMemberPublicLabels: trip.memberPublicLabels,
                  currentUserId: myUid,
                  emptyFallback: 'Participant',
                );
                final pointerSelect = _pointerSelectsMessage(context);
                final chatEntries = _buildChatEntries(messages, dateFmt);

                return Column(
                  children: [
                    if (selected != null)
                      _MessageSelectionAppBar(
                        selectedIsMine: selectedIsMine,
                        onClose: _clearSelection,
                        onCopy: () => _copyMessage(selected),
                        onEdit: selectedIsMine
                            ? () async {
                                final ok =
                                    await _editMessage(trip.id, selected);
                                if (ok && mounted) _clearSelection();
                              }
                            : null,
                        onDelete: selectedIsMine
                            ? () async {
                                final ok =
                                    await _deleteMessage(trip.id, selected);
                                if (ok && mounted) _clearSelection();
                              }
                            : null,
                      ),
                    Expanded(
                      child: messages.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Aucun message pour l’instant. '
                                  'Écris le premier pour lancer la discussion.',
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              itemCount: chatEntries.length,
                              itemBuilder: (context, index) {
                                final entry = chatEntries[index];
                                if (entry.dayLabel != null) {
                                  return _MessageDayPill(label: entry.dayLabel!);
                                }
                                final m = entry.message!;
                                final isMine =
                                    myUid != null && m.authorId == myUid;
                                final isSelected =
                                    m.id == _selectedMessageId;
                                final label = authorLabels[m.authorId] ??
                                    resolveTripMemberDisplayLabel(
                                      memberId: m.authorId,
                                      userData: null,
                                      tripMemberPublicLabels:
                                          trip.memberPublicLabels,
                                      currentUserId: myUid,
                                      emptyFallback: 'Participant',
                                    );
                                final timeLine = _timeLine(m, timeFmt);

                                return Align(
                                  alignment: isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.sizeOf(context).width *
                                              0.85,
                                    ),
                                    child: GestureDetector(
                                      onLongPress: () {
                                        setState(
                                            () => _selectedMessageId = m.id);
                                      },
                                      onSecondaryTap: pointerSelect
                                          ? () => setState(
                                              () => _selectedMessageId = m.id,
                                            )
                                          : null,
                                      onTap: (_selectedMessageId != null ||
                                              pointerSelect)
                                          ? () {
                                              if (_selectedMessageId !=
                                                  null) {
                                                setState(() {
                                                  if (_selectedMessageId ==
                                                      m.id) {
                                                    _selectedMessageId = null;
                                                  } else {
                                                    _selectedMessageId = m.id;
                                                  }
                                                });
                                              } else {
                                                setState(() =>
                                                    _selectedMessageId = m.id);
                                              }
                                            }
                                          : null,
                                      behavior: HitTestBehavior.opaque,
                                      child: MouseRegion(
                                        cursor: pointerSelect &&
                                                _selectedMessageId == null
                                            ? SystemMouseCursors.click
                                            : MouseCursor.defer,
                                        child: Card(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 4,
                                            horizontal: 4,
                                          ),
                                          elevation: isSelected ? 0 : null,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: isSelected
                                                ? BorderSide(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    width: 2,
                                                  )
                                                : BorderSide.none,
                                          ),
                                          color: isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.55)
                                              : (isMine
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .baseline,
                                                textBaseline:
                                                    TextBaseline.alphabetic,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      label,
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    timeLine,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              _TripMessageLinkedText(
                                                text: m.text,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                                selectable:
                                                    _selectedMessageId ==
                                                            null &&
                                                        !pointerSelect,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Material(
                      elevation: 2,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  minLines: 1,
                                  maxLines: 5,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Message…',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onSubmitted: _sending
                                      ? null
                                      : (_) => _send(trip.id),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _sending
                                    ? null
                                    : () => _send(trip.id),
                                icon: _sending
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send),
                                tooltip: 'Envoyer',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erreur : $e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders [text] with `http(s)://` and `www.` segments as tappable links.
class _TripMessageLinkedText extends StatefulWidget {
  const _TripMessageLinkedText({
    required this.text,
    required this.style,
    required this.selectable,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  State<_TripMessageLinkedText> createState() =>
      _TripMessageLinkedTextState();
}

class _TripMessageLinkedTextState extends State<_TripMessageLinkedText> {
  static final RegExp _urlRegex = RegExp(
    r'(https?://[^\s]+)|(www\.[^\s]+)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];
  String? _spansForText;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _ensureSpans(BuildContext context) {
    if (_spansForText == widget.text) return;
    _disposeRecognizers();
    _spansForText = widget.text;
    _spans = _buildSpans(context);
  }

  List<InlineSpan> _buildSpans(BuildContext context) {
    final text = widget.text;
    final baseStyle = widget.style;
    final scheme = Theme.of(context).colorScheme;
    final linkStyle = baseStyle?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );

    final children = <InlineSpan>[];
    var start = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > start) {
        children.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }
      final raw = match.group(0)!;
      final trimmed = _trimUrlWrappingPunctuation(raw);
      final href = trimmed.toLowerCase().startsWith('www.')
          ? 'https://$trimmed'
          : trimmed;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(_openTripMessageUrl(context, href));
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: raw,
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (children.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    _ensureSpans(context);
    final span = TextSpan(style: widget.style, children: _spans);
    if (widget.selectable) {
      return SelectableText.rich(span);
    }
    return Text.rich(span);
  }
}

String _trimUrlWrappingPunctuation(String raw) {
  var s = raw;
  while (s.isNotEmpty) {
    final last = s[s.length - 1];
    if ('.,;:!?)]}\'"'.contains(last)) {
      s = s.substring(0, s.length - 1);
      continue;
    }
    break;
  }
  return s;
}

Future<void> _openTripMessageUrl(BuildContext context, String url) async {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien invalide')),
      );
    }
    return;
  }

  final didLaunch = await launchUrl(
    parsed,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_blank',
  );

  if (!didLaunch && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d\'ouvrir le lien')),
    );
  }
}

/// Top bar when a message is selected (WhatsApp-style actions).
class _MessageSelectionAppBar extends StatelessWidget {
  const _MessageSelectionAppBar({
    required this.selectedIsMine,
    required this.onClose,
    required this.onCopy,
    this.onEdit,
    this.onDelete,
  });

  final bool selectedIsMine;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fermer',
                onPressed: onClose,
              ),
              const Spacer(),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Modifier',
                  onPressed: () => onEdit!(),
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: () => onDelete!(),
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copier',
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageDayPill extends StatelessWidget {
  const _MessageDayPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatListEntry {
  const _ChatListEntry.message(this.message) : dayLabel = null;
  const _ChatListEntry.separator(this.dayLabel) : message = null;

  final TripMessage? message;
  final String? dayLabel;
}

/// Owns its [TextEditingController] for a correct dispose after the dialog
/// route is popped.
class _EditTripMessageDialog extends StatefulWidget {
  const _EditTripMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditTripMessageDialog> createState() =>
      _EditTripMessageDialogState();
}

class _EditTripMessageDialogState extends State<_EditTripMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le message'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: TripMessagesRepository.maxTextLength,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, t);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
