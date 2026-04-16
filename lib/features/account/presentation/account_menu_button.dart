import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountMenuButton extends StatelessWidget {
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
        const SnackBar(content: Text('Impossible d’ouvrir le lien')),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      context.go('/sign-in');
    }
  }

  Widget _buildAvatar(String photoUrl, String email) {
    final fallback = CircleAvatar(
      radius: 14,
      child: Text(
        email.isNotEmpty ? email[0].toUpperCase() : '?',
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
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = (user?.photoURL ?? '').trim();
    final email = (user?.email ?? '').trim();

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
            child: Text('Télécharger l’APK'),
          ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Se deconnecter'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildAvatar(photoUrl, email),
      ),
    );
  }
}
