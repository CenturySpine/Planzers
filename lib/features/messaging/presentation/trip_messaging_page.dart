import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/auth/auth_gate.dart';
import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/messaging/presentation/chat_image_send_page.dart';
import 'package:planerz/features/messaging/presentation/chat_thread_view.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Trip-scoped chat — main thread only.
class TripMessagingPage extends StatelessWidget {
  const TripMessagingPage({super.key});

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
    extends ConsumerState<TripThreadMessagingPage>
    with WidgetsBindingObserver {
  static const _presencePingInterval = Duration(seconds: 20);
  static const _markReadMinInterval = Duration(seconds: 2);

  late final NotificationCenterRepository _notificationCenter;
  GoRouterDelegate? _routerDelegate;
  TripChatController? _listenedController;
  Timer? _presenceTimer;
  Timer? _markReadTimer;
  DateTime? _lastReadMarkedAt;
  String? _lastSeenNewestId;
  String? _tripId;
  bool _wasVisible = false;

  /// Read position captured when the conversation came on screen, used to
  /// show where unread messages start.
  DateTime? _unreadSince;

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _presenceTimer = Timer.periodic(
      _presencePingInterval,
      (_) => _syncVisibility(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripId = TripScope.of(context).id;
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (!identical(delegate, _routerDelegate)) {
      _routerDelegate?.removeListener(_syncVisibility);
      _routerDelegate = delegate;
      delegate?.addListener(_syncVisibility);
    }
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncVisibility();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routerDelegate?.removeListener(_syncVisibility);
    _listenedController?.removeListener(_onConversationChanged);
    _presenceTimer?.cancel();
    _markReadTimer?.cancel();
    final tripId = _tripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(
        _notificationCenter
            .clearOpenChannel(tripId: tripId)
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  String _threadPath(String tripId) {
    final scope = widget.scope;
    final base = '/trips/$tripId/messages';
    if (scope.isAdmin) return '$base/admin';
    if (scope.isObject) {
      return '$base/object/${scope.threadObjectType}/${scope.threadObjectId}';
    }
    return base;
  }

  /// True when this conversation is the screen the user is looking at.
  bool _isOnScreen() {
    final tripId = _tripId;
    final delegate = _routerDelegate;
    if (tripId == null || delegate == null) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final path = Uri.decodeFull(delegate.currentConfiguration.uri.path);
    return path == _threadPath(tripId);
  }

  void _syncVisibility() {
    if (!mounted) return;
    final tripId = _tripId;
    if (tripId == null) return;
    final visible = _isOnScreen();
    final becameVisible = visible && !_wasVisible;
    _wasVisible = visible;
    if (!visible) return;

    if (becameVisible) {
      final lastReadAt = ref
          .read(
            tripChannelLastReadAtProvider(
              (tripId: tripId, channel: TripNotificationChannel.messages),
            ),
          )
          .asData
          ?.value;
      if (lastReadAt != _unreadSince) {
        // May run during build (dependency change): apply after the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _unreadSince = lastReadAt);
        });
      }
    }

    unawaited(
      _notificationCenter
          .setOpenChannel(
            tripId: tripId,
            channel: TripNotificationChannel.messages,
          )
          .catchError((Object _) {}),
    );
    if (becameVisible) {
      _lastSeenNewestId = _listenedController?.messages.firstOrNull?.id;
      _markRead(tripId);
    }
  }

  /// Marks the conversation as read when a new message is displayed while
  /// the user is looking at it.
  void _onConversationChanged() {
    final tripId = _tripId;
    final newestId = _listenedController?.messages.firstOrNull?.id;
    if (tripId == null || newestId == _lastSeenNewestId || !_isOnScreen()) {
      return;
    }
    _lastSeenNewestId = newestId;
    _markRead(tripId);
  }

  /// Marks the conversation as read now, at most once per
  /// [_markReadMinInterval]; a call made too early is replayed at the end of
  /// the interval so the last message is never left unread.
  void _markRead(String tripId) {
    final now = DateTime.now().toUtc();
    final last = _lastReadMarkedAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _markReadMinInterval) {
        _markReadTimer ??= Timer(_markReadMinInterval - elapsed, () {
          _markReadTimer = null;
          if (mounted && _isOnScreen()) _markRead(tripId);
        });
        return;
      }
    }
    _lastReadMarkedAt = now;
    unawaited(
      _notificationCenter
          .markReadUpTo(
            tripId: tripId,
            channel: TripNotificationChannel.messages,
            timestamp: now,
          )
          .catchError((Object _) {}),
    );
  }

  void _listenTo(TripChatController controller) {
    if (identical(controller, _listenedController)) return;
    _listenedController?.removeListener(_onConversationChanged);
    _listenedController = controller;
    controller.addListener(_onConversationChanged);
  }

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scope = widget.scope;

    final myUid = ref.watch(authStateProvider).asData?.value?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    final canAccessAdminThread = trip.isTripAdmin(myUid);

    if (scope.isAdmin && !canAccessAdminThread) {
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

    final request = TripMessageThreadRequest(tripId: trip.id, scope: scope);
    final controller = ref.watch(tripChatControllerProvider(request));
    _listenTo(controller);

    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    final memberPhotoUrls = ref.watch(tripMemberPhotoUrlsProvider(trip.id));

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
            child: ChatThreadView(
              controller: controller,
              currentUserId: myUid,
              memberLabels: memberLabels,
              memberPhotoUrls: memberPhotoUrls,
              fallbackAuthorLabel: l10n.roleParticipant,
              unreadSince: _unreadSince,
              pickImage: pickChatImage,
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
                  const Icon(PhosphorIconsRegular.chatsCircle),
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
                  const Icon(PhosphorIconsRegular.shieldCheck),
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
