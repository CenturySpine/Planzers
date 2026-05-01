import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/administration/data/global_announcements_repository.dart';
import 'package:planerz/features/administration/presentation/global_announcements_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

class AdminAnnouncementsBellButton extends ConsumerWidget {
  const AdminAnnouncementsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isApplicationOwnerAsync = ref.watch(myIsApplicationOwnerProvider);
    final isApplicationOwner = isApplicationOwnerAsync.maybeWhen(
      data: (isOwner) => isOwner,
      orElse: () => false,
    );
    if (isApplicationOwner) {
      return const SizedBox.shrink();
    }

    final unreadIndicatorAsync =
        ref.watch(globalAdminAnnouncementsUnreadIndicatorProvider);
    final showUnreadDot = unreadIndicatorAsync.maybeWhen(
      data: (hasUnread) => hasUnread,
      orElse: () => false,
    );

    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      tooltip: l10n.globalAnnouncementsBellTooltip,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.only(left: 10, right: 2, top: 8, bottom: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_outlined),
            if (showUnreadDot)
              Positioned(
                right: 3,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
      onPressed: () => context.push(GlobalAnnouncementsPage.routePath),
    );
  }
}
