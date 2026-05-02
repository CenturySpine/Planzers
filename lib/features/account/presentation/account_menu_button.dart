import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/external_links.dart';
import 'package:planerz/features/administration/presentation/administration_page.dart';
import 'package:planerz/features/help_support/presentation/help_support_page.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/platform/android_pwa_mode_detector.dart';
import 'package:planerz/core/push/fcm_token_sync.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  Future<void> _goToAccount(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    context.push('/account');
  }

  Future<void> _downloadApk(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await launchUrl(appPreviewApkDownloadUri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await deleteFcmTokenOnSignOut(uid);
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      context.go('/sign-in');
    }
  }

  Widget _buildAvatar(String photoUrl, String displayLabel) {
    final fallback = CircleAvatar(
      radius: 14,
      child: Text(
        avatarInitialFromDisplayLabel(displayLabel),
        style: const TextStyle(fontSize: 12),
      ),
    );

    if (photoUrl.isEmpty) {
      return fallback;
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final showDownloadApkAction = isAndroidPwaMode();
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    final displayLabel = (user?.displayName ?? '').trim().isNotEmpty
        ? (user?.displayName ?? '').trim()
        : displayLabelFromEmail(email);
    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocStream = user == null
        ? null
        : ref.read(accountRepositoryProvider).watchMyUserDocument();

    final cupidonCount =
        ref.watch(cupidonGlobalUnreadCountProvider).asData?.value ?? 0;

    if (userDocStream == null) {
      return _buildMenu(
        context: context,
        l10n: l10n,
        showDownloadApkAction: showDownloadApkAction,
        cupidonCount: cupidonCount,
        photoUrl: '',
        displayLabel: displayLabel,
        isApplicationOwner: false,
      );
    }

    return StreamBuilder(
      stream: userDocStream,
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final account = (data['account'] as Map<String, dynamic>?) ?? const {};
        final photoUrl =
            (account['photoUrl'] as String?)?.trim().isNotEmpty == true
                ? (account['photoUrl'] as String).trim()
                : (data['photoUrl'] as String?)?.trim() ?? '';
        final isApplicationOwner = data['isApplicationOwner'] == true;
        return _buildMenu(
          context: context,
          l10n: l10n,
          showDownloadApkAction: showDownloadApkAction,
          cupidonCount: cupidonCount,
          photoUrl: photoUrl,
          displayLabel: displayLabel,
          isApplicationOwner: isApplicationOwner,
        );
      },
    );
  }

  Widget _buildMenu({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool showDownloadApkAction,
    required int cupidonCount,
    required String photoUrl,
    required String displayLabel,
    required bool isApplicationOwner,
  }) {
    final avatar = _buildAvatar(photoUrl, displayLabel);
    final avatarWithBadge = cupidonCount > 0
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: -4,
                top: -4,
                child: _CupidonHeartBadge(count: cupidonCount),
              ),
            ],
          )
        : avatar;

    return PopupMenuButton<String>(
      tooltip: l10n.accountTitle,
      onSelected: (value) async {
        if (value == 'account') {
          await _goToAccount(context);
          return;
        }
        if (value == 'download_apk') {
          await _downloadApk(context);
          return;
        }
        if (value == 'administration') {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          context.push(AdministrationPage.routePath);
          return;
        }
        if (value == 'help_support') {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          context.push(HelpSupportPage.routePath);
          return;
        }
        if (value == 'logout') {
          await _logout(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'account',
          child: Row(
            children: [
              const Icon(Icons.manage_accounts_outlined, size: 20),
              const SizedBox(width: 12),
              Text(l10n.accountTitle),
            ],
          ),
        ),
        if (showDownloadApkAction)
          PopupMenuItem<String>(
            value: 'download_apk',
            child: Row(
              children: [
                const Icon(Icons.download_outlined, size: 20),
                const SizedBox(width: 12),
                Text(l10n.accountDownloadApk),
              ],
            ),
          ),
        if (isApplicationOwner)
          PopupMenuItem<String>(
            value: 'administration',
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 20),
                const SizedBox(width: 12),
                Text(l10n.accountAdministration),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'help_support',
          child: Row(
            children: [
              const Icon(Icons.help_outline, size: 20),
              const SizedBox(width: 12),
              Text(l10n.accountHelpSupport),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 20),
              const SizedBox(width: 12),
              Text(l10n.accountSignOut),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 12),
        child: avatarWithBadge,
      ),
    );
  }
}

class _CupidonHeartBadge extends StatelessWidget {
  const _CupidonHeartBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : count.toString();
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.favorite, color: Colors.pink, size: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}
