import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/app/theme/planzers_colors.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

class InviteJoinPage extends ConsumerStatefulWidget {
  const InviteJoinPage({
    super.key,
    required this.tripId,
    required this.token,
  });

  final String tripId;
  final String token;

  @override
  ConsumerState<InviteJoinPage> createState() => _InviteJoinPageState();
}

class _InviteJoinPageState extends ConsumerState<InviteJoinPage> {
  bool _isJoining = false;
  String? _error;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _joinIfPossible());
  }

  Future<void> _joinIfPossible() async {
    if (_isJoining || _joined) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final redirect = Uri(
        path: '/invite',
        queryParameters: <String, String>{
          'tripId': widget.tripId,
          'token': widget.token,
        },
      ).toString();
      if (mounted) {
        context.go(
          '/sign-in?redirect=${Uri.encodeComponent(redirect)}',
        );
      }
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });
    try {
      await ref.read(tripsRepositoryProvider).joinTripWithInvite(
            tripId: widget.tripId,
            token: widget.token,
          );
      if (!mounted) return;
      setState(() {
        _joined = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous avez rejoint le voyage')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInvalidParams =
        widget.tripId.trim().isEmpty || widget.token.trim().isEmpty;
    if (hasInvalidParams) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Lien d invitation invalide.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Invitation au voyage')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isJoining) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Connexion au voyage en cours...'),
                ] else if (_joined) ...[
                  Icon(
                    Icons.check_circle,
                    color: context.planzersColors.success,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Invitation acceptee.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vous faites maintenant partie du voyage.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/trips'),
                    child: const Text('Voir mes voyages'),
                  ),
                ] else ...[
                  const Icon(Icons.group_add_outlined, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Rejoindre ce voyage',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _joinIfPossible,
                    child: const Text('Reessayer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
