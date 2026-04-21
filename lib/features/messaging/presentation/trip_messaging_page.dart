import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planzers/features/auth/auth_gate.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/core/notifications/notification_center_repository.dart';
import 'package:planzers/core/notifications/notification_channel.dart';
import 'package:planzers/features/messaging/data/trip_message.dart';
import 'package:planzers/features/messaging/data/trip_message_reaction.dart';
import 'package:planzers/features/messaging/data/trip_messages_repository.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Trip-scoped text chat; history is visible to all current [Trip] members.
class TripMessagingPage extends ConsumerStatefulWidget {
  const TripMessagingPage({super.key});

  @override
  ConsumerState<TripMessagingPage> createState() => _TripMessagingPageState();
}

class _TripMessagingPageState extends ConsumerState<TripMessagingPage> {
  static const List<String> _quickReactionEmojis = <String>[
    '👍',
    '❤️',
    '😂',
    '😮',
    '🙏',
  ];

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final NotificationCenterRepository _notificationCenter;
  bool _sending = false;
  String? _selectedMessageId;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
  }

  @override
  void dispose() {
    final tripId = _presenceTripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(
        _notificationCenter.clearOpenChannel(
              tripId: tripId,
            ),
      );
    }
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

  Future<void> _scrollToBottomAnimated() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _markMessagesAsReadIfNeeded({
    required String tripId,
    required List<TripMessage> messages,
  }) {
    if (!_isMessagingTabCurrentlyVisible()) return;
    final latestSeenAt = DateTime.now().toUtc();
    final lastMarked = _lastReadMarkedAt;
    if (lastMarked != null &&
        latestSeenAt.difference(lastMarked) < const Duration(seconds: 2)) {
      return;
    }
    _lastReadMarkedAt = latestSeenAt;
    unawaited(
      _notificationCenter.markReadUpTo(
        tripId: tripId,
        channel: TripNotificationChannel.messages,
        timestamp: latestSeenAt,
      ),
    );
  }

  void _syncPresenceIfNeeded(String tripId) {
    if (!_isMessagingTabCurrentlyVisible()) return;
    final now = DateTime.now().toUtc();
    final sameTrip = _presenceTripId == tripId;
    final shouldPing = !sameTrip ||
        _lastPresencePingAt == null ||
        now.difference(_lastPresencePingAt!) > const Duration(seconds: 25);
    if (!shouldPing) return;
    _presenceTripId = tripId;
    _lastPresencePingAt = now;
    unawaited(
      _notificationCenter.setOpenChannel(
            tripId: tripId,
            channel: TripNotificationChannel.messages,
          ),
    );
  }

  bool _isMessagingTabCurrentlyVisible() {
    try {
      final path = GoRouterState.of(context).uri.path;
      return path.endsWith('/messages');
    } catch (_) {
      return false;
    }
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

  Future<String?> _pickEmoji() async {
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
                noRecents: const Text('Aucun emoji recent'),
              ),
              categoryViewConfig: const CategoryViewConfig(
                iconColor: Colors.grey,
                iconColorSelected: Colors.blue,
                indicatorColor: Colors.blue,
              ),
              bottomActionBarConfig: const BottomActionBarConfig(
                showBackspaceButton: false,
                showSearchViewButton: true,
              ),
              searchViewConfig: const SearchViewConfig(
                buttonIconColor: Colors.blue,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reactToMessage({
    required String tripId,
    required TripMessage message,
    required List<TripMessageReaction> reactions,
  }) async {
    final myUid = ref.read(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur non connecte')),
      );
      return;
    }

    final selectedEmoji = await _pickEmoji();
    if (selectedEmoji == null || !mounted) return;
    await _setReactionWithEmoji(
      tripId: tripId,
      message: message,
      reactions: reactions,
      selectedEmoji: selectedEmoji,
    );
  }

  Future<void> _setReactionWithEmoji({
    required String tripId,
    required TripMessage message,
    required List<TripMessageReaction> reactions,
    required String selectedEmoji,
  }) async {
    final myUid = ref.read(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur non connecte')),
      );
      return;
    }

    final currentReaction = reactions
        .where((r) => r.userId == myUid)
        .cast<TripMessageReaction?>()
        .firstWhere((r) => r != null, orElse: () => null);
    final repository = ref.read(tripMessagesRepositoryProvider);
    try {
      if (currentReaction?.emoji == selectedEmoji) {
        await repository.removeMyReaction(
          tripId: tripId,
          messageId: message.id,
        );
      } else {
        await repository.setMyReaction(
          tripId: tripId,
          messageId: message.id,
          emoji: selectedEmoji,
        );
      }
      _clearSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reaction impossible : $e')),
      );
    }
  }

  /// Returns `true` if the message was updated.
  Future<bool> _editMessage(String tripId, TripMessage message) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditTripMessageDialog(initialText: message.text),
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
    _syncPresenceIfNeeded(trip.id);
    final myUid = ref.watch(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    final messagesAsync = ref.watch(tripMessagesStreamProvider(trip.id));
    final reactionsAsync = ref.watch(tripMessageReactionsStreamProvider(trip.id));

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
            _markMessagesAsReadIfNeeded(tripId: trip.id, messages: messages);
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

            return reactionsAsync.when(
              data: (reactionsByMessage) {
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
                                    final ok = await _deleteMessage(
                                      trip.id,
                                      selected,
                                    );
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
                                      'Aucun message pour l’instant. '
                                      'Écris le premier pour lancer la discussion.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyLarge,
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
                                      return _MessageDayPill(
                                          label: entry.dayLabel!);
                                    }
                                    final m = entry.message!;
                                    final isMine =
                                        myUid != null && m.authorId == myUid;
                                    final isSelected = m.id == _selectedMessageId;
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
                                    final reactions = reactionsByMessage[m.id] ??
                                        const <TripMessageReaction>[];
                                    final groupedReactions =
                                        _groupReactions(reactions, myUid: myUid);
                                    final previousMessage = index > 0
                                        ? chatEntries[index - 1].message
                                        : null;
                                    final isPreviousMessageSameDay =
                                        previousMessage != null &&
                                            DateUtils.isSameDay(
                                              previousMessage.createdAt.toLocal(),
                                              m.createdAt.toLocal(),
                                            );
                                    final previousMessageReactions =
                                        previousMessage == null
                                            ? const <TripMessageReaction>[]
                                            : (reactionsByMessage[
                                                      previousMessage.id] ??
                                                  const <TripMessageReaction>[]);
                                    final extraTopCardMargin =
                                        isPreviousMessageSameDay &&
                                                previousMessageReactions
                                                    .isNotEmpty
                                            ? 6.0
                                            : 0.0;
                                    final totalReactionCount =
                                        groupedReactions.fold<int>(
                                      0,
                                      (sum, group) => sum + group.count,
                                    );
                                    final reactionEmojis = groupedReactions
                                        .map((group) => group.emoji)
                                        .toList();
                                    final hasMyReaction = groupedReactions.any(
                                      (group) => group.containsCurrentUser,
                                    );

                                    return Align(
                                      alignment: isMine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: IntrinsicWidth(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: math.min(
                                              MediaQuery.sizeOf(context).width *
                                                  0.85,
                                              560,
                                            ),
                                          ),
                                          child: GestureDetector(
                                          onLongPress: () {
                                            setState(
                                                () => _selectedMessageId = m.id);
                                          },
                                          onSecondaryTap: pointerSelect
                                              ? () => setState(
                                                    () =>
                                                        _selectedMessageId = m.id,
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
                                                        _selectedMessageId =
                                                            m.id);
                                                  }
                                                }
                                              : null,
                                          behavior: HitTestBehavior.opaque,
                                          child: MouseRegion(
                                            cursor: pointerSelect &&
                                                    _selectedMessageId == null
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
                                                        groupedReactions.isNotEmpty
                                                            ? 16
                                                            : 0,
                                                  ),
                                                  child: Card(
                                                    margin:
                                                        EdgeInsets.fromLTRB(
                                                      2,
                                                      2 + extraTopCardMargin,
                                                      2,
                                                      2,
                                                    ),
                                                    elevation:
                                                        isSelected ? 0 : null,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      side: isSelected
                                                          ? BorderSide(
                                                              color: Theme.of(
                                                                      context)
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
                                                            .withValues(
                                                                alpha: 0.55)
                                                        : (isMine
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primaryContainer
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .surfaceContainerHighest),
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .fromLTRB(10, 8, 10, 2),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          if (!isMine) ...[
                                                            Text(
                                                              label,
                                                              maxLines: 1,
                                                              overflow: TextOverflow
                                                                  .ellipsis,
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .labelMedium
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                                height: 3),
                                                          ],
                                                          Stack(
                                                            children: [
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  right: 86,
                                                                ),
                                                                child:
                                                                    _TripMessageLinkedText(
                                                                  text: m.text,
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .bodyMedium,
                                                                ),
                                                              ),
                                                              Positioned(
                                                                right: 0,
                                                                bottom: 0,
                                                                child: Text(
                                                                  timeLine,
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .labelSmall
                                                                      ?.copyWith(
                                                                        color: Theme.of(
                                                                                context)
                                                                            .colorScheme
                                                                            .onSurfaceVariant,
                                                                      ),
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
                                                    child:
                                                        _MessageReactionsBadge(
                                                      emojis: reactionEmojis,
                                                      totalCount:
                                                          totalReactionCount,
                                                      highlighted: hasMyReaction,
                                                    ),
                                                  ),
                                                if (isSelected)
                                                  Positioned(
                                                    top: 0,
                                                    child:
                                                        _InlineMessageQuickReactionBar(
                                                      emojis:
                                                          _quickReactionEmojis,
                                                      onEmojiTap: (emoji) =>
                                                          _setReactionWithEmoji(
                                                        tripId: trip.id,
                                                        message: m,
                                                        reactions: reactions,
                                                        selectedEmoji: emoji,
                                                      ),
                                                      onMoreTap: () =>
                                                          _reactToMessage(
                                                        tripId: trip.id,
                                                        message: m,
                                                        reactions: reactions,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if (messages.isNotEmpty)
                                Positioned(
                                  right: 14,
                                  bottom: 14,
                                  child: _ScrollToBottomButton(
                                    onPressed: () =>
                                        unawaited(_scrollToBottomAnimated()),
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
                                  onSubmitted:
                                      _sending ? null : (_) => _send(trip.id),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed:
                                    _sending ? null : () => _send(trip.id),
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
                    'Erreur reactions : $e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
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
  });

  final String text;
  final TextStyle? style;

  @override
  State<_TripMessageLinkedText> createState() => _TripMessageLinkedTextState();
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 2),
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
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => unawaited(onEmojiTap(emoji)),
                  icon: Text(
                    emoji,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  tooltip: 'Reagir avec $emoji',
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: () => unawaited(onMoreTap()),
              icon: const Icon(Icons.add),
              tooltip: 'Plus d’emoticones',
            ),
          ],
        ),
      ),
    );
  }
}

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
        containsCurrentUser:
            current.containsCurrentUser || containsCurrentUser,
      );
    }
  }

  final groups = byEmoji.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return groups;
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

class _MessageReactionsBadge extends StatelessWidget {
  const _MessageReactionsBadge({
    required this.emojis,
    required this.totalCount,
    required this.highlighted,
  });

  final List<String> emojis;
  final int totalCount;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emojisLabel = emojis.join(' ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            highlighted ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$emojisLabel $totalCount',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Aller en bas',
        icon: const Icon(Icons.keyboard_double_arrow_down_rounded),
      ),
    );
  }
}

/// Owns its [TextEditingController] for a correct dispose after the dialog
/// route is popped.
class _EditTripMessageDialog extends StatefulWidget {
  const _EditTripMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditTripMessageDialog> createState() => _EditTripMessageDialogState();
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
