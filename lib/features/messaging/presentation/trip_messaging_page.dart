import 'dart:async';
import 'dart:math' as math;

import 'package:cross_cache/cross_cache.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/features/auth/auth_gate.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/messaging/chat_controller/firestore_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/core/presentation/message_selection_action_bar.dart';
import 'package:planerz/features/messaging/presentation/chat_builders.dart';
import 'package:planerz/features/messaging/presentation/trip_chat_composer.dart';
import 'package:planerz/features/messaging/presentation/chat_image_viewer.dart';
import 'package:planerz/features/messaging/presentation/chat_message_text.dart';
import 'package:planerz/features/messaging/presentation/reply_widgets.dart';
import 'package:planerz/features/messaging/presentation/whatsapp_emoji_picker.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Trip-scoped text chat — main thread only.
class TripMessagingPage extends ConsumerStatefulWidget {
  const TripMessagingPage({super.key});

  @override
  ConsumerState<TripMessagingPage> createState() => _TripMessagingPageState();
}

class _TripMessagingPageState extends ConsumerState<TripMessagingPage> {
  @override
  Widget build(BuildContext context) {
    return const TripThreadMessagingPage(scope: TripMessageThreadScope.main());
  }
}

/// Generic trip messaging page for any [TripMessageThreadScope].
class TripThreadMessagingPage extends ConsumerStatefulWidget {
  const TripThreadMessagingPage({
    super.key,
    required this.scope,
  });

  final TripMessageThreadScope scope;

  @override
  ConsumerState<TripThreadMessagingPage> createState() =>
      _TripThreadMessagingPageState();
}

