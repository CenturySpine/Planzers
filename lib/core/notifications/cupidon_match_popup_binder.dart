import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/app/router.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/l10n/app_localizations.dart';

class CupidonMatchPopupBinder extends StatefulWidget {
  const CupidonMatchPopupBinder({required this.child, super.key});

  final Widget child;

  @override
  State<CupidonMatchPopupBinder> createState() =>
      _CupidonMatchPopupBinderState();
}

class _CupidonMatchPopupBinderState extends State<CupidonMatchPopupBinder> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _matchesSub;
  bool _readyForRealtimeAdds = false;
  final List<_CupidonPopupPayload> _queue = <_CupidonPopupPayload>[];
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      return;
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _matchesSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChanged(User? user) async {
    await _matchesSub?.cancel();
    _matchesSub = null;
    _readyForRealtimeAdds = false;
    _queue.clear();

    if (user == null) return;

    _matchesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('cupidonMatches')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!_readyForRealtimeAdds) {
        _readyForRealtimeAdds = true;
        return;
      }
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data() ?? const <String, dynamic>{};
        final other = (data['otherMemberLabel'] as String?)?.trim();
        final photo = (data['otherMemberPhotoUrl'] as String?)?.trim();
        final trip = (data['tripTitle'] as String?)?.trim();
        _queue.add(
          _CupidonPopupPayload(
            otherMemberLabel: other ?? '',
            otherMemberPhotoUrl: photo != null && photo.isNotEmpty ? photo : '',
            tripTitle: trip ?? '',
          ),
        );
      }
      unawaited(_drainQueue());
    });
  }

  Future<void> _drainQueue() async {
    if (_dialogOpen || !mounted || _queue.isEmpty) return;
    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_drainQueue());
      });
      return;
    }
    _dialogOpen = true;
    final payload = _queue.removeAt(0);
    final l10n = AppLocalizations.of(navContext)!;
    final otherMemberLabel = payload.otherMemberLabel.trim().isNotEmpty
        ? payload.otherMemberLabel
        : l10n.cupidonPopupUnknownMember;
    final tripTitle =
        payload.tripTitle.trim().isNotEmpty ? payload.tripTitle : l10n.tripLabelGeneric;
    await showDialog<void>(
      context: navContext,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.pink),
            const SizedBox(width: 8),
            Text(l10n.cupidonPopupTitle),
          ],
        ),
        content: Row(
          children: [
            CircleAvatar(
              foregroundImage: payload.otherMemberPhotoUrl.isEmpty
                  ? null
                  : NetworkImage(payload.otherMemberPhotoUrl),
              child: Text(avatarInitialFromDisplayLabel(otherMemberLabel)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$otherMemberLabel\n$tripTitle',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              appRouter.push('/account/cupidon');
            },
            child: Text(l10n.cupidonPopupViewMatchesAction),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (_queue.isNotEmpty) {
      unawaited(_drainQueue());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CupidonPopupPayload {
  const _CupidonPopupPayload({
    required this.otherMemberLabel,
    required this.otherMemberPhotoUrl,
    required this.tripTitle,
  });

  final String otherMemberLabel;
  final String otherMemberPhotoUrl;
  final String tripTitle;
}
