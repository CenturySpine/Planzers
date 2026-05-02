import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/features/administration/data/global_announcements_repository.dart';
import 'package:planerz/features/administration/domain/admin_announcement.dart';
import 'package:planerz/features/administration/domain/admin_announcement_localized_text.dart';
import 'package:planerz/l10n/app_localizations.dart';

class GlobalAnnouncementsPage extends ConsumerStatefulWidget {
  const GlobalAnnouncementsPage({super.key});

  static const String routePath = '/announcements';

  @override
  ConsumerState<GlobalAnnouncementsPage> createState() =>
      _GlobalAnnouncementsPageState();
}

class _GlobalAnnouncementsPageState
    extends ConsumerState<GlobalAnnouncementsPage> {
  final Set<String> _dismissingAnnouncementIds = <String>{};
  bool _isRestoringDismissedAnnouncements = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(globalAnnouncementsRepositoryProvider).markAsReadNow(),
      );
    });
  }

  Future<void> _dismissAnnouncement({
    required AppLocalizations l10n,
    required AdminAnnouncement announcement,
  }) async {
    final announcementId = announcement.id;
    if (_dismissingAnnouncementIds.contains(announcementId)) {
      return;
    }
    setState(() {
      _dismissingAnnouncementIds.add(announcementId);
    });
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .dismissAnnouncement(announcementId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _dismissingAnnouncementIds.remove(announcementId);
        });
      }
    }
  }

  Future<void> _restoreDismissedAnnouncements(AppLocalizations l10n) async {
    if (_isRestoringDismissedAnnouncements) {
      return;
    }
    setState(() => _isRestoringDismissedAnnouncements = true);
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .restoreAllDismissedAdminAnnouncements();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.globalAnnouncementsRestoreHiddenSnackBar)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoringDismissedAnnouncements = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeTag = Localizations.localeOf(context).toString();
    final timeFormat = DateFormat.Hm(localeTag);
    final dateFormat = DateFormat('d MMM yyyy', localeTag);
    final announcementsAsync =
        ref.watch(globalVisibleAnnouncementsForCurrentUserProvider);
    final hasDismissedAsync =
        ref.watch(globalHasDismissedAdminAnnouncementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.globalAnnouncementsTitle),
        actions: [
          if (hasDismissedAsync.maybeWhen(
            data: (hasDismissed) => hasDismissed,
            orElse: () => false,
          ))
            IconButton(
              tooltip: l10n.globalAnnouncementsRestoreHiddenTooltip,
              onPressed: _isRestoringDismissedAnnouncements
                  ? null
                  : () => unawaited(_restoreDismissedAnnouncements(l10n)),
              icon: _isRestoringDismissedAnnouncements
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : const Icon(Icons.visibility_outlined),
            ),
        ],
      ),
      body: announcementsAsync.when(
        data: (announcements) {
          if (announcements.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.globalAnnouncementsEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final announcement = announcements[index];
              final localCreatedAt = announcement.createdAt.toLocal();
              final resolvedBody = resolveAdminAnnouncementText(
                announcement.text,
                Localizations.localeOf(context),
              );
              final isDismissing =
                  _dismissingAnnouncementIds.contains(announcement.id);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinkifiedText(text: resolvedBody),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${dateFormat.format(localCreatedAt)} · ${timeFormat.format(localCreatedAt)}',
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
                      if (announcement.userDismissAllowed)
                        IconButton(
                          onPressed: isDismissing
                              ? null
                              : () => unawaited(
                                    _dismissAnnouncement(
                                      l10n: l10n,
                                      announcement: announcement,
                                    ),
                                  ),
                          icon: isDismissing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.close,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                          tooltip: l10n.globalAnnouncementsDismissTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
