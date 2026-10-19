import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/administration/data/admin_trip_activities_repository.dart';

/// Deletes all the activities of a trip (e.g. after tests of the AI imports).
class AdminTripActivitiesPage extends ConsumerStatefulWidget {
  const AdminTripActivitiesPage({super.key});

  static const String routePath = '/administration/trip-activities';

  @override
  ConsumerState<AdminTripActivitiesPage> createState() =>
      _AdminTripActivitiesPageState();
}

class _AdminTripActivitiesPageState
    extends ConsumerState<AdminTripActivitiesPage> {
  final TextEditingController _searchController = TextEditingController();
  List<AdminTripActivityCount>? _trips;
  Object? _error;
  bool _loading = false;
  String? _deletingTripId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips =
          await ref.read(adminTripActivitiesRepositoryProvider).listTrips();
      if (!mounted) return;
      setState(() => _trips = trips);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndDelete(AdminTripActivityCount trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer les activités ?'),
        content: Text(
          trip.activityCount == 1
              ? 'L’activité de « ${_titleOf(trip)} » sera supprimée '
                  'définitivement, ainsi que ses liens dans les documents de '
                  'voyage et les repas.'
              : 'Les ${trip.activityCount} activités de « ${_titleOf(trip)} » '
                  'seront supprimées définitivement, ainsi que leurs liens dans '
                  'les documents de voyage et les repas.',
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
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deletingTripId = trip.tripId);
    try {
      final deleted = await ref
          .read(adminTripActivitiesRepositoryProvider)
          .deleteActivities(
            tripId: trip.tripId,
            expectedActivityCount: trip.activityCount,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            deleted <= 1
                ? '$deleted activité supprimée'
                : '$deleted activités supprimées',
          ),
        ),
      );
    } catch (error) {
      final message = error is FirebaseFunctionsException
          ? error.message ?? error.code
          : '$error';
      messenger.showSnackBar(
        SnackBar(content: Text('Échec de la suppression : $message')),
      );
    } finally {
      if (mounted) setState(() => _deletingTripId = null);
    }
    if (mounted) await _load();
  }

  static String _activitiesLabel(int count) =>
      count <= 1 ? '$count activité' : '$count activités';

  static String _titleOf(AdminTripActivityCount trip) =>
      trip.title.isEmpty ? '(sans titre)' : trip.title;

  static String _datesOf(AdminTripActivityCount trip) {
    final format = DateFormat('dd/MM/yyyy');
    String day(String raw) {
      final date = DateTime.tryParse(raw);
      return date == null ? '?' : format.format(date);
    }

    if (trip.startDate.isEmpty && trip.endDate.isEmpty) return '';
    return '${day(trip.startDate)} → ${day(trip.endDate)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activités des voyages'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading || _deletingTripId != null ? null : _load,
            icon: const Icon(PhosphorIconsRegular.arrowClockwise),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final trips = _trips;
    if (trips == null) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Échec du chargement : $_error'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
              hintText: 'Rechercher un voyage',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(child: _buildList(trips)),
      ],
    );
  }

  Widget _buildList(List<AdminTripActivityCount> trips) {
    final query = _searchController.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? trips
        : trips
            .where((t) =>
                t.title.toLowerCase().contains(query) ||
                t.tripId.toLowerCase().contains(query))
            .toList(growable: false);
    if (shown.isEmpty) {
      return const Center(child: Text('Aucun voyage'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final trip = shown[index];
        final dates = _datesOf(trip);
        final deleting = _deletingTripId == trip.tripId;
        return ListTile(
          title: Text(_titleOf(trip)),
          subtitle: Text(
            [
              if (dates.isNotEmpty) dates,
              _activitiesLabel(trip.activityCount),
            ].join(' · '),
          ),
          trailing: deleting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : trip.activityCount == 0
                  ? null
                  : IconButton(
                      tooltip: 'Supprimer les activités',
                      onPressed: _deletingTripId == null
                          ? () => _confirmAndDelete(trip)
                          : null,
                      icon: const Icon(PhosphorIconsRegular.trash),
                    ),
        );
      },
    );
  }
}
