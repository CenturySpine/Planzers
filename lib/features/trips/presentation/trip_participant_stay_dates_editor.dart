import 'package:flutter/material.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/presentation/trip_calendar_stay_bounds_field.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripParticipantStayDatesEditor extends StatefulWidget {
  const TripParticipantStayDatesEditor({
    super.key,
    required this.mode,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.initialStay,
    this.trip,
    this.onDraftChanged,
    this.onLiveChanged,
    this.showTitle = true,
  }) : assert(
          mode == TripMemberStayOptionsEditorMode.draft
              ? onDraftChanged != null
              : onLiveChanged != null,
        );

  final TripMemberStayOptionsEditorMode mode;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final TripMemberStay initialStay;
  final Trip? trip;
  final ValueChanged<TripMemberStay>? onDraftChanged;
  final Future<void> Function(TripMemberStay stay)? onLiveChanged;
  final bool showTitle;

  @override
  State<TripParticipantStayDatesEditor> createState() =>
      _TripParticipantStayDatesEditorState();
}

class _TripParticipantStayDatesEditorState
    extends State<TripParticipantStayDatesEditor> {
  late TripMemberStay _stay;
  bool _isUpdatingStay = false;

  bool get _isDraft =>
      widget.mode == TripMemberStayOptionsEditorMode.draft;

  @override
  void initState() {
    super.initState();
    _stay = widget.initialStay;
  }

  @override
  void didUpdateWidget(covariant TripParticipantStayDatesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDraft &&
        !_isUpdatingStay &&
        oldWidget.initialStay != widget.initialStay) {
      _stay = widget.initialStay;
    }
  }

  bool _validateStay(TripMemberStay nextStay) {
    final l10n = AppLocalizations.of(context)!;
    if (!TripMemberStay.isChronological(nextStay)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayInvalidRange)),
      );
      return false;
    }
    if (widget.trip != null &&
        !TripMemberStay.withinTripCalendarBounds(
          stay: nextStay,
          trip: widget.trip!,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayOutOfTripBounds)),
      );
      return false;
    }
    return true;
  }

  Future<void> _handleStayChanged(TripMemberStay nextStay) async {
    if (_isDraft) {
      setState(() => _stay = nextStay);
      widget.onDraftChanged?.call(nextStay);
      return;
    }
    if (_isUpdatingStay || widget.onLiveChanged == null) return;
    if (!_validateStay(nextStay)) return;

    final previousStay = _stay;
    setState(() {
      _stay = nextStay;
      _isUpdatingStay = true;
    });
    try {
      await widget.onLiveChanged!(nextStay);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stay = previousStay);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStay = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle) ...[
              Text(
                l10n.tripStayPresenceDatesTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
            ],
            TripCalendarStayBoundsField(
              tripStartDate: widget.tripStartDate,
              tripEndDate: widget.tripEndDate,
              value: _stay,
              onChanged: _handleStayChanged,
            ),
          ],
        ),
      ),
    );
  }
}
