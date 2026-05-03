import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_stay_bounds_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripCreatePage extends ConsumerStatefulWidget {
  const TripCreatePage({super.key});

  static const String routePath = '/trips/new';

  @override
  ConsumerState<TripCreatePage> createState() => _TripCreatePageState();
}

class _TripCreatePageState extends ConsumerState<TripCreatePage> {
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late TripMemberStay _stay;
  String? _errorMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _destinationController = TextEditingController();
    _stay = TripMemberStay.defaultForNewTripEditor();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    final destination = _destinationController.text.trim();

    if (title.isEmpty || destination.isEmpty) {
      setState(() => _errorMessage = l10n.tripsCreateValidationRequired);
      return;
    }

    if (!TripMemberStay.isChronological(_stay)) {
      setState(() => _errorMessage = l10n.tripStayInvalidRange);
      return;
    }

    final startDate = TripMemberStay.parseDateKey(_stay.startDateKey);
    final endDate = TripMemberStay.parseDateKey(_stay.endDateKey);
    if (startDate == null || endDate == null) {
      setState(() => _errorMessage = l10n.tripStayInvalidRange);
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(tripsRepositoryProvider).createTrip(
            title: title,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            tripStartDayPart: _stay.startDayPart,
            tripEndDayPart: _stay.endDayPart,
          );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tripsCreateDialogTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.tripsTitleLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destinationController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.tripsDestinationLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
            },
          ),
          const SizedBox(height: 16),
          TripStayBoundsEditor(
            tripStartDate: null,
            tripEndDate: null,
            value: _stay,
            onChanged: (next) {
              setState(() {
                _stay = next;
                _errorMessage = null;
              });
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.tripsCreateAction),
          ),
        ],
      ),
    );
  }
}
