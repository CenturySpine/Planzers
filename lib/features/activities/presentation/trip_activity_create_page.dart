import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripActivityCreatePage extends ConsumerStatefulWidget {
  const TripActivityCreatePage({
    super.key,
    required this.tripId,
    this.initialCategory,
  });

  final String tripId;

  /// When set (e.g. deep link), pre-selects this category on the form.
  final TripActivityCategory? initialCategory;

  @override
  ConsumerState<TripActivityCreatePage> createState() =>
      _TripActivityCreatePageState();
}

class _TripActivityCreatePageState extends ConsumerState<TripActivityCreatePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _linkController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  late TripActivityCategory _category;
  bool _saving = false;
  DateTime? _plannedAt;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? TripActivityCategory.visit;
    _labelController = TextEditingController();
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
    final initialDate = DateUtils.dateOnly(localPlannedAt ?? now);
    final pickedDate = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
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
      await ref.read(activitiesRepositoryProvider).addActivity(
            tripId: widget.tripId,
            label: _labelController.text,
            category: _category,
            linkUrl: _linkController.text,
            address: _addressController.text,
            freeComments: _commentsController.text,
            plannedAt: canPlanActivity ? _plannedAt : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.activitiesAdded),
        ),
      );
      context.pop();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.activitiesNewActivity),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              l10n.activitiesCategory,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in TripActivityCategory.values)
                  FilterChip(
                    avatar: Icon(category.categoryIcon, size: 18),
                    label: Text(category.label(l10n)),
                    selected: _category == category,
                    onSelected: _saving
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
                        icon: const Icon(Icons.calendar_month_outlined),
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
                      if (_plannedAt != null)
                        TextButton(
                          onPressed:
                              _saving ? null : () => setState(() => _plannedAt = null),
                          child: Text(l10n.activitiesRemovePlannedDate),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : () => _submit(canPlanActivity: canPlanActivity),
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
      ),
    );
  }
}
