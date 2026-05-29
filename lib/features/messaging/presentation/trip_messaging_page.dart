import 'dart:async';

import 'package:cross_cache/cross_cache.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
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
import 'package:planerz/features/messaging/presentation/chat_builders.dart';
import 'package:planerz/features/messaging/presentation/chat_message_text.dart';
import 'package:planerz/features/messaging/presentation/reply_widgets.dart';
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
  final _highlightedMessageId = ValueNotifier<String?>(null);
  final _crossCache = CrossCache();
  bool _isSendingImage = false;

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
      if (_isSendingImage) return;
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > TripMessagesRepository.maxImageBytes) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.chatImageTooLarge)),
        );
        return;
      }

      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(picked.path);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      final replyId = _replyingTo?.id;
      _cancelReply();

      setState(() {
        _isSendingImage = true;
        _builders = null;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await repo.sendImageMessage(
          tripId: trip.id,
          bytes: bytes,
          fileExt: ext,
          scope: scope,
          replyToMessageId: replyId,
        );
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.chatSendImpossible(e.toString()))),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSendingImage = false;
            _builders = null;
          });
        }
      }
    }

    void handleMessageOptions(BuildContext ctx, Message message) {
      unawaited(
        showMessageOptions(
          ctx,
          message,
          isMine: myUid != null && message.authorId == myUid,
          myUid: myUid,
          onSetReaction: setReaction,
          onRemoveReaction: removeReaction,
          onEdit: (msgId, text) => repo.updateMessage(
            tripId: trip.id,
            messageId: msgId,
            text: text,
            scope: scope,
          ),
          onDelete: (msgId) => repo.deleteMessage(
            tripId: trip.id,
            messageId: msgId,
            scope: scope,
          ),
          onReply: _startReply,
        ),
      );
    }

    final localeTag = Localizations.localeOf(context).toString();

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
        final maxWidth =
            isSentByMe ? w - sideMargin : w - avatarSlot - sideMargin;

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
            return FlyerChatImageMessage(
              message: message,
              index: index,
              constraints: BoxConstraints(maxWidth: maxWidth),
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
                left: isSentByMe ? null : 0,
                right: isSentByMe ? 0 : null,
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

        if (!previousHasReactions) return chatMessage;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: chatMessage,
        );
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
        return Composer(
          hintText: l10n.chatMessageHint,
          maxLines: 5,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          attachmentIcon: _isSendingImage
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.image_outlined),
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

    return Scaffold(
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
          Expanded(
            child: Chat(
              currentUserId: myUid ?? '',
              chatController: chatController,
              crossCache: _crossCache,
              resolveUser: resolveUser,
              builders: _builders!,
              onAttachmentTap: _isSendingImage ? null : handleAttachmentTap,
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
                  handleMessageOptions(ctx, msg),
              onMessageSecondaryTap: (ctx, msg, {required index, details}) =>
                  handleMessageOptions(ctx, msg),
              timeFormat: DateFormat.Hm(localeTag),
            ),
          ),
        ],
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
