import 'dart:async';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Generic chat widget that can be instantiated independently of any specific
/// data source. All operations are injected as callbacks; all data is passed
/// as plain parameters. [TripMessagingPage] is the canonical thin wrapper.
class ChatWidget extends StatefulWidget {
  const ChatWidget({
    super.key,
    required this.currentUserId,
    required this.messages,
    required this.reactions,
    required this.userDocs,
    required this.authorLabels,
    required this.onSend,
    required this.onUpdate,
    required this.onDelete,
    required this.onSetReaction,
    required this.onRemoveReaction,
    this.showUserBadges = true,
  });

  final String? currentUserId;
  final List<TripMessage> messages;

  /// Map from message ID to its list of reactions.
  final Map<String, List<TripMessageReaction>> reactions;

  /// Map from user ID to raw Firestore user data (for profile badges).
  final Map<String, Map<String, dynamic>> userDocs;

  /// Pre-resolved display labels keyed by user ID.
  final Map<String, String> authorLabels;

  final Future<void> Function(String text) onSend;
  final Future<void> Function(String messageId, String text) onUpdate;
  final Future<void> Function(String messageId) onDelete;
  final Future<void> Function(String messageId, String emoji) onSetReaction;
  final Future<void> Function(String messageId) onRemoveReaction;

