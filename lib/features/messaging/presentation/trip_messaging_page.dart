import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/auth/auth_gate.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/messaging/chat_controller/firestore_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/messaging/presentation/chat_builders.dart';
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

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
  }

  @override
  void dispose() {
    final tripId = _presenceTripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(_notificationCenter.clearOpenChannel(tripId: tripId));
    }
    super.dispose();
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

    void handleLongPress(
      BuildContext ctx,
      Message message, {
      required int index,
      required LongPressStartDetails details,
    }) {
      unawaited(
        showMessageOptions(
          ctx,
          message,
          isMine: myUid != null && message.authorId == myUid,
          myUid: myUid,
          onSetReaction: (msgId, emoji) => repo.setMyReaction(
            tripId: trip.id,
            messageId: msgId,
            emoji: emoji,
            scope: scope,
          ),
          onRemoveReaction: (msgId) => repo.removeMyReaction(
            tripId: trip.id,
            messageId: msgId,
            scope: scope,
          ),
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
        ),
      );
    }

    void handleSecondaryTap(
      BuildContext ctx,
      Message message, {
      required int index,
      TapUpDetails? details,
    }) {
      unawaited(
        showMessageOptions(
          ctx,
          message,
          isMine: myUid != null && message.authorId == myUid,
          myUid: myUid,
          onSetReaction: (msgId, emoji) => repo.setMyReaction(
            tripId: trip.id,
            messageId: msgId,
            emoji: emoji,
            scope: scope,
          ),
          onRemoveReaction: (msgId) => repo.removeMyReaction(
            tripId: trip.id,
            messageId: msgId,
            scope: scope,
          ),
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
        return FlyerChatTextMessage(
          message: message,
          index: index,
          constraints: BoxConstraints(maxWidth: maxWidth),
        );
      },
      chatMessageBuilder: (ctx, message, index, animation, child,
          {isRemoved, required isSentByMe, groupStatus}) {
        final isFirst = groupStatus?.isFirst ?? true;
        final isLast = groupStatus?.isLast ?? true;
        final showAvatar = !isSentByMe && isLast && isRemoved != true;
        final showUsername = !isSentByMe && isFirst && isRemoved != true;
        return ChatMessage(
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
          child: child,
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
        return Composer(
          hintText: l10n.chatMessageHint,
          maxLines: 5,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
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
              resolveUser: resolveUser,
              builders: _builders!,
              onMessageSend: (text) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                unawaited(
                  repo
                      .sendMessage(
                        tripId: trip.id,
                        text: text,
                        scope: scope,
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
              onMessageLongPress: handleLongPress,
              onMessageSecondaryTap: handleSecondaryTap,
              timeFormat: DateFormat.Hm(localeTag),
            ),
          ),
        ],
      ),
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
