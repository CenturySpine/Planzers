import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/auth/auth_gate.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/messaging/presentation/chat_widget.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

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
  @override
  Widget build(BuildContext context) {
    return const TripThreadMessagingPage(scope: TripMessageThreadScope.main());
  }
}

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

class _TripThreadMessagingPageState extends ConsumerState<TripThreadMessagingPage> {
  static const int _olderPageSize = 50;

  late final NotificationCenterRepository _notificationCenter;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;
  String? _activeTripId;

  QueryDocumentSnapshot<Map<String, dynamic>>? _olderCursor;
  bool _hasMoreOlder = true;
  bool _loadingOlder = false;
  final Map<String, TripMessage> _olderMessagesById = <String, TripMessage>{};
  final Map<String, List<TripMessageReaction>> _olderReactionsByMessage =
      <String, List<TripMessageReaction>>{};

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
      return path.contains('/messages');
    } catch (_) {
      return false;
    }
  }

  void _resetPaginationForTrip(String tripId) {
    _activeTripId = tripId;
    _olderCursor = null;
    _hasMoreOlder = true;
    _loadingOlder = false;
    _olderMessagesById.clear();
    _olderReactionsByMessage.clear();
  }

  Future<void> _loadOlderMessages({
    required String tripId,
    required TripMessagesRepository repo,
  }) async {
    if (_loadingOlder || !_hasMoreOlder) return;
    final startAfterDoc = _olderCursor;
    if (startAfterDoc == null) return;

    setState(() => _loadingOlder = true);
    try {
      final page = await repo.fetchOlderChatPage(
        tripId: tripId,
        pageSize: _olderPageSize,
        startAfterDoc: startAfterDoc,
        scope: widget.scope,
      );
      if (!mounted) return;
      setState(() {
        for (final message in page.data.messages) {
          _olderMessagesById[message.id] = message;
        }
        _olderReactionsByMessage.addAll(page.data.reactionsByMessage);
        _olderCursor = page.nextCursor;
        _hasMoreOlder = page.hasMore && page.nextCursor != null;
        _loadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    _syncPresenceIfNeeded(trip.id);

    final scope = widget.scope;
    final myUid = ref.watch(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
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
    final participants =
        ref.watch(tripParticipantsStreamProvider(trip.id)).asData?.value ?? [];
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));

    final chatDataAsync = ref.watch(
      tripChatDataScopedStreamProvider(
        TripMessageThreadRequest(tripId: trip.id, scope: scope),
      ),
    );
    final repo = ref.read(tripMessagesRepositoryProvider);
    final canAccessAdminThread = trip.isTripAdmin(myUid);
    if (_activeTripId != trip.id) {
      _resetPaginationForTrip(trip.id);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          if (canAccessAdminThread)
            _TripMessagingThreadTabs(
              selectedScope: scope,
              onSelectMain: () => context.go('/trips/${trip.id}/messages'),
              onSelectAdmin: () => context.go('/trips/${trip.id}/messages/admin'),
            ),
          Expanded(
            child: chatDataAsync.when(
              data: (chatData) {
          if (_olderCursor == null) {
            _olderCursor = chatData.oldestLoadedDoc;
            _hasMoreOlder = chatData.hasPotentialOlder && _olderCursor != null;
          }

          final mergedMessagesById = <String, TripMessage>{
            ..._olderMessagesById,
            for (final m in chatData.messages) m.id: m,
          };
          final mergedMessages = mergedMessagesById.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final mergedReactions = <String, List<TripMessageReaction>>{
            ..._olderReactionsByMessage,
            ...chatData.reactionsByMessage,
          };

          _markMessagesAsReadIfNeeded(tripId: trip.id, messages: mergedMessages);

          final labelUserIds = <String>{
            for (final m in participants)
              if (m.userId != null && m.userId!.trim().isNotEmpty) m.userId!.trim(),
            for (final m in mergedMessages)
              if (m.authorId.trim().isNotEmpty) m.authorId.trim(),
          }.toList();
          final usersIdsKey = stableUsersIdsKey(labelUserIds);

          final usersAsync = ref.watch(
            usersDataByIdsKeyStreamProvider(usersIdsKey),
          );
                return usersAsync.when(
                  data: (userDocs) {
                    return ChatWidget(
                      currentUserId: myUid,
                      messages: mergedMessages,
                      reactions: mergedReactions,
                      userDocs: userDocs,
                      authorLabels: memberLabels,
                      showUserBadges: true,
                      hasMoreOlder: _hasMoreOlder,
                      loadingOlder: _loadingOlder,
                      onLoadOlder: () => _loadOlderMessages(tripId: trip.id, repo: repo),
                      onSend: (text) => repo.sendMessage(
                        tripId: trip.id,
                        text: text,
                        scope: scope,
                      ),
                      onUpdate: (id, text) => repo.updateMessage(
                        tripId: trip.id,
                        messageId: id,
                        text: text,
                        scope: scope,
                      ),
                      onDelete: (id) => repo.deleteMessage(
                        tripId: trip.id,
                        messageId: id,
                        scope: scope,
                      ),
                      onSetReaction: (id, emoji) => repo.setMyReaction(
                        tripId: trip.id,
                        messageId: id,
                        emoji: emoji,
                        scope: scope,
                      ),
                      onRemoveReaction: (id) => repo.removeMyReaction(
                        tripId: trip.id,
                        messageId: id,
                        scope: scope,
                      ),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erreur utilisateurs : $e',
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
        ],
      ),
    );
  }
}

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
