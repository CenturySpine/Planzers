import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  Future<void> _goToAccount(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    context.push('/account');
  }

  Future<void> _logout(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      context.go('/sign-in');
    }
  }

  Widget _buildAvatar(String photoUrl, String email) {
    return CircleAvatar(
      radius: 14,
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(
              email.isNotEmpty ? email[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 12),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = (user?.photoURL ?? '').trim();
    final email = (user?.email ?? '').trim();

    if (kIsWeb) {
      return PopupMenuButton<String>(
        tooltip: 'Mon compte',
        onSelected: (value) async {
          if (value == 'account') {
            await _goToAccount(context);
            return;
          }
          if (value == 'logout') {
            await _logout(context);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            value: 'account',
            child: Text('Mon compte'),
          ),
          PopupMenuItem<String>(
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

    return IconButton(
      tooltip: 'Mon compte',
      onPressed: () {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildAvatar(photoUrl, email),
                      const SizedBox(width: 10),
                      const Text('Mon compte'),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _goToAccount(context),
                  child: const Text('Compte'),
                ),
                TextButton(
                  onPressed: () => _logout(context),
                  child: const Text('Logout'),
                ),
              ],
            ),
          ),
        );
      },
      icon: _buildAvatar(photoUrl, email),
    );
  }
}
