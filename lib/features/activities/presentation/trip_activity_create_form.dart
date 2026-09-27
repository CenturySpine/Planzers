import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Activity creation form, shared by the full-screen page and the panel
/// opened next to a wallet document.
class TripActivityCreateForm extends ConsumerStatefulWidget {
  const TripActivityCreateForm({
    super.key,
    required this.tripId,
    required this.onCreated,
    this.allowedCategories,
    this.initialCategory,
    this.initialLabel = '',
    this.initialPlannedDay,
    this.scrollController,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final String tripId;

  /// Called with the new activity id once saved.
  final ValueChanged<String> onCreated;

  /// When set, restricts the category picker to these categories and pre-selects the first one.
  final List<TripActivityCategory>? allowedCategories;

  /// Pre-selected category (defaults to the first allowed one).
  final TripActivityCategory? initialCategory;
  final String initialLabel;

  /// Day the date picker opens on (e.g. the date of a travel document).
  final DateTime? initialPlannedDay;
  final ScrollController? scrollController;

  /// Scrolls with the fields (e.g. a sheet's drag handle and title).
  final Widget? header;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<TripActivityCreateForm> createState() =>
      _TripActivityCreateFormState();
}

class _TripActivityCreateFormState
    extends ConsumerState<TripActivityCreateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _linkController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  late TripActivityCategory _category;
  bool _saving = false;
  DateTime? _plannedAt;

  /// Custom duration; null follows the category default.
  int? _durationMinutes;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ??
        widget.allowedCategories?.first ??
        TripActivityCategory.visit;
    _labelController = TextEditingController(text: widget.initialLabel);
    _linkController = TextEditingController();
    _addressController = TextEditingController();
    _commentsController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _linkController.dispose();
    _addressController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  String? _validateOptionalUrl(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final trimmedValue = (value ?? '').trim();
    if (trimmedValue.isEmpty) return null;
    final uri = Uri.tryParse(trimmedValue);
    if (uri == null || !uri.isAbsolute) {
      return l10n.linkInvalidExample;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return l10n.activitiesLinkMustStartHttp;
    }
    return null;
  }

  Future<DateTime?> _pickPlannedDateTime() async {
    final now = DateTime.now();
    final localPlannedAt = _plannedAt?.toLocal();
    final initialDate =
        DateUtils.dateOnly(localPlannedAt ?? widget.initialPlannedDay ?? now);
    final minSelectableDate = DateTime(now.year - 5);
    final maxSelectableDate = DateTime(now.year + 5);
    final pickedDate = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initialDate,
      firstDate: initialDate.isBefore(minSelectableDate)
          ? initialDate
          : minSelectableDate,
      lastDate: initialDate.isAfter(maxSelectableDate)
          ? initialDate
          : maxSelectableDate,
      helpText: AppLocalizations.of(context)!.activitiesPlannedDateHelp,
    );
    if (pickedDate == null || !mounted) return null;
    final initialTime = TimeOfDay.fromDateTime(localPlannedAt ?? now);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return null;
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _submit({required bool canPlanActivity}) async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      final activityId = await ref.read(activitiesRepositoryProvider).addActivity(
            tripId: widget.tripId,
            label: _labelController.text,
            category: _category,
            linkUrl: _linkController.text,
            address: _addressController.text,
            freeComments: _commentsController.text,
            plannedAt: canPlanActivity ? _plannedAt : null,
            durationMinutes: canPlanActivity ? _durationMinutes : null,
          );
      if (!mounted) return;
      widget.onCreated(activityId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final canPlanActivity = tripAsync.maybeWhen(
      data: (trip) => trip != null
          ? canPlanActivityForTrip(
              trip: trip,
              userId: myUid,
            )
          : false,
      orElse: () => false,
    );

    return Form(
      key: _formKey,
      child: ListView(
        controller: widget.scrollController,
        padding: widget.padding,
        children: [
          if (widget.header != null) widget.header!,
          Text(
            l10n.activitiesCategory,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category
                  in widget.allowedCategories ?? TripActivityCategory.values)
                FilterChip(
                  avatar: Icon(category.categoryIcon, size: 18),
                  label: Text(category.label(l10n)),
                  selected: _category == category,
                  onSelected:
                      _saving || (widget.allowedCategories?.length == 1)
                          ? null
                          : (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _labelController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.activitiesLabel,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return l10n.activitiesLabelRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _linkController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ).copyWith(
              labelText: l10n.activitiesLink,
            ),
            keyboardType: TextInputType.url,
            validator: _validateOptionalUrl,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.activitiesAddress,
              hintText: l10n.activitiesAddressHint,
              border: const OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _commentsController,
            textInputAction:
                canPlanActivity ? TextInputAction.next : TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.activitiesComments,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 6,
          ),
          if (canPlanActivity) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.activitiesTabPlanned,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final pickedDateTime =
                                  await _pickPlannedDateTime();
                              if (pickedDateTime == null || !mounted) return;
                              setState(() => _plannedAt = pickedDateTime);
                            },
                      icon: const Icon(PhosphorIconsRegular.calendar),
                      label: Text(
                        _plannedAt == null
                            ? l10n.activitiesPlannedUnset
                            : l10n.activitiesPlannedOn(
                                DateFormat.yMMMMd(
                                  Localizations.localeOf(context).toString(),
                                ).add_Hm().format(_plannedAt!.toLocal()),
                              ),
                      ),
                    ),
                    TripActivityDurationButton(
                      category: _category,
                      durationMinutes: _durationMinutes,
                      onChanged: _saving
                          ? null
                          : (minutes) =>
                              setState(() => _durationMinutes = minutes),
                    ),
                    if (_plannedAt != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _plannedAt = null),
                        child: Text(l10n.activitiesRemovePlannedDate),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving
                ? null
                : () => _submit(canPlanActivity: canPlanActivity),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
