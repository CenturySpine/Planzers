import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trip_member_profile_repository.dart';
import 'package:planzers/features/trips/data/trip_member_stay.dart';
import 'package:planzers/features/trips/presentation/trip_stay_bounds_editor.dart';

Future<void> showTripStayEditDialog({
  required BuildContext context,
  required Trip trip,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final stayAsync = ref.watch(tripMemberStayStreamProvider(trip.id));
          return stayAsync.when(
            data: (stay) => _TripStayFormDialog(
              trip: trip,
              initialStay: stay,
            ),
            loading: () => const AlertDialog(
              content: SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => AlertDialog(
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _TripStayFormDialog extends ConsumerStatefulWidget {
  const _TripStayFormDialog({
    required this.trip,
    required this.initialStay,
  });

  final Trip trip;
  final TripMemberStay? initialStay;

  @override
  ConsumerState<_TripStayFormDialog> createState() =>
      _TripStayFormDialogState();
}

class _TripStayFormDialogState extends ConsumerState<_TripStayFormDialog> {
  late TripMemberStay _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _value =
        widget.initialStay ?? TripMemberStay.defaultForTrip(widget.trip);
  }

  Future<void> _save() async {
    if (!TripMemberStay.isChronological(_value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La plage de dates est invalide.'),
        ),
      );
      return;
    }
    if (!TripMemberStay.withinTripCalendarBounds(
      stay: _value,
      trip: widget.trip,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les dates doivent rester dans les dates du voyage.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(tripMemberProfileRepositoryProvider).upsertMyStay(
            tripId: widget.trip.id,
            stay: _value,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dates mises à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mes dates sur le voyage'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: TripStayBoundsEditor(
            tripStartDate: widget.trip.startDate,
            tripEndDate: widget.trip.endDate,
            value: _value,
            onChanged: (v) => setState(() => _value = v),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
