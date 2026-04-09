import 'package:firebase_auth/firebase_auth.dart';
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
}
