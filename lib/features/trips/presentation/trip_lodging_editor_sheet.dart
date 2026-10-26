import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/presentation/trip_activity_place_field.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';
import 'package:planerz/features/trips/data/trip_lodgings_repository.dart';
import 'package:planerz/features/trips/presentation/trip_date_range_picker_sheet.dart';
import 'package:planerz/features/trips/presentation/trip_lodging_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// What the lodging stage editor gives back.
class TripLodgingStageEdit {
  const TripLodgingStageEdit.save({
    required TripLodging this.place,
    required this.nightKeys,
  }) : removed = false;

  const TripLodgingStageEdit.remove()
      : place = null,
        nightKeys = const [],
        removed = true;

  /// The place chosen, under the id of the lodging it stands for (empty for
  /// a new one).
  final TripLodging? place;
  final List<String> nightKeys;

  /// The stage is no longer filled in.
  final bool removed;
}

/// [lodgings] once [edit] of [stage] is applied, for the trip [nights].
List<TripLodging> applyTripLodgingStageEdit({
  required List<TripLodging> lodgings,
  required List<DateTime> nights,
  required TripLodgingStage stage,
  required TripLodgingStageEdit edit,
}) {
  final tripNightKeys = [for (final night in nights) tripNightKey(night)];
  final previous = stage.lodging;
  if (edit.removed) {
    if (previous == null) return lodgings;
    return removeTripLodgingStage(
      lodgings: lodgings,
      tripNightKeys: tripNightKeys,
      previous: previous,
      previousNightKeys: stage.nightKeys,
    );
  }
  return applyTripLodgingStage(
    lodgings: lodgings,
    tripNightKeys: tripNightKeys,
    previous: previous,
    previousNightKeys: stage.nightKeys,
    nightKeys: edit.nightKeys,
    place: edit.place!,
  );
}

/// Opens the editor on [stage] of [trip] and stores the change right away.
Future<void> editTripLodgingStageNow(
  BuildContext context, {
  required Trip trip,
  required List<TripLodging> stored,
  required TripLodgingStage stage,
}) async {
  final lodgings = effectiveTripLodgings(trip, stored);
  final nights = tripNights(trip);
  final edit = await showTripLodgingStageEditor(
    context,
    tripId: trip.id,
    tripNights: nights,
    stage: stage,
    lodgings: lodgings,
  );
  if (edit == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final next = applyTripLodgingStageEdit(
    lodgings: lodgings,
    nights: nights,
    stage: stage,
    edit: edit,
  );
  try {
    await ProviderScope.containerOf(context, listen: false)
        .read(tripLodgingsRepositoryProvider)
        .saveLodgings(tripId: trip.id, next: next, stored: stored);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
    );
  }
}

/// Bottom sheet to set where the nights of [stage] are spent: the nights
/// (within [tripNights]), the place's name, address and link, or one of the
/// trip's [lodgings] already filled in.
Future<TripLodgingStageEdit?> showTripLodgingStageEditor(
  BuildContext context, {
  required String tripId,
  required List<DateTime> tripNights,
  required TripLodgingStage stage,
  required List<TripLodging> lodgings,
}) {
  return showModalBottomSheet<TripLodgingStageEdit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TripLodgingStageEditor(
      tripId: tripId,
      tripNights: tripNights,
      stage: stage,
      lodgings: lodgings,
    ),
  );
}

class _TripLodgingStageEditor extends StatefulWidget {
  const _TripLodgingStageEditor({
    required this.tripId,
    required this.tripNights,
    required this.stage,
    required this.lodgings,
  });

  final String tripId;
  final List<DateTime> tripNights;
  final TripLodgingStage stage;
  final List<TripLodging> lodgings;

  @override
  State<_TripLodgingStageEditor> createState() =>
      _TripLodgingStageEditorState();
}

