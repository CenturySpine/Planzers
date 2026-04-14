import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/app/theme/planzers_colors.dart';
import 'package:planzers/features/account/presentation/account_app_bar_actions.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/trip_date_format.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({super.key});

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

enum _TripTimelineCategory { past, ongoing, upcoming }

class _TripsPageState extends ConsumerState<TripsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsStreamProvider);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes voyages'),
        actions: const [
          AccountAppBarActions(),
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

          final grouped = _groupTripsByTimeline(trips);
          final colorScheme = Theme.of(context).colorScheme;
          final palette = context.planzersColors;

          final timelineColors = <_TripTimelineCategory, Color>{
            _TripTimelineCategory.past: palette.warning,
            _TripTimelineCategory.ongoing: colorScheme.primaryContainer,
            _TripTimelineCategory.upcoming: colorScheme.tertiary,
          };

          return Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Passés'),
                  Tab(text: 'En cours'),
                  Tab(text: 'À venir'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TripsTimelineList(
                      trips: grouped[_TripTimelineCategory.past] ?? const [],
                      color: timelineColors[_TripTimelineCategory.past]!,
                      emptyMessage: 'Aucun voyage passé.',
                      myUid: myUid,
                      onOpenTrip: (tripId) =>
                          context.push('/trips/$tripId/overview'),
                      onDeleteTrip: (trip) => _confirmAndDeleteTrip(
                        context,
                        ref,
                        tripId: trip.id,
                        tripTitle: trip.title,
                      ),
                    ),
                    _TripsTimelineList(
                      trips: grouped[_TripTimelineCategory.ongoing] ?? const [],
                      color: timelineColors[_TripTimelineCategory.ongoing]!,
                      emptyMessage: 'Aucun voyage en cours.',
                      myUid: myUid,
                      onOpenTrip: (tripId) =>
                          context.push('/trips/$tripId/overview'),
                      onDeleteTrip: (trip) => _confirmAndDeleteTrip(
                        context,
                        ref,
                        tripId: trip.id,
                        tripTitle: trip.title,
                      ),
                    ),
                    _TripsTimelineList(
                      trips: grouped[_TripTimelineCategory.upcoming] ?? const [],
                      color: timelineColors[_TripTimelineCategory.upcoming]!,
                      emptyMessage: 'Aucun voyage à venir.',
                      myUid: myUid,
                      onOpenTrip: (tripId) =>
                          context.push('/trips/$tripId/overview'),
                      onDeleteTrip: (trip) => _confirmAndDeleteTrip(
                        context,
                        ref,
                        tripId: trip.id,
                        tripTitle: trip.title,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  Map<_TripTimelineCategory, List<Trip>> _groupTripsByTimeline(List<Trip> trips) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final grouped = <_TripTimelineCategory, List<Trip>>{
      _TripTimelineCategory.past: [],
      _TripTimelineCategory.ongoing: [],
      _TripTimelineCategory.upcoming: [],
    };

    for (final trip in trips) {
      final category = _timelineCategoryForTrip(trip, today);
      grouped[category]!.add(trip);
    }

    grouped[_TripTimelineCategory.past]!.sort(_comparePastTrips);
    grouped[_TripTimelineCategory.ongoing]!.sort(_compareOngoingTrips);
    grouped[_TripTimelineCategory.upcoming]!.sort(_compareUpcomingTrips);
    return grouped;
  }

  _TripTimelineCategory _timelineCategoryForTrip(Trip trip, DateTime today) {
    final start = trip.startDate != null
        ? DateTime(trip.startDate!.year, trip.startDate!.month, trip.startDate!.day)
        : null;
    final end = trip.endDate != null
        ? DateTime(trip.endDate!.year, trip.endDate!.month, trip.endDate!.day)
        : null;

    if (start == null && end == null) {
      return _TripTimelineCategory.ongoing;
    }
    if (end != null && end.isBefore(today)) {
      return _TripTimelineCategory.past;
    }
    if (start != null && start.isAfter(today)) {
      return _TripTimelineCategory.upcoming;
    }
    return _TripTimelineCategory.ongoing;
  }

  int _comparePastTrips(Trip a, Trip b) {
    final aEnd = a.endDate ?? a.startDate ?? a.createdAt;
    final bEnd = b.endDate ?? b.startDate ?? b.createdAt;
    return bEnd.compareTo(aEnd);
  }

  int _compareOngoingTrips(Trip a, Trip b) {
    final aStart = a.startDate ?? a.createdAt;
    final bStart = b.startDate ?? b.createdAt;
    return bStart.compareTo(aStart);
  }

  int _compareUpcomingTrips(Trip a, Trip b) {
    final aStart = a.startDate ?? a.endDate ?? a.createdAt;
    final bStart = b.startDate ?? b.endDate ?? b.createdAt;
    return aStart.compareTo(bStart);
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
                      decoration:
                          const InputDecoration(labelText: 'Destination'),
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
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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

class _TripsTimelineList extends StatelessWidget {
  const _TripsTimelineList({
    required this.trips,
    required this.color,
    required this.emptyMessage,
    required this.myUid,
    required this.onOpenTrip,
    required this.onDeleteTrip,
  });

  final List<Trip> trips;
  final Color color;
  final String emptyMessage;
  final String? myUid;
  final ValueChanged<String> onOpenTrip;
  final ValueChanged<Trip> onDeleteTrip;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final canDelete = myUid != null && trip.ownerId == myUid;
        final dateLine = formatTripDateRange(trip.startDate, trip.endDate);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TripCard(
            trip: trip,
            color: color,
            canDelete: canDelete,
            dateLine: dateLine,
            onTap: () => onOpenTrip(trip.id),
            onDelete: () => onDeleteTrip(trip),
          ),
        );
      },
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.color,
    required this.canDelete,
    required this.dateLine,
    required this.onTap,
    required this.onDelete,
  });

  final Trip trip;
  final Color color;
  final bool canDelete;
  final String dateLine;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final surface = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      Theme.of(context).colorScheme.surface,
    );
    return Card(
      margin: EdgeInsets.zero,
      color: surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    if (dateLine.isNotEmpty)
                      Text(
                        dateLine,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (trip.destination.trim().isNotEmpty) ...[
                      if (dateLine.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        trip.destination,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${trip.memberIds.length} membre(s)',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _openInviteJoinPage({
    required String tripId,
    required String token,
  }) async {
    if (!widget.navigatorContext.mounted) return;
    Navigator.of(widget.navigatorContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.parentContext.mounted) return;
      final route = Uri(
        path: '/invite',
        queryParameters: <String, String>{
          'tripId': tripId,
          'token': token,
        },
      ).toString();
      widget.parentContext.go(route);
    });
  }

  Future<void> _submitEnterCode() async {
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
      final ctx = await ref.read(tripsRepositoryProvider).getInviteJoinContext(
            token: code,
          );
      if (!mounted) return;
      await _openInviteJoinPage(tripId: ctx.tripId, token: code);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _TripsPageState._messageForJoinByCodeError(e);
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
              onSubmitted: _isSubmitting ? null : (_) => _submitEnterCode(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
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
          onPressed: _isSubmitting
              ? null
              : _submitEnterCode,
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
