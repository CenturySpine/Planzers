import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/core/presentation/message_selection_action_bar.dart';
import 'package:planerz/features/trips/data/trip_announcement.dart';
import 'package:planerz/features/trips/data/trip_announcements_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripAnnouncementsPage extends ConsumerStatefulWidget {
  const TripAnnouncementsPage({super.key});

  @override
  ConsumerState<TripAnnouncementsPage> createState() => _TripAnnouncementsPageState();
}

class _TripAnnouncementsPageState extends ConsumerState<TripAnnouncementsPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final NotificationCenterRepository _notificationCenter;
  bool _sending = false;
  final Set<String> _deletingIds = <String>{};
  String? _selectedAnnouncementId;
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
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isAnnouncementsTabCurrentlyVisible() {
    try {
      final path = GoRouterState.of(context).uri.path;
      return path.endsWith('/announcements');
    } catch (_) {
      return false;
    }
  }

  void _markAnnouncementsAsReadIfNeeded(String tripId) {
    if (!_isAnnouncementsTabCurrentlyVisible()) return;
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
        channel: TripNotificationChannel.announcements,
        timestamp: now,
      ),
    );
  }

  void _syncPresenceIfNeeded(String tripId) {
    if (!_isAnnouncementsTabCurrentlyVisible()) return;
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
        channel: TripNotificationChannel.announcements,
      ),
    );
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
      await ref.read(tripAnnouncementsRepositoryProvider).sendAnnouncement(
            tripId: tripId,
            text: text,
          );
      if (!mounted) return;
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteAnnouncement({
    required String tripId,
    required String announcementId,
  }) async {
    if (_deletingIds.contains(announcementId)) return;
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.tripAnnouncementsDeleteConfirmBody),
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

    setState(() {
      _deletingIds.add(announcementId);
      _selectedAnnouncementId = null;
    });
    try {
      await ref.read(tripAnnouncementsRepositoryProvider).deleteAnnouncement(
            tripId: tripId,
            announcementId: announcementId,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _deletingIds.remove(announcementId));
    }
  }

  Future<bool> _editAnnouncement({
    required String tripId,
    required TripAnnouncement announcement,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => EditTextDialog(
        initialText: announcement.text,
        title: l10n.tripAnnouncementsEditTitle,
        maxLength: TripAnnouncementsRepository.maxTextLength,
      ),
    );
    if (newText == null || !mounted) return false;
    try {
      await ref.read(tripAnnouncementsRepositoryProvider).updateAnnouncement(
            tripId: tripId,
            announcementId: announcement.id,
            text: newText,
          );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final myRole = resolveTripPermissionRole(trip: trip, userId: myUid);
    final canPublish = isTripRoleAllowed(
      currentRole: myRole,
      minRole: trip.generalPermissions.publishAnnouncementsMinRole,
    );
    _syncPresenceIfNeeded(trip.id);
    final announcementsAsync = ref.watch(tripAnnouncementsStreamProvider(trip.id));
    final localeTag = Localizations.localeOf(context).toString();
    final timeFmt = DateFormat.Hm(localeTag);
    final dateFmt = DateFormat('d MMM yyyy', localeTag);

    return PopScope(
      canPop: _selectedAnnouncementId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedAnnouncementId != null) {
          setState(() => _selectedAnnouncementId = null);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            if (_selectedAnnouncementId != null)
              Builder(builder: (context) {
                final announcements = announcementsAsync.asData?.value ?? [];
                final selected = announcements.firstWhere(
                  (a) => a.id == _selectedAnnouncementId,
                  orElse: () {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => setState(() => _selectedAnnouncementId = null),
                    );
                    return announcements.first;
                  },
                );
                return MessageSelectionActionBar(
                  onClose: () => setState(() => _selectedAnnouncementId = null),
                  onEdit: canPublish
                      ? () async {
                          final ok = await _editAnnouncement(
                            tripId: trip.id,
                            announcement: selected,
                          );
                          if (ok && mounted) setState(() => _selectedAnnouncementId = null);
                        }
                      : null,
                  onDelete: canPublish
                      ? () => _deleteAnnouncement(
                            tripId: trip.id,
                            announcementId: selected.id,
                          )
                      : null,
                );
              }),
            if (_selectedAnnouncementId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n.tripAnnouncementsPageTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            Expanded(
              child: announcementsAsync.when(
                data: (announcements) {
                  _markAnnouncementsAsReadIfNeeded(trip.id);
                  if (announcements.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.tripAnnouncementsEmptyState,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  _scrollToBottom();
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: announcements.length,
                    itemBuilder: (context, index) {
                      final announcement = announcements[index];
                      final localDate = announcement.createdAt.toLocal();
                      final deleting = _deletingIds.contains(announcement.id);
                      final isSelected = _selectedAnnouncementId == announcement.id;
                      return GestureDetector(
                        onLongPress: canPublish
                            ? () => setState(() => _selectedAnnouncementId = announcement.id)
                            : null,
                        onTap: isSelected
                            ? () => setState(() => _selectedAnnouncementId = null)
                            : null,
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isSelected
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          LinkifiedText(text: announcement.text),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Text(
                                                '${dateFmt.format(localDate)} · ${timeFmt.format(localDate)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              if (announcement.wasEdited) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.edit_rounded,
                                                  size: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canPublish && !isSelected)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: IconButton(
                                          onPressed: deleting
                                              ? null
                                              : () => unawaited(
                                                    _deleteAnnouncement(
                                                      tripId: trip.id,
                                                      announcementId: announcement.id,
                                                    ),
                                                  ),
                                          icon: deleting
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : Icon(Icons.delete_outline,
                                                  color: Theme.of(context).colorScheme.error),
                                          tooltip: l10n.commonDelete,
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.commonErrorWithDetails(e.toString()),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            if (canPublish)
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
                              hintText: l10n.tripAnnouncementsInputHint,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            onSubmitted: _sending ? null : (_) => unawaited(_send(trip.id)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : () => unawaited(_send(trip.id)),
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
      ),
    );
  }
}