  /// When false (e.g. 2-person DM), author badges are hidden.
  final bool showUserBadges;

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  static const List<String> _quickReactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '🙏',
  ];

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _selectedMessageId;
  bool _hasInitiallyScrolled = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(ChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.messages, oldWidget.messages)) {
      if (!_hasInitiallyScrolled) {
        _scrollToBottom();
      } else if (_isNearBottom()) {
        unawaited(_scrollToBottomAnimated());
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = !_isNearBottom();
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= 100.0;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _hasInitiallyScrolled = true;
    });
  }

  Future<void> _scrollToBottomAnimated() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _clearSelection() {
    if (_selectedMessageId != null) {
      setState(() => _selectedMessageId = null);
    }
  }

  TripMessage? _messageById(String? id) {
    if (id == null) return null;
    for (final m in widget.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      if (!mounted) return;
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.chatSendImpossible(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _pickEmoji() async {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SizedBox(
          height: math.min(MediaQuery.sizeOf(ctx).height * 0.55, 420),
          child: EmojiPicker(
            onEmojiSelected: (_, emoji) => Navigator.pop(ctx, emoji.emoji),
            config: Config(
              checkPlatformCompatibility: true,
              emojiViewConfig: EmojiViewConfig(
                columns: 8,
                emojiSizeMax: 32,
                noRecents: Text(
                  AppLocalizations.of(context)!.chatNoRecentEmoji,
                ),
              ),
              categoryViewConfig: CategoryViewConfig(
                iconColor: scheme.onSurfaceVariant,
                iconColorSelected: scheme.primary,
                indicatorColor: scheme.primary,
              ),
              bottomActionBarConfig: const BottomActionBarConfig(
                showBackspaceButton: false,
                showSearchViewButton: true,
              ),
              searchViewConfig: SearchViewConfig(
                buttonIconColor: scheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reactToMessage({
    required TripMessage message,
    required List<TripMessageReaction> reactions,
  }) async {
    final myUid = widget.currentUserId;
    if (myUid == null || myUid.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.chatUserNotConnected)),
      );
      return;
    }
    final selectedEmoji = await _pickEmoji();
    if (selectedEmoji == null || !mounted) return;
    await _setReactionWithEmoji(
      message: message,
      reactions: reactions,
      selectedEmoji: selectedEmoji,
    );
  }

  Future<void> _setReactionWithEmoji({
    required TripMessage message,
    required List<TripMessageReaction> reactions,
    required String selectedEmoji,
  }) async {
    final myUid = widget.currentUserId;
    if (myUid == null || myUid.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.chatUserNotConnected)),
      );
      return;
    }
    final currentReaction = reactions
        .where((r) => r.userId == myUid)
        .cast<TripMessageReaction?>()
        .firstWhere((r) => r != null, orElse: () => null);
    try {
      if (currentReaction?.emoji == selectedEmoji) {
        await widget.onRemoveReaction(message.id);
      } else {
        await widget.onSetReaction(message.id, selectedEmoji);
      }
      _clearSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.chatReactionImpossible(e.toString()),
          ),
        ),
      );
    }
  }

  Future<bool> _editMessage(TripMessage message) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditChatMessageDialog(initialText: message.text),
    );
    if (newText == null || !mounted) return false;
    try {
      await widget.onUpdate(message.id, newText);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.chatEditImpossible(e.toString()),
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> _deleteMessage(TripMessage message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(AppLocalizations.of(context)!.chatDeleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return false;
    try {
      await widget.onDelete(message.id);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.chatDeleteImpossible(e.toString()),
          ),
        ),
      );
      return false;
    }
  }

  void _copyMessage(TripMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.chatCopied)),
    );
  }

  List<_ChatListEntry> _buildChatEntries(
    List<TripMessage> messages,
    DateFormat dateFmt,
  ) {
    // First pass: messages + date separators
    final raw = <_ChatListEntry>[];
    DateTime? previousDate;
    for (final message in messages) {
      final localDate = message.createdAt.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      if (previousDate == null || day != previousDate) {
        raw.add(_ChatListEntry.separator(_dayLabelFor(day, dateFmt)));
        previousDate = day;
      }
      raw.add(_ChatListEntry.message(message));
    }

    // Second pass: mark which non-mine message is first in its consecutive run
    final currentUserId = widget.currentUserId;
    return List.generate(raw.length, (i) {
      final entry = raw[i];
      if (entry.message == null || entry.message!.authorId == currentUserId) {
        return entry;
      }
      final prev = i > 0 ? raw[i - 1] : null;
      final showBadge = prev == null ||
          prev.dayLabel != null ||
          (prev.message != null &&
              prev.message!.authorId != entry.message!.authorId);
      return showBadge
          ? _ChatListEntry.message(entry.message!, showBadge: true)
          : entry;
    });
  }

  String _dayLabelFor(DateTime day, DateFormat dateFmt) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return l10n.commonToday;
    if (day == yesterday) return l10n.commonYesterday;
    return dateFmt.format(day);
  }

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
    final l10n = AppLocalizations.of(context)!;
    final myUid = widget.currentUserId;
    final messages = widget.messages;
    final reactionsByMessage = widget.reactions;
    final localeTag = Localizations.localeOf(context).toString();
    final timeFmt = DateFormat.Hm(localeTag);
    final dateFmt = DateFormat('d MMMM yyyy', localeTag);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final selected = _messageById(_selectedMessageId);
    if (_selectedMessageId != null && selected == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearSelection();
      });
    }
    final selectedIsMine =
        selected != null && myUid != null && selected.authorId == myUid;
    final pointerSelect = _pointerSelectsMessage(context);
    final chatEntries = _buildChatEntries(messages, dateFmt);

    return PopScope(
      canPop: _selectedMessageId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedMessageId != null) _clearSelection();
      },
      child: Column(
        children: [
          if (selected != null)
            _MessageSelectionAppBar(
              selectedIsMine: selectedIsMine,
              onClose: _clearSelection,
              onCopy: () => _copyMessage(selected),
              onEdit: selectedIsMine
                  ? () async {
                      final ok = await _editMessage(selected);
                      if (ok && mounted) _clearSelection();
                    }
                  : null,
              onDelete: selectedIsMine
                  ? () async {
                      final ok = await _deleteMessage(selected);
                      if (ok && mounted) _clearSelection();
                    }
                  : null,
            ),
          Expanded(
            child: Stack(
              children: [
                if (messages.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.chatEmptyState,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  ListView.builder(
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
                      final isMine = myUid != null && m.authorId == myUid;
                      final isSelected = m.id == _selectedMessageId;
                      final label =
                          widget.authorLabels[m.authorId] ?? l10n.roleParticipant;
                      final reactions = reactionsByMessage[m.id] ??
                          const <TripMessageReaction>[];
                      final groupedReactions =
                          _groupReactions(reactions, myUid: myUid);
                      final previousMessage =
                          index > 0 ? chatEntries[index - 1].message : null;
                      final isPreviousMessageSameDay =
                          previousMessage != null &&
                              DateUtils.isSameDay(
                                previousMessage.createdAt.toLocal(),
                                m.createdAt.toLocal(),
                              );
                      final previousMessageReactions = previousMessage == null
                          ? const <TripMessageReaction>[]
                          : (reactionsByMessage[previousMessage.id] ??
                              const <TripMessageReaction>[]);
                      final extraTopCardMargin = isPreviousMessageSameDay &&
                              previousMessageReactions.isNotEmpty
                          ? 6.0
                          : 0.0;
                      final totalReactionCount = groupedReactions.fold<int>(
                        0,
                        (sum, g) => sum + g.count,
                      );
                      final reactionEmojis =
                          groupedReactions.map((g) => g.emoji).toList();

                      // Time + edited indicator colors
                      final timeColor = isMine
                          ? Colors.black.withValues(alpha: 0.5)
                          : scheme.onSurfaceVariant;

                      // Bubble color
                      final Color bubbleColor;
                      if (isSelected) {
                        bubbleColor = scheme.primary.withValues(alpha: 0.15);
                      } else if (isMine) {
                        bubbleColor = scheme.primaryContainer;
                      } else {
                        bubbleColor = scheme.surfaceContainerHighest;
                      }

                      final bubble = GestureDetector(
                        onLongPress: () =>
                            setState(() => _selectedMessageId = m.id),
                        onSecondaryTap: pointerSelect
                            ? () => setState(() => _selectedMessageId = m.id)
                            : null,
                        onTap: (_selectedMessageId != null || pointerSelect)
                            ? () => setState(() {
                                  _selectedMessageId =
                                      _selectedMessageId == m.id ? null : m.id;
                                })
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: MouseRegion(
                          cursor: pointerSelect && _selectedMessageId == null
                              ? SystemMouseCursors.click
                              : MouseCursor.defer,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.topCenter,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: isSelected ? 34 : 0,
                                  bottom:
                                      groupedReactions.isNotEmpty ? 16 : 0,
                                ),
                                child: Card(
                                  margin: EdgeInsets.fromLTRB(
                                    2,
                                    2 + extraTopCardMargin,
                                    2,
                                    2,
                                  ),
                                  elevation: isSelected ? 0 : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: isSelected
                                        ? BorderSide(
                                            color: scheme.primary,
                                            width: 2,
                                          )
                                        : BorderSide.none,
                                  ),
                                  color: bubbleColor,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 6, 10, 5),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!isMine) ...[
                                          Text(
                                            label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: scheme.secondary,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                        ],
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Flexible(
                                              child: _ChatLinkedText(
                                                text: m.text,
                                                style: theme.textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: isMine
                                                      ? Colors.black
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Transform.translate(
                                              offset: const Offset(0, 2),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (m.wasEdited) ...[
                                                    Icon(
                                                      Icons.edit_rounded,
                                                      size: 10,
                                                      color: timeColor,
                                                    ),
                                                    const SizedBox(width: 2),
                                                  ],
                                                  Text(
                                                    timeFmt.format(
                                                      (m.wasEdited
                                                              ? m.updatedAt!
                                                              : m.createdAt)
                                                          .toLocal(),
                                                    ),
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                      color: timeColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (groupedReactions.isNotEmpty)
                                Positioned(
                                  bottom: -4,
                                  left: isMine ? null : 8,
                                  right: isMine ? 8 : null,
                                  child: _MessageReactionsBadge(
                                    emojis: reactionEmojis,
                                    totalCount: totalReactionCount,
                                  ),
                                ),
                              if (isSelected)
                                Positioned(
                                  top: 0,
                                  child: _InlineMessageQuickReactionBar(
                                    emojis: _quickReactionEmojis,
                                    onEmojiTap: (emoji) =>
                                        _setReactionWithEmoji(
                                      message: m,
                                      reactions: reactions,
                                      selectedEmoji: emoji,
                                    ),
                                    onMoreTap: () => _reactToMessage(
                                      message: m,
                                      reactions: reactions,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );

                      // Non-mine messages: badge column + constrained bubble
                      if (!isMine && widget.showUserBadges) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 38, // 32px badge + 6px gap
                              child: entry.showBadge
                                  ? Align(
                                      alignment: Alignment.topCenter,
                                      child: buildProfileBadge(
                                        context: context,
                                        displayLabel: label,
                                        userData: widget.userDocs[m.authorId],
                                        size: 32,
                                      ),
                                    )
                                  : null,
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IntrinsicWidth(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(
                                        MediaQuery.sizeOf(context).width *
                                                0.85 -
                                            38,
                                        560,
                                      ),
                                    ),
                                    child: bubble,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: IntrinsicWidth(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.min(
                                MediaQuery.sizeOf(context).width * 0.85,
                                560,
                              ),
                            ),
                            child: bubble,
                          ),
                        ),
                      );
                    },
                  ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _ScrollToBottomButton(
                      onPressed: () => unawaited(_scrollToBottomAnimated()),
                    ),
                  ),
              ],
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
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: l10n.chatMessageHint,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                BorderSide(color: scheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                BorderSide(color: scheme.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: scheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        onSubmitted: _sending ? null : (_) => unawaited(_send()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : () => unawaited(_send()),
                      icon: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      tooltip: l10n.chatSend,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text rendering with URL detection and inline trailing span
// ---------------------------------------------------------------------------

class _ChatLinkedText extends StatefulWidget {
  const _ChatLinkedText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<_ChatLinkedText> createState() => _ChatLinkedTextState();
}

class _ChatLinkedTextState extends State<_ChatLinkedText> {
  static final RegExp _urlRegex = RegExp(
    r'(https?://[^\s]+)|(www\.[^\s]+)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _textSpans = const [];
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

  void _ensureTextSpans(BuildContext context) {
    if (_spansForText == widget.text) return;
    _disposeRecognizers();
    _spansForText = widget.text;
    _textSpans = _buildTextSpans(context);
  }

  List<InlineSpan> _buildTextSpans(BuildContext context) {
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
        ..onTap = () => unawaited(_openChatUrl(context, href));
      _recognizers.add(recognizer);
      children.add(
        TextSpan(text: raw, style: linkStyle, recognizer: recognizer),
      );
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (children.isEmpty) {
      children.add(TextSpan(text: text, style: baseStyle));
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    _ensureTextSpans(context);
    return Text.rich(TextSpan(style: widget.style, children: _textSpans));
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

Future<void> _openChatUrl(BuildContext context, String url) async {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.linkInvalid)),
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
      SnackBar(content: Text(AppLocalizations.of(context)!.linkOpenImpossible)),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection app bar
// ---------------------------------------------------------------------------

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
                tooltip: AppLocalizations.of(context)!.commonClose,
                onPressed: onClose,
              ),
              const Spacer(),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: AppLocalizations.of(context)!.commonEdit,
                  onPressed: () => unawaited(onEdit!()),
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppLocalizations.of(context)!.commonDelete,
                  onPressed: () => unawaited(onDelete!()),
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: AppLocalizations.of(context)!.chatCopy,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day separator pill
// ---------------------------------------------------------------------------

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
            border: Border.all(color: scheme.outlineVariant, width: 0.5),
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

// ---------------------------------------------------------------------------
// Chat list entry model
// ---------------------------------------------------------------------------

class _ChatListEntry {
  const _ChatListEntry.message(this.message, {this.showBadge = false})
      : dayLabel = null;
  const _ChatListEntry.separator(this.dayLabel)
      : message = null,
        showBadge = false;

  final TripMessage? message;
  final String? dayLabel;

  /// True when this is the first message in a consecutive run from the same
  /// author and a profile badge should be rendered beside it.
  final bool showBadge;
}

// ---------------------------------------------------------------------------
// Quick reaction bar (shown inline when message selected)
// ---------------------------------------------------------------------------

class _InlineMessageQuickReactionBar extends StatelessWidget {
  const _InlineMessageQuickReactionBar({
    required this.emojis,
    required this.onEmojiTap,
    required this.onMoreTap,
  });

  final List<String> emojis;
  final Future<void> Function(String emoji) onEmojiTap;
  final Future<void> Function() onMoreTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in emojis)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => unawaited(onEmojiTap(emoji)),
                  icon: Text(
                    emoji,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  tooltip: AppLocalizations.of(context)!.chatReactWithEmoji(emoji),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: () => unawaited(onMoreTap()),
              icon: const Icon(Icons.add),
              tooltip: AppLocalizations.of(context)!.chatMoreEmojis,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction grouping helpers
// ---------------------------------------------------------------------------

List<_ReactionGroup> _groupReactions(
  List<TripMessageReaction> reactions, {
  required String? myUid,
}) {
  final byEmoji = <String, _ReactionGroup>{};
  for (final reaction in reactions) {
    final emoji = reaction.emoji.trim();
    if (emoji.isEmpty) continue;
    final current = byEmoji[emoji];
    final containsCurrentUser = myUid != null && reaction.userId == myUid;
    if (current == null) {
      byEmoji[emoji] = _ReactionGroup(
        emoji: emoji,
        count: 1,
        containsCurrentUser: containsCurrentUser,
      );
    } else {
      byEmoji[emoji] = _ReactionGroup(
        emoji: emoji,
        count: current.count + 1,
        containsCurrentUser: current.containsCurrentUser || containsCurrentUser,
      );
    }
  }
  return byEmoji.values.toList()..sort((a, b) => b.count.compareTo(a.count));
}

class _ReactionGroup {
  const _ReactionGroup({
    required this.emoji,
    required this.count,
    required this.containsCurrentUser,
  });

  final String emoji;
  final int count;
  final bool containsCurrentUser;
}

// ---------------------------------------------------------------------------
// Reaction badge shown below message bubble
// ---------------------------------------------------------------------------

class _MessageReactionsBadge extends StatelessWidget {
  const _MessageReactionsBadge({
    required this.emojis,
    required this.totalCount,
  });

  final List<String> emojis;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emojisLabel = emojis.join(' ');
    final countLabel = totalCount > 1 ? ' $totalCount' : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$emojisLabel$countLabel',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scroll-to-bottom FAB
// ---------------------------------------------------------------------------

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: AppLocalizations.of(context)!.chatGoBottom,
        icon: Icon(
          Icons.keyboard_double_arrow_down_rounded,
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit message dialog
// ---------------------------------------------------------------------------

class _EditChatMessageDialog extends StatefulWidget {
  const _EditChatMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditChatMessageDialog> createState() => _EditChatMessageDialogState();
}

class _EditChatMessageDialogState extends State<_EditChatMessageDialog> {
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
      title: Text(AppLocalizations.of(context)!.chatEditMessageTitle),
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
          child: Text(AppLocalizations.of(context)!.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, t);
          },
          child: Text(AppLocalizations.of(context)!.commonSave),
        ),
      ],
    );
  }
}