class _TripThreadMessagingPageState
    extends ConsumerState<TripThreadMessagingPage> {
  late final NotificationCenterRepository _notificationCenter;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;

  // Cached so that Chat.didUpdateWidget() is not triggered on every parent
  // rebuild: Builders uses identical() for function equality (Freezed), so new
  // closures per build() would always compare unequal and force a Chat rebuild.
  Builders? _builders;

  // Reply state — nulled out whenever _replyingTo changes to force a Builders rebuild.
  Message? _replyingTo;
  /// Long-press selection — nulled out when cleared to force a [Builders] rebuild.
  String? _selectedMessageId;
  final _highlightedMessageId = ValueNotifier<String?>(null);
  final _crossCache = CrossCache();

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
  }

  @override
  void dispose() {
    _crossCache.dispose();
    _highlightedMessageId.dispose();
    final tripId = _presenceTripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(_notificationCenter.clearOpenChannel(tripId: tripId));
    }
    super.dispose();
  }

  void _startReply(Message message) {
    setState(() {
      _replyingTo = message;
      _builders = null;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
      _builders = null;
    });
  }

  void _clearMessageSelection() {
    if (_selectedMessageId == null) return;
    setState(() {
      _selectedMessageId = null;
      _builders = null;
    });
  }

  void _selectMessage(Message message) {
    if (message is! TextMessage && message is! ImageMessage) return;
    setState(() {
      _selectedMessageId = message.id;
      _builders = null;
    });
  }

  Message? _findMessageById(String id, List<Message> messages) {
    for (final message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  Future<void> _copySelectedMessage(Message message) async {
    if (message is! TextMessage) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.chatCopied)),
    );
  }

  Future<void> _editSelectedMessage(Message message) async {
    if (message is! TextMessage) return;
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final scope = widget.scope;
    final repo = ref.read(tripMessagesRepositoryProvider);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => EditTextDialog(
        initialText: message.text,
        title: l10n.chatEditMessageTitle,
        maxLength: TripMessagesRepository.maxTextLength,
      ),
    );
    if (newText == null || !mounted) return;
    try {
      await repo.updateMessage(
        tripId: trip.id,
        messageId: message.id,
        text: newText,
        scope: scope,
      );
      _clearMessageSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatEditImpossible(e.toString()))),
      );
    }
  }

  Future<void> _deleteSelectedMessage(Message message) async {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final scope = widget.scope;
    final repo = ref.read(tripMessagesRepositoryProvider);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.chatDeleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await repo.deleteMessage(
        tripId: trip.id,
        messageId: message.id,
        scope: scope,
      );
      _clearMessageSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatDeleteImpossible(e.toString()))),
      );
    }
  }

  void _markMessagesAsReadIfNeeded(String tripId) {
    if (!_isMessagingTabCurrentlyVisible()) return;
    final now = DateTime.now().toUtc();
    final lastMarked = _lastReadMarkedAt;
    if (lastMarked != null &&
        now.difference(lastMarked) < const Duration(seconds: 2)) {
      return;
    }
    _lastReadMarkedAt = now;
    unawaited(
      _notificationCenter.markReadUpTo(
        tripId: tripId,
        channel: TripNotificationChannel.messages,
        timestamp: now,
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
      return path.contains('/messages');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scope = widget.scope;

    _syncPresenceIfNeeded(trip.id);

    final myUid = ref.watch(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;

    // Access control
    if (scope.isAdmin && !trip.isTripAdmin(myUid)) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.tripNotFoundOrNoAccess,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final repo = ref.read(tripMessagesRepositoryProvider);
    final request = TripMessageThreadRequest(tripId: trip.id, scope: scope);
    final chatController = ref.watch(firestoreChatControllerProvider(request));
    final canAccessAdminThread = trip.isTripAdmin(myUid);

    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    final memberPhotoUrls = ref.watch(tripMemberPhotoUrlsProvider(trip.id));

    _markMessagesAsReadIfNeeded(trip.id);

    Future<User?> resolveUser(String userId) async {
      final photoUrl = memberPhotoUrls[userId];
      return User(
        id: userId,
        name: memberLabels[userId] ?? l10n.roleParticipant,
        imageSource:
            (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
      );
    }

    Future<void> setReaction(String messageId, String emoji) async {
      final uid = myUid;
      if (uid != null) {
        await chatController.applyLocalReaction(
          messageId: messageId,
          userId: uid,
          emoji: emoji,
        );
      }
      await repo.setMyReaction(
        tripId: trip.id,
        messageId: messageId,
        emoji: emoji,
        scope: scope,
      );
    }

    Future<void> removeReaction(String messageId) async {
      final uid = myUid;
      if (uid != null) {
        await chatController.applyLocalReaction(
          messageId: messageId,
          userId: uid,
        );
      }
      await repo.removeMyReaction(
        tripId: trip.id,
        messageId: messageId,
        scope: scope,
      );
    }

    String replyPreviewText(Message message) {
      return switch (message) {
        TextMessage(:final text) => text,
        ImageMessage(:final text) when text != null && text.trim().isNotEmpty =>
          text.trim(),
        ImageMessage() => l10n.chatQuotedImage,
        _ => '',
      };
    }

    Future<void> handleAttachmentTap() async {
      final uid = myUid;
      if (uid == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 92,
      );
      if (picked == null || !context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);

      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      if (bytes.length > TripMessagesRepository.maxImageBytes) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.chatImageTooLarge)),
        );
        return;
      }

      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(picked.path);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      final replyId = _replyingTo?.id;
      _cancelReply();

      final messageId = repo.newImageMessageId(trip.id);
      final dimensions = await repo.decodeImageDimensions(bytes);
      if (!context.mounted) return;

      final optimisticMessage = ImageMessage(
        id: messageId,
        authorId: uid,
        createdAt: DateTime.now().toUtc(),
        source: messageId,
        status: MessageStatus.sending,
        width: dimensions?.$1,
        height: dimensions?.$2,
        replyToMessageId: replyId,
      );
      await chatController.insertOptimisticImage(
        message: optimisticMessage,
        previewBytes: bytes,
      );
      if (!context.mounted) return;

      try {
        await repo.sendImageMessage(
          tripId: trip.id,
          messageId: messageId,
          bytes: bytes,
          fileExt: ext,
          scope: scope,
          replyToMessageId: replyId,
          onUploadProgress: (progress) {
            chatController.updateUploadProgress(messageId, progress);
          },
        );
      } catch (e) {
        await chatController.markOptimisticImageFailed(messageId);
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.chatSendImpossible(e.toString()))),
        );
      }
    }

    final localeTag = Localizations.localeOf(context).toString();

    final selectedMessage = _selectedMessageId == null
        ? null
        : _findMessageById(_selectedMessageId!, chatController.messages);
    if (_selectedMessageId != null && selectedMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearMessageSelection();
      });
    }
    final selectedIsMine = selectedMessage != null &&
        myUid != null &&
        selectedMessage.authorId == myUid;

    _builders ??= Builders(
      textMessageBuilder: (ctx, message, index,
              {required isSentByMe, groupStatus}) {
        const avatarSlot = 40.0; // avatar 32px + right padding 8px
        const sideMargin = 48.0;
        final w = MediaQuery.sizeOf(ctx).width;
        final maxWidth =
            isSentByMe ? w - sideMargin : w - avatarSlot - sideMargin;

        // Build reply preview widget if this message is a reply.
        Widget? replyTopWidget;
        final replyId = message.replyToMessageId;
        if (replyId != null) {
          Message? original;
          for (final m in chatController.messages) {
            if (m.id == replyId) {
              original = m;
              break;
            }
          }
          if (original != null) {
            replyTopWidget = QuotedMessageSnippet(
              authorId: original.authorId,
              text: replyPreviewText(original),
              tripId: trip.id,
              onTap: () {
                _highlightedMessageId.value = replyId;
                unawaited(
                  chatController.scrollToMessage(replyId, alignment: 0.3),
                );
                Future.delayed(const Duration(milliseconds: 1200), () {
                  _highlightedMessageId.value = null;
                });
              },
            );
          }
        }

        final radius = _groupedBubbleRadius(
          isSentByMe: isSentByMe,
          isFirst: groupStatus?.isFirst ?? true,
          isLast: groupStatus?.isLast ?? true,
          hasTopWidget: replyTopWidget != null,
        );

        return ValueListenableBuilder<String?>(
          valueListenable: _highlightedMessageId,
          builder: (ctx2, highlightedId, _) {
            final scheme = Theme.of(ctx2).colorScheme;
            final textTheme = Theme.of(ctx2).textTheme;
            final markdownText = embedPlainUrlsAsMarkdown(message.text);
            final displayMessage = markdownText == message.text
                ? message
                : message.copyWith(text: markdownText);
            return FlyerChatTextMessage(
              message: displayMessage,
              index: index,
              constraints: BoxConstraints(maxWidth: maxWidth),
              borderRadius: radius,
              topWidget: replyTopWidget,
              sentBackgroundColor: highlightedId == message.id
                  ? scheme.tertiaryContainer
                  : scheme.primaryContainer,
              receivedBackgroundColor: highlightedId == message.id
                  ? scheme.tertiaryContainer
                  : scheme.surfaceContainerHighest,
              sentTextStyle: textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
              sentLinksColor: scheme.primary,
              receivedLinksColor: scheme.primary,
              linksDecoration: TextDecoration.underline,
              onLinkTap: (url, _) => unawaited(openExternalUrl(ctx2, url)),
              timeStyle: isSentByMe
                  ? textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.6),
                    )
                  : null,
            );
          },
        );
      },
      imageMessageBuilder: (ctx, message, index,
          {required isSentByMe, groupStatus}) {
        const avatarSlot = 40.0;
        const sideMargin = 48.0;
        final w = MediaQuery.sizeOf(ctx).width;
        final bubbleMaxWidth =
            isSentByMe ? w - sideMargin : w - avatarSlot - sideMargin;
        final imageMaxWidth = math.min(
          bubbleMaxWidth,
          chatImageBubbleMaxExtent,
        );
        final imageConstraints = BoxConstraints(
          maxWidth: imageMaxWidth,
          maxHeight: chatImageBubbleMaxExtent,
        );

        Widget? replyTopWidget;
        final replyId = message.replyToMessageId;
        if (replyId != null) {
          Message? original;
          for (final m in chatController.messages) {
            if (m.id == replyId) {
              original = m;
              break;
            }
          }
          if (original != null) {
            replyTopWidget = QuotedMessageSnippet(
              authorId: original.authorId,
              text: replyPreviewText(original),
              tripId: trip.id,
              onTap: () {
                _highlightedMessageId.value = replyId;
                unawaited(
                  chatController.scrollToMessage(replyId, alignment: 0.3),
                );
                Future.delayed(const Duration(milliseconds: 1200), () {
                  _highlightedMessageId.value = null;
                });
              },
            );
          }
        }

        final radius = _groupedBubbleRadius(
          isSentByMe: isSentByMe,
          isFirst: groupStatus?.isFirst ?? true,
          isLast: groupStatus?.isLast ?? true,
          hasTopWidget: replyTopWidget != null,
        );

        final previewBytes = chatController.optimisticPreviewBytes(message.id);
        final localPreview = previewBytes != null
            ? MemoryImage(previewBytes)
            : null;

        return ValueListenableBuilder<String?>(
          valueListenable: _highlightedMessageId,
          builder: (ctx2, highlightedId, _) {
            return FlyerChatImageMessage(
              message: message,
              index: index,
              customImageProvider: localPreview,
              constraints: imageConstraints,
              borderRadius: radius,
              topWidget: replyTopWidget,
              placeholderColor: highlightedId == message.id
                  ? Theme.of(ctx2).colorScheme.tertiaryContainer
                  : null,
            );
          },
        );
      },
      chatMessageBuilder: (ctx, message, index, animation, child,
          {isRemoved, required isSentByMe, groupStatus}) {
        final isFirst = groupStatus?.isFirst ?? true;
        final isLast = groupStatus?.isLast ?? true;
        final showAvatar = !isSentByMe && isLast && isRemoved != true;
        final showUsername = !isSentByMe && isFirst && isRemoved != true;
        final reactions = message.reactions;
        final showReactions = isRemoved != true &&
            reactions != null &&
            reactions.isNotEmpty;

        final messages = chatController.messages;
        final previousHasReactions = index > 0 &&
            _messageHasReactions(messages[index - 1]);

        // Pill sits in the bubble's bottom padding (overlap without layout overflow).
        // Negative [Positioned.bottom] draws outside the Stack and gets clipped by
        // the next list item — same fix as pre-migration extraTopCardMargin.
        final Widget bubbleChild;
        if (showReactions) {
          bubbleChild = Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: child,
              ),
              Positioned(
                bottom: 0,
                left: isSentByMe ? null : 8,
                right: isSentByMe ? 8 : null,
                child: MessageReactionsBadge(reactions: reactions),
              ),
            ],
          );
        } else {
          bubbleChild = child;
        }

        final chatMessage = ChatMessage(
          message: message,
          index: index,
          animation: animation,
          isRemoved: isRemoved,
          groupStatus: groupStatus,
          leadingWidget: !isSentByMe
              ? (showAvatar
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChatProfileBadge(
                          userId: message.authorId,
                          tripId: trip.id,
                        ),
                    )
                  : const SizedBox(width: 40))
              : null,
          topWidget: showUsername
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 48),
                  child: ChatUserLabel(
                    userId: message.authorId,
                    tripId: trip.id,
                  ),
                )
              : null,
          child: bubbleChild,
        );

        final isSelected = _selectedMessageId == message.id;
        Widget result = chatMessage;
        if (!previousHasReactions) {
          result = chatMessage;
        } else {
          result = Padding(
            padding: const EdgeInsets.only(top: 6),
            child: chatMessage,
          );
        }
        if (isSelected) {
          result = wrapMessageWithQuickReactionBar(
            isSentByMe: isSentByMe,
            onEmojiTap: (emoji) async {
              try {
                if (currentUserReactionEmoji(message, myUid) == emoji) {
                  await removeReaction(message.id);
                } else {
                  await setReaction(message.id, emoji);
                }
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(l10n.chatReactionImpossible(e.toString())),
                  ),
                );
              }
            },
            onMoreTap: () async {
              final selected = await showPlanerzEmojiReactionPicker(ctx);
              if (selected == null || !ctx.mounted) return;
              try {
                if (currentUserReactionEmoji(message, myUid) == selected) {
                  await removeReaction(message.id);
                } else {
                  await setReaction(message.id, selected);
                }
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(l10n.chatReactionImpossible(e.toString())),
                  ),
                );
              }
            },
            child: result,
          );
        }
        return result;
      },
      chatAnimatedListBuilder: (ctx, itemBuilder) {
        return ChatAnimatedList(
          itemBuilder: itemBuilder,
          onEndReached: () => chatController.loadOlderPage(
            repo: repo,
            tripId: trip.id,
            scope: scope,
          ),
        );
      },
      composerBuilder: (ctx) {
        final replyTarget = _replyingTo;
        return TripChatComposer(
          hintText: l10n.chatMessageHint,
          maxLines: 5,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          attachmentEnabled: true,
          attachmentIcon: const Icon(Icons.image_outlined),
          topWidget: replyTarget != null
              ? ReplyComposerBanner(
                  authorId: replyTarget.authorId,
                  text: replyPreviewText(replyTarget),
                  tripId: trip.id,
                  onCancel: _cancelReply,
                )
              : null,
        );
      },
    );

    return PopScope(
      canPop: _selectedMessageId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedMessageId != null) _clearMessageSelection();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            if (canAccessAdminThread)
              _TripMessagingThreadTabs(
                selectedScope: scope,
                onSelectMain: () => context.go('/trips/${trip.id}/messages'),
                onSelectAdmin: () =>
                    context.go('/trips/${trip.id}/messages/admin'),
              ),
            if (selectedMessage != null)
              MessageSelectionActionBar(
                onClose: _clearMessageSelection,
                onReply: () {
                  _startReply(selectedMessage);
                  _clearMessageSelection();
                },
                onCopy: selectedMessage is TextMessage
                    ? () => unawaited(_copySelectedMessage(selectedMessage))
                    : null,
                onEdit: selectedIsMine && selectedMessage is TextMessage
                    ? () => _editSelectedMessage(selectedMessage)
                    : null,
                onDelete: selectedIsMine
                    ? () => _deleteSelectedMessage(selectedMessage)
                    : null,
              ),
            Expanded(
              child: Chat(
              currentUserId: myUid ?? '',
              chatController: chatController,
              crossCache: _crossCache,
              resolveUser: resolveUser,
              builders: _builders!,
              onAttachmentTap: handleAttachmentTap,
              onMessageTap: (ctx, message, {required index, required details}) {
                if (_selectedMessageId != null) {
                  setState(() {
                    _selectedMessageId =
                        _selectedMessageId == message.id ? null : message.id;
                    _builders = null;
                  });
                  return;
                }
                if (message is! ImageMessage) return;
                final previewBytes =
                    chatController.optimisticPreviewBytes(message.id);
                unawaited(
                  showChatImageViewer(
                    context: ctx,
                    imageUrl: previewBytes == null ? message.source : null,
                    imageProvider: previewBytes != null
                        ? MemoryImage(previewBytes)
                        : null,
                    crossCache: _crossCache,
                    caption: message.text,
                  ),
                );
              },
              onMessageSend: (text) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                final replyId = _replyingTo?.id;
                _cancelReply();
                unawaited(
                  repo
                      .sendMessage(
                        tripId: trip.id,
                        text: text,
                        scope: scope,
                        replyToMessageId: replyId,
                      )
                      .catchError((Object e) {
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text(l10n.chatSendImpossible(e.toString())),
                      ),
                    );
                  }),
                );
              },
              onMessageLongPress: (ctx, msg, {required index, required details}) =>
                  _selectMessage(msg),
              onMessageSecondaryTap: (ctx, msg, {required index, details}) =>
                  _selectMessage(msg),
              timeFormat: DateFormat.Hm(localeTag),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _messageHasReactions(Message message) {
  final reactions = message.reactions;
  return reactions != null && reactions.isNotEmpty;
}

