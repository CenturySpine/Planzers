import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/trip_date_format.dart';

class TripsPage extends ConsumerWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsStreamProvider);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes voyages'),
        actions: [
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'trips_join_invite',
            tooltip: 'Rejoindre avec un code d\'invitation',
            onPressed: () => _openJoinByInviteCodeDialog(context),
            child: const Icon(Icons.vpn_key_outlined),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'trips_create',
            tooltip: 'Nouveau voyage',
            onPressed: () => _openCreateTripDialog(context, ref),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: tripsAsync.when(
        data: (trips) {
          if (trips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun voyage pour le moment.\nCree ton premier voyage.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final trip = trips[index];
              final canDelete = (myUid != null && trip.ownerId == myUid);
              final dateLine = formatTripDateRange(trip.startDate, trip.endDate);
              return ListTile(
                onTap: () => context.push('/trips/${trip.id}/overview'),
                title: Text(trip.title),
                subtitle: Text(
                  dateLine.isEmpty
                      ? trip.destination
                      : '$dateLine\n${trip.destination}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${trip.memberIds.length} membre(s)'),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: () => _confirmAndDeleteTrip(
                          context,
                          ref,
                          tripId: trip.id,
                          tripTitle: trip.title,
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erreur Firestore: $error'),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateTripDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController();
    final destinationController = TextEditingController();
    String? error;
    DateTime? startDate;
    DateTime? endDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickStart() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setDialogState(() => startDate = picked);
              }
            }

            Future<void> pickEnd() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: endDate ?? startDate ?? DateTime.now(),
                firstDate: startDate ?? DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setDialogState(() => endDate = picked);
              }
            }

            return AlertDialog(
              title: const Text('Creer un voyage'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Titre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: destinationController,
                      decoration: const InputDecoration(labelText: 'Destination'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date de début'),
                      subtitle: Text(formatOptionalTripDate(startDate)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (startDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setDialogState(() => startDate = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: pickStart,
                          ),
                        ],
                      ),
                      onTap: pickStart,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date de fin'),
                      subtitle: Text(formatOptionalTripDate(endDate)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (endDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setDialogState(() => endDate = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: pickEnd,
                          ),
                        ],
                      ),
                      onTap: pickEnd,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final destination = destinationController.text.trim();

                    if (title.isEmpty || destination.isEmpty) {
                      setDialogState(() {
                        error = 'Titre et destination obligatoires';
                      });
                      return;
                    }

                    if (isEndBeforeStart(startDate, endDate)) {
                      setDialogState(() {
                        error =
                            'La date de fin doit être le même jour ou après la date de début';
                      });
                      return;
                    }

                    try {
                      await ref.read(tripsRepositoryProvider).createTrip(
                            title: title,
                            destination: destination,
                            startDate: startDate,
                            endDate: endDate,
                          );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                      setDialogState(() {
                        error = e.toString();
                      });
                    }
                  },
                  child: const Text('Creer'),
                ),
              ],
            );
          },
        );
      },
    );

    // Same lifecycle issue as the invite dialog: do not dispose until the
    // route overlay has finished tearing down (async close + animation).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
        destinationController.dispose();
      });
    });
  }

  Future<void> _openJoinByInviteCodeDialog(BuildContext parentContext) async {
    await showDialog<void>(
      context: parentContext,
      builder: (dialogRouteContext) => _JoinTripByCodeDialog(
        parentContext: parentContext,
        navigatorContext: dialogRouteContext,
      ),
    );
  }

  static String _messageForJoinByCodeError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'not-found':
          return 'Ce code d\'invitation est introuvable.';
        case 'permission-denied':
          return 'Ce code d\'invitation n\'est plus valide.';
        case 'invalid-argument':
          return 'Code d\'invitation invalide.';
        case 'unauthenticated':
          return 'Connecte-toi pour rejoindre un voyage.';
        default:
          break;
      }
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
  }

  Future<void> _confirmAndDeleteTrip(
    BuildContext context,
    WidgetRef ref, {
    required String tripId,
    required String tripTitle,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer ce voyage ?'),
          content: Text(
            'Cette action est definitive.\n\nVoyage: $tripTitle',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(tripsRepositoryProvider).deleteTrip(tripId: tripId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyage supprime')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression: $e')),
      );
    }
  }
}

class _JoinTripByCodeDialog extends ConsumerStatefulWidget {
  const _JoinTripByCodeDialog({
    required this.parentContext,
    required this.navigatorContext,
  });

  /// Context of [TripsPage] (valid for [GoRouter] / [ScaffoldMessenger] after close).
  final BuildContext parentContext;

  /// Context passed to [showDialog] (valid for [Navigator.pop] only).
  final BuildContext navigatorContext;

  @override
  ConsumerState<_JoinTripByCodeDialog> createState() =>
      _JoinTripByCodeDialogState();
}

class _JoinTripByCodeDialogState extends ConsumerState<_JoinTripByCodeDialog> {
  late final TextEditingController _codeController;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Saisis le code d\'invitation.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final tripId =
          await ref.read(tripsRepositoryProvider).joinTripWithInviteToken(code);
      if (!widget.navigatorContext.mounted) return;
      Navigator.of(widget.navigatorContext).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!widget.parentContext.mounted) return;
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text('Vous avez rejoint le voyage')),
        );
        widget.parentContext.go('/trips/$tripId/overview');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = TripsPage._messageForJoinByCodeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Code d\'invitation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Colle le code envoye par l\'organisateur du voyage '
              '(pas le lien, uniquement le code).',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: _isSubmitting ? null : (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(widget.navigatorContext).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Rejoindre'),
        ),
      ],
    );
  }
}
