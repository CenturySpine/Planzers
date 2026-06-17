import 'package:flutter/material.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/presentation/trip_participant_stay_dates_editor.dart';
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
    this.isCupidonModeEnabled = true,
    this.showStayDates = true,
    this.trip,
  }) : assert(
          mode == TripMemberStayOptionsEditorMode.draft
              ? onDraftChanged != null
              : onLiveCupidonChanged != null &&
                  (showStayDates ? onLiveStayChanged != null : true),
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
  final bool isCupidonModeEnabled;
  final bool showStayDates;
  final Trip? trip;

  @override
  State<TripMemberStayOptionsEditor> createState() =>
      _TripMemberStayOptionsEditorState();
}

class _TripMemberStayOptionsEditorState extends State<TripMemberStayOptionsEditor>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  late TripMemberStay _stay;
  late bool _cupidonEnabled;
  TripMemberPhoneVisibility? _phoneVisibility;
  bool _isUpdatingCupidon = false;
  bool _isUpdatingPhoneVisibility = false;

  bool get _isDraft => widget.mode == TripMemberStayOptionsEditorMode.draft;
  bool get _showStayDates => widget.showStayDates;

  @override
  void initState() {
    super.initState();
    if (_showStayDates) {
      _tabController = TabController(length: 2, vsync: this)
        ..addListener(() => setState(() {}));
    }
    _stay = widget.initialStay;
    _cupidonEnabled = widget.initialCupidonEnabled;
    _phoneVisibility = widget.initialPhoneVisibility;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TripMemberStayOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showStayDates != widget.showStayDates) {
      _tabController?.dispose();
      _tabController = widget.showStayDates
          ? (TabController(length: 2, vsync: this)
            ..addListener(() => setState(() {})))
          : null;
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
    if (_isDraft && oldWidget.initialStay != widget.initialStay) {
      _stay = widget.initialStay;
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

  Widget _buildOptionsTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cupidonSectionEnabled = widget.isCupidonModeEnabled;
    final cupidonDescription = cupidonSectionEnabled
        ? l10n.cupidonModeExplanation
        : l10n.cupidonModeDisabledByAdmin;
    final hasPhoneNumber = _phoneVisibility != null;
    final phoneVisibilitySectionEnabled = hasPhoneNumber &&
        !_isUpdatingPhoneVisibility &&
        (_isDraft || widget.onLivePhoneVisibilityChanged != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _cupidonEnabled,
              onChanged: (_isUpdatingCupidon || !cupidonSectionEnabled)
                  ? null
                  : _handleCupidonChanged,
              title: Text(widget.cupidonTitle),
              subtitle: Text(cupidonDescription),
            ),
          ),
        ),
        if (widget.phoneVisibilityTitle != null) ...[
          const SizedBox(height: 6),
          Card(
            child: Opacity(
              opacity: hasPhoneNumber ? 1.0 : 0.38,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.phoneVisibilityTitle!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasPhoneNumber
                                ? l10n.tripPhoneVisibilitySubtitle
                                : l10n.tripPhoneVisibilityRequiresProfileNumber,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<TripMemberPhoneVisibility>(
                      value: _phoneVisibility,
                      onChanged: phoneVisibilitySectionEnabled
                          ? (value) {
                              if (value != null) {
                                _handlePhoneVisibilityChanged(value);
                              }
                            }
                          : null,
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
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showStayTab = _showStayDates && (_tabController?.index ?? 0) == 0;
    final showOptionsTab = !_showStayDates || (_tabController?.index ?? 1) == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isDraft) ...[
          Card(
            color: context.planerzColors.successContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.inviteOptionsEditableAfterJoinInfo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (_showStayDates) ...[
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: l10n.tripStayPresenceDatesTitle),
              Tab(text: l10n.tripMemberStayOptionsTab),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (showStayTab)
          TripParticipantStayDatesEditor(
            mode: widget.mode,
            tripStartDate: widget.tripStartDate,
            tripEndDate: widget.tripEndDate,
            initialStay: _stay,
            trip: widget.trip,
            showTitle: false,
            onDraftChanged: _isDraft
                ? (stay) {
                    setState(() => _stay = stay);
                    _emitDraft();
                  }
                : null,
            onLiveChanged: !_isDraft ? widget.onLiveStayChanged : null,
          ),
        if (showOptionsTab) _buildOptionsTab(context),
      ],
    );
  }
}
