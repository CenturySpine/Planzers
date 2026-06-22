import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/presentation/trip_date_range_picker_sheet.dart';
import 'package:planerz/features/trips/presentation/trip_participant_stay_dates_editor.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
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
    this.grouped = false,
    this.showOptionsSection = true,
    this.staySectionLabel,
    this.optionsSectionLabel,
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
  final bool grouped;
  final bool showOptionsSection;
  final String? staySectionLabel;
  final String? optionsSectionLabel;

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
    if (_showStayDates && !_isDraft) {
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
    if (oldWidget.showStayDates != widget.showStayDates ||
        oldWidget.mode != widget.mode) {
      _tabController?.dispose();
      _tabController = _showStayDates && !_isDraft
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

  DateTimeRange _pickerBounds() {
    final tripStart = widget.tripStartDate;
    final tripEnd = widget.tripEndDate;
    if (tripStart != null && tripEnd != null) {
      final a = DateUtils.dateOnly(tripStart);
      final b = DateUtils.dateOnly(tripEnd);
      final first = a.isBefore(b) ? a : b;
      final last = a.isBefore(b) ? b : a;
      return DateTimeRange(start: first, end: last);
    }
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year - 1),
      end: DateTime(now.year + 2, 12, 31),
    );
  }

  int _nightCount() {
    final start = TripMemberStay.parseDateKey(_stay.startDateKey);
    final end = TripMemberStay.parseDateKey(_stay.endDateKey);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays;
  }

  Future<void> _openStayDatePicker() async {
    final bounds = _pickerBounds();
    final start = TripMemberStay.parseDateKey(_stay.startDateKey) ?? bounds.start;
    final end = TripMemberStay.parseDateKey(_stay.endDateKey) ?? start;
    final result = await showTripDateRangePickerSheet(
      context: context,
      style: neonTripDateRangePickerStyle(),
      initialStart: start,
      initialEnd: end,
      firstDate: bounds.start,
      lastDate: bounds.end,
    );
    if (!mounted || result == null) return;
    setState(() {
      _stay = _stay.copyWith(
        startDateKey: TripMemberStay.dateKeyFromDateTime(result.start),
        endDateKey: TripMemberStay.dateKeyFromDateTime(result.end),
      );
    });
    _emitDraft();
  }

  String _phoneVisibilityLabel(
    AppLocalizations l10n,
    TripMemberPhoneVisibility visibility,
  ) {
    return switch (visibility) {
      TripMemberPhoneVisibility.nobody => l10n.tripPhoneVisibilityPersonne,
      TripMemberPhoneVisibility.owner => l10n.tripPhoneVisibilityCreateur,
      TripMemberPhoneVisibility.admin => l10n.tripPhoneVisibilityAdmin,
      TripMemberPhoneVisibility.participant =>
        l10n.tripPhoneVisibilityParticipant,
    };
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
                        return DropdownMenuItem(
                          value: visibility,
                          child: Text(
                            _phoneVisibilityLabel(l10n, visibility),
                          ),
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

  Widget _buildCupidonRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cupidonSectionEnabled = widget.isCupidonModeEnabled;
    final cupidonDescription = cupidonSectionEnabled
        ? (widget.cupidonSubtitle ?? l10n.cupidonModeExplanation)
        : l10n.cupidonModeDisabledByAdmin;
    final disabledTextColor = NeonPalette.outline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.cupidonTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cupidonSectionEnabled
                      ? NeonPalette.deep
                      : disabledTextColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                cupidonDescription,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: cupidonSectionEnabled
                      ? NeonPalette.onSurfaceVariant
                      : disabledTextColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        TripNeonSwitch(
          value: _cupidonEnabled,
          onChanged: cupidonSectionEnabled && !_isUpdatingCupidon
              ? _handleCupidonChanged
              : null,
        ),
      ],
    );
  }

  Widget _buildPhoneVisibilityRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasPhoneNumber = _phoneVisibility != null;
    final phoneDisabled = !hasPhoneNumber;
    final disabledTextColor = NeonPalette.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.phoneVisibilityTitle!,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: phoneDisabled ? disabledTextColor : NeonPalette.deep,
          ),
        ),
        const SizedBox(height: 10),
        if (phoneDisabled)
          const _NeonSelectShell(
            value: '—',
            enabled: false,
          )
        else
          PopupMenuButton<TripMemberPhoneVisibility>(
            enabled: !_isUpdatingPhoneVisibility,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: _handlePhoneVisibilityChanged,
            itemBuilder: (menuContext) {
              return TripMemberPhoneVisibility.values.map((visibility) {
                final selected = _phoneVisibility == visibility;
                return PopupMenuItem<TripMemberPhoneVisibility>(
                  value: visibility,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _phoneVisibilityLabel(l10n, visibility),
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected
                                ? NeonPalette.primary
                                : NeonPalette.deep,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check,
                          size: 20,
                          color: NeonPalette.primary,
                        ),
                    ],
                  ),
                );
              }).toList();
            },
            child: _NeonSelectShell(
              value: _phoneVisibilityLabel(l10n, _phoneVisibility!),
              enabled: true,
            ),
          ),
        if (phoneDisabled) ...[
          const SizedBox(height: 8),
          Text(
            l10n.tripPhoneVisibilityRequiresProfileNumber,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: disabledTextColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDraftNeonOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TripNeonSectionHeader(
          icon: Icons.tune,
          label: l10n.tripMemberStayOptionsTab,
        ),
        TripNeonOptCard(
          disabled: !widget.isCupidonModeEnabled,
          child: _buildCupidonRow(context),
        ),
        if (widget.phoneVisibilityTitle != null)
          TripNeonOptCard(
            disabled: _phoneVisibility == null,
            child: _buildPhoneVisibilityRow(context),
          ),
      ],
    );
  }

  Widget _buildGroupedDraftLayout(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final startDate = TripMemberStay.parseDateKey(_stay.startDateKey) ??
        DateUtils.dateOnly(DateTime.now());
    final endDate =
        TripMemberStay.parseDateKey(_stay.endDateKey) ?? startDate;
    final nights = _nightCount();
    final stayLabel =
        widget.staySectionLabel ?? l10n.tripUserPreferencesStaySection;
    final optionsLabel = widget.optionsSectionLabel ??
        l10n.tripUserPreferencesOptionsSection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showStayDates) ...[
          TripNeonSectionHeader(
            icon: Icons.event_available,
            label: stayLabel,
          ),
          TripNeonPrefGroup(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TripStayDateCard(
                          kicker: l10n.tripStayFromLabel,
                          kickerIcon: Icons.flight_takeoff,
                          value: formatTripStayShortDate(context, startDate),
                          onTap: _openStayDatePicker,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TripStayDateCard(
                          kicker: l10n.tripStayToLabel,
                          kickerIcon: Icons.flight_land,
                          value: formatTripStayShortDate(context, endDate),
                          onTap: _openStayDatePicker,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.tripCreateNightsDays(nights, nights + 1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NeonPalette.primary,
                    ),
                  ),
                ],
              ),
              TripMealBoundCard(
                bordered: false,
                dayLabel: l10n.tripCreateArrivalMealDay(
                  formatTripStayShortDate(context, startDate),
                ),
                dayIcon: Icons.flight_takeoff,
                question: l10n.tripCreateFirstMealQuestion,
                selected: _stay.startDayPart,
                onSelected: (part) {
                  setState(() => _stay = _stay.copyWith(startDayPart: part));
                  _emitDraft();
                },
              ),
              TripMealBoundCard(
                bordered: false,
                dayLabel: l10n.tripCreateDepartureMealDay(
                  formatTripStayShortDate(context, endDate),
                ),
                dayIcon: Icons.flight_land,
                question: l10n.tripCreateLastMealQuestion,
                selected: _stay.endDayPart,
                onSelected: (part) {
                  setState(() => _stay = _stay.copyWith(endDayPart: part));
                  _emitDraft();
                },
              ),
            ],
          ),
        ],
        if (widget.showOptionsSection) ...[
          TripNeonSectionHeader(
            icon: Icons.tune,
            label: optionsLabel,
          ),
          TripNeonPrefGroup(
            children: [
              _buildCupidonRow(context),
              if (widget.phoneVisibilityTitle != null)
                _buildPhoneVisibilityRow(context),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDraftUnifiedScroll(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final startDate = TripMemberStay.parseDateKey(_stay.startDateKey) ??
        DateUtils.dateOnly(DateTime.now());
    final endDate =
        TripMemberStay.parseDateKey(_stay.endDateKey) ?? startDate;
    final nights = _nightCount();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showStayDates) ...[
          TripNeonSectionHeader(
            icon: Icons.event_available,
            label: l10n.tripStayPresenceDatesTitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TripStayDateCard(
                    kicker: l10n.tripCreateDateStartLabel,
                    kickerIcon: Icons.flight_takeoff,
                    value: formatTripStayShortDate(context, startDate),
                    onTap: _openStayDatePicker,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TripStayDateCard(
                    kicker: l10n.tripCreateDateEndLabel,
                    kickerIcon: Icons.flight_land,
                    value: formatTripStayShortDate(context, endDate),
                    onTap: _openStayDatePicker,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              l10n.tripCreateNightsDays(nights, nights + 1),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NeonPalette.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TripMealBoundCard(
              dayLabel: l10n.tripCreateArrivalMealDay(
                formatTripStayShortDate(context, startDate),
              ),
              dayIcon: Icons.flight_takeoff,
              question: l10n.tripCreateFirstMealQuestion,
              selected: _stay.startDayPart,
              onSelected: (part) {
                setState(() => _stay = _stay.copyWith(startDayPart: part));
                _emitDraft();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TripMealBoundCard(
              dayLabel: l10n.tripCreateDepartureMealDay(
                formatTripStayShortDate(context, endDate),
              ),
              dayIcon: Icons.flight_land,
              question: l10n.tripCreateLastMealQuestion,
              selected: _stay.endDayPart,
              onSelected: (part) {
                setState(() => _stay = _stay.copyWith(endDayPart: part));
                _emitDraft();
              },
            ),
          ),
        ],
        _buildDraftNeonOptions(context),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDraft) {
      if (widget.grouped) {
        return _buildGroupedDraftLayout(context);
      }
      return _buildDraftUnifiedScroll(context);
    }

    final l10n = AppLocalizations.of(context)!;
    final showStayTab = _showStayDates && (_tabController?.index ?? 0) == 0;
    final showOptionsTab = !_showStayDates || (_tabController?.index ?? 1) == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            onDraftChanged: null,
            onLiveChanged: widget.onLiveStayChanged,
          ),
        if (showOptionsTab) _buildOptionsTab(context),
      ],
    );
  }
}

class _NeonSelectShell extends StatelessWidget {
  const _NeonSelectShell({
    required this.value,
    required this.enabled,
  });

  final String value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? NeonPalette.deep : NeonPalette.outline;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled
            ? NeonPalette.surface
            : Color.lerp(NeonPalette.surface, NeonPalette.outline, 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeonPalette.divider, width: 1.5),
      ),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more,
                size: 22,
                color: enabled
                    ? NeonPalette.onSurfaceVariant
                    : NeonPalette.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