class _TripLodgingStageEditorState extends State<_TripLodgingStageEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _linkController;
  GeoPoint? _location;

  /// The lodging the place stands for: the stage's, or one picked among the
  /// trip's.
  TripLodging? _base;
  DateTime? _firstNight;
  DateTime? _checkOutDay;
  String? _error;

  @override
  void initState() {
    super.initState();
    final lodging = widget.stage.lodging;
    _base = lodging;
    _nameController = TextEditingController(text: lodging?.name ?? '');
    _addressController = TextEditingController(text: lodging?.address ?? '');
    _linkController = TextEditingController(text: lodging?.linkUrl ?? '');
    _location = lodging?.location;
    _firstNight = widget.stage.firstNight;
    _checkOutDay = widget.stage.checkOutDay;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  List<TripLodging> get _otherLodgings => [
        for (final lodging in widget.lodgings)
          if (lodging.id != widget.stage.lodging?.id && lodging.hasPlace)
            lodging,
      ];

  void _reuse(TripLodging lodging) {
    setState(() {
      _base = lodging;
      _nameController.text = lodging.name;
      _addressController.text = lodging.address;
      _linkController.text = lodging.linkUrl;
      _location = lodging.location;
      _error = null;
    });
  }

  Future<void> _pickNights() async {
    final nights = widget.tripNights;
    if (nights.isEmpty) return;
    final first = nights.first;
    final last = nights.last;
    final tripCheckOut = DateTime(last.year, last.month, last.day + 1);
    final result = await showTripDateRangePickerSheet(
      context: context,
      style: const TripDateRangePickerStyle(
        primary: AppTokens.primary,
        primarySoft: AppTokens.primarySoft,
        primaryTint: AppTokens.primaryTint,
        deep: AppTokens.deep,
        onSurfaceVariant: AppTokens.onSurfaceVariant,
        divider: AppTokens.divider,
        outline: AppTokens.outline,
        surface: AppTokens.surface,
        textSecondary: AppTokens.text700,
      ),
      initialStart: _firstNight ?? first,
      initialEnd: _checkOutDay ?? tripCheckOut,
      firstDate: first,
      lastDate: tripCheckOut,
    );
    if (!mounted || result == null) return;
    var start = DateUtils.dateOnly(result.start);
    var end = DateUtils.dateOnly(result.end);
    // A single day picked stands for its night.
    if (!end.isAfter(start)) {
      end = DateTime(start.year, start.month, start.day + 1);
    }
    if (end.isAfter(tripCheckOut)) {
      end = tripCheckOut;
      start = DateTime(end.year, end.month, end.day - 1);
    }
    setState(() {
      _firstNight = start;
      _checkOutDay = end;
      _error = null;
    });
  }

  String? _linkError(String value) {
    final l10n = AppLocalizations.of(context)!;
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute) return l10n.tripOverviewLinkInvalid;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return l10n.tripOverviewLinkMustStartWithHttp;
    }
    return null;
  }

  void _save() {
    final l10n = AppLocalizations.of(context)!;
    final link = _linkController.text.trim();
    final linkError = _linkError(link);
    if (linkError != null) {
      setState(() => _error = linkError);
      return;
    }
    final base = _base;
    final place = TripLodging(
      id: base?.id ?? '',
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      location: _location,
      linkUrl: link,
      linkPreview: base != null && base.linkUrl.trim() == link
          ? base.linkPreview
          : const {},
    );
    if (!place.hasPlace) {
      setState(() => _error = l10n.tripLodgingPlaceRequired);
      return;
    }
    final first = _firstNight;
    final checkOut = _checkOutDay;
    Navigator.of(context).pop(
      TripLodgingStageEdit.save(
        place: place,
        nightKeys: [
          for (final night in tripNightsBetween(first, checkOut))
            tripNightKey(night),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final others = _otherLodgings;
    final hasNights = widget.tripNights.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tripLodgingTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (hasNights) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickNights,
                icon: const Icon(PhosphorIconsRegular.calendarDots),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tripLodgingNightsLabel(
                      context,
                      firstNight: _firstNight,
                      checkOutDay: _checkOutDay,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.tripLodgingReuseLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lodging in others)
                    ChoiceChip(
                      avatar: const Icon(PhosphorIconsRegular.bed, size: 18),
                      label: Text(
                        lodging.displayTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: _base?.id == lodging.id,
                      onSelected: (_) => _reuse(lodging),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.commonName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TripActivityPlaceField(
              tripId: widget.tripId,
              controller: _addressController,
              location: _location,
              onLocationChanged: (location) => setState(() {
                _location = location;
                _error = null;
              }),
              labelText: l10n.tripLodgingAddressLabel,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.tripOverviewLinkLabel,
                hintText: l10n.tripCreateLinkPlaceholder,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppTokens.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.stage.lodging != null)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop(const TripLodgingStageEdit.remove()),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTokens.error,
                    ),
                    icon: const Icon(PhosphorIconsRegular.trash),
                    label: Text(l10n.tripLodgingRemove),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
