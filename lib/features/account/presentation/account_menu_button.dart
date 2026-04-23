import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/push/fcm_token_sync.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  static final Uri _apkDownloadUri = Uri.parse(
    'https://github.com/CenturySpine/Planzers/releases/latest/download/planerz-preview.apk',
  );

  Future<void> _goToAccount(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    context.push('/account');
  }

  Future<void> _downloadApk(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await launchUrl(_apkDownloadUri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir le lien")),
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

    final avatar = userDocStream == null
        ? _buildAvatar('', displayLabel)
        : StreamBuilder(
            stream: userDocStream,
            builder: (BuildContext context,
                AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
              final data = snapshot.data?.data() ?? const <String, dynamic>{};
              final account =
                  (data['account'] as Map<String, dynamic>?) ?? const {};
              final photoUrl =
                  (account['photoUrl'] as String?)?.trim().isNotEmpty == true
                      ? (account['photoUrl'] as String).trim()
                      : (data['photoUrl'] as String?)?.trim() ?? '';
              return _buildAvatar(photoUrl, displayLabel);
            },
          );

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
      tooltip: 'Mon compte',
      onSelected: (value) async {
        if (value == 'account') {
          await _goToAccount(context);
          return;
        }
        if (value == 'download_apk') {
          await _downloadApk(context);
          return;
        }
        if (value == 'logout') {
          await _logout(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'account',
          child: Text('Mon compte'),
        ),
        if (kIsWeb)
          const PopupMenuItem<String>(
            value: 'download_apk',
            child: Text("Télécharger l'APK"),
          ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Se deconnecter'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
