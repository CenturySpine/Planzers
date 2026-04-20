import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/data/account_repository.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/cupidon/data/cupidon_repository.dart';

class CupidonSpacePage extends ConsumerStatefulWidget {
  const CupidonSpacePage({super.key});

  @override
  ConsumerState<CupidonSpacePage> createState() => _CupidonSpacePageState();
}

class _CupidonSpacePageState extends ConsumerState<CupidonSpacePage> {
  bool _updatingDefault = false;
  final Set<String> _deletingMatchIds = <String>{};

  Future<void> _updateDefaultCupidonEnabled(bool enabled) async {
    if (_updatingDefault) return;
    setState(() => _updatingDefault = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateCupidonEnabledByDefaultPreference(enabled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mise à jour préférence: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingDefault = false);
    }
  }

  Future<void> _confirmAndDeleteMatch(CupidonMatchEntry match) async {
    final cleanId = match.matchId.trim();
    if (cleanId.isEmpty || _deletingMatchIds.contains(cleanId)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce match ?'),
        content: Text(
          'Ce match avec ${match.otherMemberLabel} (voyage "${match.tripTitle}") sera retiré de ton historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingMatchIds.add(cleanId));
    try {
      await ref.read(cupidonRepositoryProvider).deleteMyMatch(cleanId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingMatchIds.remove(cleanId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultCupidonAsync = ref.watch(cupidonEnabledByDefaultProvider);
    final matchesAsync = ref.watch(myCupidonMatchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Espace Cupidon')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: defaultCupidonAsync.when(
                data: (enabled) => SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged:
                      _updatingDefault ? null : _updateDefaultCupidonEnabled,
                  title: const Text('Activer Cupidon par défaut'),
                  subtitle: const Text(
                    'Quand tu rejoins un nouveau voyage, cette valeur est préremplie.',
                  ),
                ),
                loading: () => const SizedBox(
                  height: 70,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Erreur chargement préférence: $e'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Mes matchs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          matchesAsync.when(
            data: (matches) {
              if (matches.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun match enregistré pour le moment.'),
                  ),
                );
              }
              return Column(
                children: matches.map((match) {
                  final isDeleting = _deletingMatchIds.contains(match.matchId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: _ProfileBadge(
                          label: match.otherMemberLabel,
                          photoUrl: match.otherMemberPhotoUrl,
                        ),
                        title: Text(match.otherMemberLabel),
                        subtitle: Text(
                          '${match.tripTitle} · ${_formatMatchDate(match.createdAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Supprimer ce match',
                          onPressed: isDeleting
                              ? null
                              : () => _confirmAndDeleteMatch(match),
                          icon: isDeleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Erreur chargement matchs: $e'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMatchDate(DateTime value) {
    final d = value.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.label,
    required this.photoUrl,
  });

  final String label;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final cleanPhotoUrl = photoUrl.trim();
    final initial = avatarInitialFromDisplayLabel(label);
    return CircleAvatar(
      foregroundImage:
          cleanPhotoUrl.isEmpty ? null : NetworkImage(cleanPhotoUrl),
      child: Text(initial),
    );
  }
}