// ── Bubble corner radius ──────────────────────────────────────────────────────

BorderRadius _groupedBubbleRadius({
  required bool isSentByMe,
  required bool isFirst,
  required bool isLast,
  required bool hasTopWidget,
}) {
  const large = Radius.circular(12);
  const small = Radius.circular(4);
  if (isSentByMe) {
    return BorderRadius.only(
      topLeft: large,
      bottomLeft: large,
      topRight: (isFirst || hasTopWidget) ? large : small,
      bottomRight: isLast ? large : small,
    );
  } else {
    return BorderRadius.only(
      topRight: large,
      bottomRight: large,
      topLeft: (isFirst || hasTopWidget) ? large : small,
      bottomLeft: isLast ? large : small,
    );
  }
}

// ── Thread selector tabs ──────────────────────────────────────────────────────

class _TripMessagingThreadTabs extends StatelessWidget {
  const _TripMessagingThreadTabs({
    required this.selectedScope,
    required this.onSelectMain,
    required this.onSelectAdmin,
  });

  final TripMessageThreadScope selectedScope;
  final VoidCallback onSelectMain;
  final VoidCallback onSelectAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedTabIndex = selectedScope.isAdmin ? 1 : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DefaultTabController(
        length: 2,
        initialIndex: selectedTabIndex,
        child: TabBar(
          onTap: (index) {
            if (index == selectedTabIndex) return;
            if (index == 0) {
              onSelectMain();
              return;
            }
            onSelectAdmin();
          },
          tabs: <Widget>[
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined),
                  const SizedBox(width: 8),
                  Text(l10n.tripMessagingChannelMain),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined),
                  const SizedBox(width: 8),
                  Text(l10n.tripMessagingChannelAdmin),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
