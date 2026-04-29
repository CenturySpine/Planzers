import 'package:flutter/material.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/presentation/trip_stay_bounds_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

enum TripMemberStayOptionsEditorMode {
  draft,
  live,
}

class TripMemberStayOptionsDraft {
  const TripMemberStayOptionsDraft({
    required this.stay,
    required this.cupidonEnabled,
    required this.phoneVisibility,
  });

  final TripMemberStay stay;
  final bool cupidonEnabled;
  final TripMemberPhoneVisibility? phoneVisibility;
}

class TripMemberStayOptionsEditor extends StatefulWidget {
  const TripMemberStayOptionsEditor({
    super.key,
    required this.mode,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.initialStay,
    required this.initialCupidonEnabled,
    this.initialPhoneVisibility,
    this.onDraftChanged,
    this.onLiveStayChanged,
    this.onLiveCupidonChanged,
    this.onLivePhoneVisibilityChanged,
    required this.cupidonTitle,
    this.cupidonSubtitle,
    this.phoneVisibilityTitle,
  }) : assert(
          mode == TripMemberStayOptionsEditorMode.draft
              ? onDraftChanged != null
              : onLiveStayChanged != null && onLiveCupidonChanged != null,
        );

  final TripMemberStayOptionsEditorMode mode;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final TripMemberStay initialStay;
  final bool initialCupidonEnabled;
  final TripMemberPhoneVisibility? initialPhoneVisibility;
  final ValueChanged<TripMemberStayOptionsDraft>? onDraftChanged;
  final Future<void> Function(TripMemberStay stay)? onLiveStayChanged;
  final Future<void> Function(bool enabled)? onLiveCupidonChanged;
  final Future<void> Function(TripMemberPhoneVisibility visibility)?
      onLivePhoneVisibilityChanged;
  final String cupidonTitle;
  final String? cupidonSubtitle;
  final String? phoneVisibilityTitle;

  @override
  State<TripMemberStayOptionsEditor> createState() =>
      _TripMemberStayOptionsEditorState();
}

class _TripMemberStayOptionsEditorState extends State<TripMemberStayOptionsEditor> {
  late TripMemberStay _stay;
  late bool _cupidonEnabled;
  TripMemberPhoneVisibility? _phoneVisibility;
  bool _isUpdatingStay = false;
  bool _isUpdatingCupidon = false;
  bool _isUpdatingPhoneVisibility = false;

  bool get _isDraft => widget.mode == TripMemberStayOptionsEditorMode.draft;

  @override
  void initState() {
    super.initState();
    _stay = widget.initialStay;
    _cupidonEnabled = widget.initialCupidonEnabled;
    _phoneVisibility = widget.initialPhoneVisibility;
  }

  @override
  void didUpdateWidget(covariant TripMemberStayOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDraft &&
        !_isUpdatingStay &&
        oldWidget.initialStay != widget.initialStay) {
      _stay = widget.initialStay;
    }
    if (!_isDraft &&
        !_isUpdatingCupidon &&
        oldWidget.initialCupidonEnabled != widget.initialCupidonEnabled) {
      _cupidonEnabled = widget.initialCupidonEnabled;
    }
    if (!_isDraft &&
        !_isUpdatingPhoneVisibility &&
        oldWidget.initialPhoneVisibility != widget.initialPhoneVisibility) {
      _phoneVisibility = widget.initialPhoneVisibility;
    }
  }

  void _emitDraft() {
    widget.onDraftChanged?.call(
      TripMemberStayOptionsDraft(
        stay: _stay,
        cupidonEnabled: _cupidonEnabled,
        phoneVisibility: _phoneVisibility,
      ),
    );
  }

  Future<void> _handleStayChanged(TripMemberStay nextStay) async {
    if (_isDraft) {
      setState(() => _stay = nextStay);
      _emitDraft();
      return;
    }
    if (_isUpdatingStay || widget.onLiveStayChanged == null) return;
    final previousStay = _stay;
    setState(() {
      _stay = nextStay;
      _isUpdatingStay = true;
    });
    try {
      await widget.onLiveStayChanged!(nextStay);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stay = previousStay);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStay = false);
      }
    }
  }

  Future<void> _handleCupidonChanged(bool enabled) async {
    if (_isDraft) {
      setState(() => _cupidonEnabled = enabled);
      _emitDraft();
      return;
    }
    if (_isUpdatingCupidon || widget.onLiveCupidonChanged == null) return;
    final previousCupidonEnabled = _cupidonEnabled;
    setState(() {
      _cupidonEnabled = enabled;
      _isUpdatingCupidon = true;
    });
    try {
      await widget.onLiveCupidonChanged!(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cupidonEnabled = previousCupidonEnabled);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingCupidon = false);
      }
    }
  }

  Future<void> _handlePhoneVisibilityChanged(
    TripMemberPhoneVisibility visibility,
  ) async {
    if (_isDraft) {
      setState(() => _phoneVisibility = visibility);
      _emitDraft();
      return;
    }
    if (_isUpdatingPhoneVisibility ||
        widget.onLivePhoneVisibilityChanged == null) {
      return;
    }
    final previousPhoneVisibility = _phoneVisibility;
    setState(() {
      _phoneVisibility = visibility;
      _isUpdatingPhoneVisibility = true;
    });
    try {
      await widget.onLivePhoneVisibilityChanged!(visibility);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phoneVisibility = previousPhoneVisibility);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingPhoneVisibility = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TripStayBoundsEditor(
          tripStartDate: widget.tripStartDate,
          tripEndDate: widget.tripEndDate,
          value: _stay,
          onChanged: _handleStayChanged,
        ),
        const SizedBox(height: 20),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _cupidonEnabled,
          onChanged: _isUpdatingCupidon ? null : _handleCupidonChanged,
          title: Text(widget.cupidonTitle),
          subtitle: widget.cupidonSubtitle == null
              ? null
              : Text(widget.cupidonSubtitle!),
        ),
        if (_phoneVisibility != null && widget.phoneVisibilityTitle != null) ...[
          const SizedBox(height: 20),
          Text(
            widget.phoneVisibilityTitle!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TripMemberPhoneVisibility>(
            initialValue: _phoneVisibility,
            onChanged: (_isUpdatingPhoneVisibility ||
                    (_isDraft
                        ? _phoneVisibility == null
                        : widget.onLivePhoneVisibilityChanged == null))
                ? null
                : (value) {
                    if (value != null) {
                      _handlePhoneVisibilityChanged(value);
                    }
                  },
            items: TripMemberPhoneVisibility.values.map((visibility) {
              String label;
              switch (visibility) {
                case TripMemberPhoneVisibility.nobody:
                  label = l10n.tripPhoneVisibilityPersonne;
                case TripMemberPhoneVisibility.owner:
                  label = l10n.tripPhoneVisibilityCreateur;
                case TripMemberPhoneVisibility.admin:
                  label = l10n.tripPhoneVisibilityAdmin;
                case TripMemberPhoneVisibility.participant:
                  label = l10n.tripPhoneVisibilityParticipant;
              }
              return DropdownMenuItem(
                value: visibility,
                child: Text(label),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
