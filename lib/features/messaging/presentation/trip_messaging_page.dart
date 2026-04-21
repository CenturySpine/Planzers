import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/auth/auth_gate.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/core/notifications/notification_center_repository.dart';
import 'package:planzers/core/notifications/notification_channel.dart';
import 'package:planzers/features/messaging/data/trip_message.dart';
import 'package:planzers/features/messaging/data/trip_messages_repository.dart';
import 'package:planzers/features/messaging/presentation/chat_widget.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Trip-scoped text chat; history is visible to all current [Trip] members.
///
/// This page owns trip-level concerns (presence, read marks, navigation
/// awareness) and delegates all chat UI to [ChatWidget].
class TripMessagingPage extends ConsumerStatefulWidget {
  const TripMessagingPage({super.key});

  @override
  ConsumerState<TripMessagingPage> createState() => _TripMessagingPageState();
}

class _TripMessagingPageState extends ConsumerState<TripMessagingPage> {
  late final NotificationCenterRepository _notificationCenter;
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
      unawaited(_notificationCenter.clearOpenChannel(tripId: tripId));
    }
    super.dispose();
  }

  void _markMessagesAsReadIfNeeded({
    required String tripId,
    required List<TripMessage> messages,
  }) {
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
      return path.endsWith('/messages');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    _syncPresenceIfNeeded(trip.id);

    final myUid = ref.watch(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    final messagesAsync = ref.watch(tripMessagesStreamProvider(trip.id));
    final reactionsAsync = ref.watch(tripMessageReactionsStreamProvider(trip.id));
    final repo = ref.read(tripMessagesRepositoryProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: messagesAsync.when(
        data: (messages) {
          _markMessagesAsReadIfNeeded(tripId: trip.id, messages: messages);

          final labelUserIds = <String>{
            for (final id in trip.memberIds)
              if (id.trim().isNotEmpty) id.trim(),
            for (final m in messages)
              if (m.authorId.trim().isNotEmpty) m.authorId.trim(),
          }.toList();

          return reactionsAsync.when(
            data: (reactions) => StreamBuilder<Map<String, Map<String, dynamic>>>(
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
                return ChatWidget(
                  currentUserId: myUid,
                  messages: messages,
                  reactions: reactions,
                  userDocs: userDocs,
                  authorLabels: authorLabels,
                  showUserBadges: true,
                  onSend: (text) => repo.sendMessage(
                    tripId: trip.id,
                    text: text,
                  ),
                  onUpdate: (id, text) => repo.updateMessage(
                    tripId: trip.id,
                    messageId: id,
                    text: text,
                  ),
                  onDelete: (id) => repo.deleteMessage(
                    tripId: trip.id,
                    messageId: id,
                  ),
                  onSetReaction: (id, emoji) => repo.setMyReaction(
                    tripId: trip.id,
                    messageId: id,
                    emoji: emoji,
                  ),
                  onRemoveReaction: (id) => repo.removeMyReaction(
                    tripId: trip.id,
                    messageId: id,
                  ),
                );
              },
            ),
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
    );
  }
}
