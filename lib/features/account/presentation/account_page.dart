import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/data/account_preferences.dart';
import 'package:planzers/features/account/data/account_repository.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  bool _didInitFromFirestore = false;
  bool _didInitAutoOpenPreferenceFromFirestore = false;
  bool _isSaving = false;
  bool _isSavingAutoOpenPreference = false;
  bool _autoOpenCurrentTrip = true;

  Widget _buildAvatar(String photoUrl, String email) {
    final fallback = CircleAvatar(
      radius: 42,
      child: Text(
        email.isNotEmpty ? email[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 24),
      ),
    );

    if (photoUrl.isEmpty) {
      return fallback;
    }

    return SizedBox(
      width: 84,
      height: 84,
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
  void dispose() {
    _accountNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAccountName(_accountNameController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte mis a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mise a jour compte: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAutoOpenCurrentTripPreference(bool enabled) async {
    if (_isSavingAutoOpenPreference) return;

    setState(() => _isSavingAutoOpenPreference = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAutoOpenCurrentTripPreference(enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoOpenCurrentTrip = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mise a jour option: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingAutoOpenPreference = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/sign-in');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon compte'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.read(accountRepositoryProvider).watchMyUserDocument(),
        builder: (
          BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final account = (data['account'] as Map<String, dynamic>?) ?? const {};

          final email = (account['email'] as String?)?.trim().isNotEmpty == true
              ? (account['email'] as String).trim()
              : (data['email'] as String?)?.trim().isNotEmpty == true
                  ? (data['email'] as String).trim()
                  : (authUser.email ?? '').trim();
          final photoUrl = (account['photoUrl'] as String?)?.trim().isNotEmpty == true
              ? (account['photoUrl'] as String).trim()
              : (data['photoUrl'] as String?)?.trim().isNotEmpty == true
                  ? (data['photoUrl'] as String).trim()
                  : (authUser.photoURL ?? '').trim();
          final accountName = (account['name'] as String?)?.trim() ?? '';
          final autoOpenCurrentTripPreference =
              readAutoOpenCurrentTripPreference(data);

          if (!_didInitFromFirestore) {
            _accountNameController.text = accountName;
            _didInitFromFirestore = true;
          }
          if (!_didInitAutoOpenPreferenceFromFirestore &&
              !_isSavingAutoOpenPreference) {
            _autoOpenCurrentTrip = autoOpenCurrentTripPreference;
            _didInitAutoOpenPreferenceFromFirestore = true;
          }

          final effectiveName = accountName.isNotEmpty ? accountName : email;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.center,
                child: _buildAvatar(photoUrl, email),
              ),
              const SizedBox(height: 12),
              Text(
                email.isNotEmpty ? email : 'Email indisponible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                effectiveName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _accountNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du compte',
                        hintText: 'Ex: Alex',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().length > 60) {
                          return 'Maximum 60 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Si vide, le nom affiche sera votre email.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ouvrir auto le voyage en cours'),
                      subtitle: const Text(
                        'Ouvre automatiquement le voyage si un seul est en cours aujourd\'hui.',
                      ),
                      value: _autoOpenCurrentTrip,
                      onChanged: _isSavingAutoOpenPreference
                          ? null
                          : (enabled) {
                              setState(() => _autoOpenCurrentTrip = enabled);
                              _saveAutoOpenCurrentTripPreference(enabled);
                            },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
