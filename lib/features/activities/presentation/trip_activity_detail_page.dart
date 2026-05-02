import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planerz/l10n/app_localizations.dart';

extension TripActivityCategoryPresentation on TripActivityCategory {
  IconData get categoryIcon => switch (this) {
        TripActivityCategory.sport => Icons.sports_soccer_outlined,
        TripActivityCategory.hiking => Icons.hiking_outlined,
        TripActivityCategory.shopping => Icons.shopping_bag_outlined,
        TripActivityCategory.visit => Icons.explore_outlined,
        TripActivityCategory.restaurant => Icons.restaurant_outlined,
        TripActivityCategory.cafe => Icons.local_cafe_outlined,
        TripActivityCategory.museum => Icons.museum_outlined,
        TripActivityCategory.show => Icons.theater_comedy_outlined,
        TripActivityCategory.nightlife => Icons.nightlife,
        TripActivityCategory.karaoke => Icons.mic_outlined,
        TripActivityCategory.games => Icons.sports_esports_outlined,
        TripActivityCategory.beach => Icons.beach_access,
        TripActivityCategory.park => Icons.park_outlined,
        TripActivityCategory.transport => Icons.directions_bus_outlined,
        TripActivityCategory.accommodation => Icons.hotel_outlined,
        TripActivityCategory.wellness => Icons.spa_outlined,
        TripActivityCategory.cooking => Icons.outdoor_grill,
        TripActivityCategory.workshop => Icons.palette_outlined,
        TripActivityCategory.market => Icons.storefront_outlined,
        TripActivityCategory.meeting => Icons.business_center_outlined,
      };

  String get categoryLabelFr => switch (this) {
        TripActivityCategory.sport => 'Sport',
        TripActivityCategory.hiking => 'Randonnée',
        TripActivityCategory.shopping => 'Shopping',
        TripActivityCategory.visit => 'Visite',
        TripActivityCategory.restaurant => 'Restaurant',
        TripActivityCategory.cafe => 'Café',
        TripActivityCategory.museum => 'Musée',
        TripActivityCategory.show => 'Spectacle',
        TripActivityCategory.nightlife => 'Soirée',
        TripActivityCategory.karaoke => 'Karaoké',
        TripActivityCategory.games => 'Jeux',
        TripActivityCategory.beach => 'Plage',
        TripActivityCategory.park => 'Parc',
        TripActivityCategory.transport => 'Transport',
        TripActivityCategory.accommodation => 'Hébergement',
        TripActivityCategory.wellness => 'Bien-être',
        TripActivityCategory.cooking => 'Cuisine',
        TripActivityCategory.workshop => 'Atelier',
        TripActivityCategory.market => 'Marché',
        TripActivityCategory.meeting => 'Réunion',
      };

  String label(AppLocalizations l10n) => switch (this) {
        TripActivityCategory.sport => l10n.activityCategorySport,
        TripActivityCategory.hiking => l10n.activityCategoryHiking,
        TripActivityCategory.shopping => l10n.activityCategoryShopping,
        TripActivityCategory.visit => l10n.activityCategoryVisit,
        TripActivityCategory.restaurant => l10n.activityCategoryRestaurant,
        TripActivityCategory.cafe => l10n.activityCategoryCafe,
        TripActivityCategory.museum => l10n.activityCategoryMuseum,
        TripActivityCategory.show => l10n.activityCategoryShow,
        TripActivityCategory.nightlife => l10n.activityCategoryNightlife,
        TripActivityCategory.karaoke => l10n.activityCategoryKaraoke,
        TripActivityCategory.games => l10n.activityCategoryGames,
        TripActivityCategory.beach => l10n.activityCategoryBeach,
        TripActivityCategory.park => l10n.activityCategoryPark,
        TripActivityCategory.transport => l10n.activityCategoryTransport,
        TripActivityCategory.accommodation => l10n.activityCategoryAccommodation,
        TripActivityCategory.wellness => l10n.activityCategoryWellness,
        TripActivityCategory.cooking => l10n.activityCategoryCooking,
        TripActivityCategory.workshop => l10n.activityCategoryWorkshop,
        TripActivityCategory.market => l10n.activityCategoryMarket,
        TripActivityCategory.meeting => l10n.activityCategoryMeeting,
      };
}

class TripActivityDetailPage extends ConsumerStatefulWidget {
  const TripActivityDetailPage({
    super.key,
    required this.tripId,
    required this.activityId,
  });

  final String tripId;
  final String activityId;

  @override
  ConsumerState<TripActivityDetailPage> createState() =>
      _TripActivityDetailPageState();
}

class _TripActivityDetailPageState extends ConsumerState<TripActivityDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _linkController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  TripActivityCategory _category = TripActivityCategory.visit;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;
  TripActivity? _lastSyncedActivity;

  @override
  void initState() {
    super.initState();
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

  bool _sameEditableFields(TripActivity? prev, TripActivity next) {
    if (prev == null) return false;
    return prev.label == next.label &&
        prev.linkUrl == next.linkUrl &&
        prev.address == next.address &&
        prev.freeComments == next.freeComments &&
        prev.category == next.category &&
        prev.done == next.done;
  }

  void _syncControllersWhenIdle(TripActivity activity) {
    if (_editing || _saving) return;
    if (_sameEditableFields(_lastSyncedActivity, activity)) return;
    _lastSyncedActivity = activity;
    _labelController.text = activity.label;
    _linkController.text = activity.linkUrl;
    _addressController.text = activity.address;
    _commentsController.text = activity.freeComments;
    _category = activity.category;
  }

  void _applyActivity(TripActivity activity) {
    _labelController.text = activity.label;
    _linkController.text = activity.linkUrl;
    _addressController.text = activity.address;
    _commentsController.text = activity.freeComments;
    _category = activity.category;
    _lastSyncedActivity = activity;
  }

  String? _validateOptionalUrl(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.isAbsolute) {
      return l10n.linkInvalidExample;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return l10n.activitiesLinkMustStartHttp;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(activitiesRepositoryProvider).updateActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
            label: _labelController.text,
            category: _category,
            linkUrl: _linkController.text,
            address: _addressController.text,
            freeComments: _commentsController.text,
          );
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.activitiesUpdated)),
      );
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

  void _cancelEdit(TripActivity activity) {
    _applyActivity(activity);
    setState(() => _editing = false);
  }

  Future<void> _confirmAndDelete(TripActivity activity) async {
    if (_deleting) return;
    final label =
        activity.label.trim().isEmpty
            ? AppLocalizations.of(context)!.activitiesUntitled
            : activity.label.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.activitiesDeleteTitle),
        content: Text(AppLocalizations.of(context)!.activitiesDeleteBody(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await ref.read(activitiesRepositoryProvider).deleteActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.activitiesDeleted)),
      );
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
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final docRef = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId.trim())
        .collection('activities')
        .doc(widget.activityId.trim());

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  l10n.activitiesNotFound,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final activity = TripActivity.fromDoc(doc);
        _syncControllersWhenIdle(activity);
        final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
        final canEdit = tripAsync.maybeWhen(
          data: (trip) => trip != null
              ? canEditActivityForTrip(
                  trip: trip,
                  userId: myUid,
                )
              : false,
          orElse: () => false,
        );
        final canDelete = tripAsync.maybeWhen(
          data: (trip) => trip != null
              ? canDeleteActivityForTrip(
                  trip: trip,
                  userId: myUid,
                )
              : false,
          orElse: () => false,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        activity.category.categoryIcon,
                        size: 20,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                  TextSpan(
                    text: activity.label.trim().isEmpty
                        ? l10n.activitiesUntitled
                        : activity.label.trim(),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (!_editing) ...[
                if (canEdit)
                  IconButton(
                    tooltip: l10n.commonEdit,
                    onPressed: _deleting
                        ? null
                        : () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: l10n.commonDelete,
                    onPressed: _deleting
                        ? null
                        : () => _confirmAndDelete(activity),
                    icon: _deleting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  ),
              ],
              if (canEdit && _editing) ...[
                IconButton(
                  tooltip: l10n.commonCancel,
                  onPressed: _saving ? null : () => _cancelEdit(activity),
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  tooltip: l10n.commonSave,
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ],
          ),
          body: _editing
              ? _EditBody(
                  formKey: _formKey,
                  labelController: _labelController,
                  linkController: _linkController,
                  addressController: _addressController,
                  commentsController: _commentsController,
                  category: _category,
                  onCategoryChanged: _saving
                      ? null
                      : (c) => setState(() => _category = c),
                  activity: activity,
                  validateOptionalUrl: _validateOptionalUrl,
                )
              : _ReadBody(
                  tripId: widget.tripId,
                  activity: activity,
                  canEditActivity: canEdit,
                ),
        );
      },
    );
  }
}

class _ReadBody extends ConsumerWidget {
  const _ReadBody({
    required this.tripId,
    required this.activity,
    required this.canEditActivity,
  });

  final String tripId;
  final TripActivity activity;
  final bool canEditActivity;

  Future<void> _toggleDone(
    WidgetRef ref,
    BuildContext context,
    bool value,
  ) async {
    try {
      await ref.read(activitiesRepositoryProvider).setActivityDone(
            tripId: tripId,
            activityId: activity.id,
            done: value,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<DateTime?> _pickPlannedDateTime(
    BuildContext context, {
    DateTime? tripStartDate,
  }) async {
    final now = DateTime.now();
    final localPlannedAt = activity.plannedAt?.toLocal();
    final localTripStartDate = tripStartDate?.toLocal();
    final initialDate = DateUtils.dateOnly(
      localPlannedAt ?? localTripStartDate ?? now,
    );
    final minSelectableDate = DateTime(now.year - 5);
    final maxSelectableDate = DateTime(now.year + 5);
    final firstDate = initialDate.isBefore(minSelectableDate)
        ? initialDate
        : minSelectableDate;
    final lastDate = initialDate.isAfter(maxSelectableDate)
        ? initialDate
        : maxSelectableDate;
    final pickedDate = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: AppLocalizations.of(context)!.activitiesPlannedDateHelp,
    );
    if (pickedDate == null || !context.mounted) return null;
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

  Future<void> _setPlannedDate(
    WidgetRef ref,
    BuildContext context,
    DateTime? plannedAt,
  ) async {
    try {
      await ref.read(activitiesRepositoryProvider).setActivityPlannedAt(
            tripId: tripId,
            activityId: activity.id,
            plannedAt: plannedAt,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripStreamProvider(tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final canPlanActivity = tripAsync.maybeWhen(
      data: (trip) => trip != null
          ? canPlanActivityForTrip(
              trip: trip,
              userId: myUid,
            )
          : false,
      orElse: () => false,
    );
    final tripMemberPublicLabels = tripAsync.maybeWhen(
      data: (trip) => trip?.memberPublicLabels ?? const <String, String>{},
      orElse: () => const <String, String>{},
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activity.linkUrl.trim().isNotEmpty) ...[
          LinkPreviewCardFromFirestore(
            url: activity.linkUrl.trim(),
            preview: activity.linkPreview,
          ),
          const SizedBox(height: 16),
        ],
        if (activity.address.trim().isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.activitiesAddressCardTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          activity.address.trim(),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.tripOverviewOpenLocation,
                        onPressed: () => openAddressInGoogleMaps(
                              context,
                              activity.address,
                            ),
                        icon: const Icon(Icons.location_on_outlined),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 22,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.activitiesFromLodgingByCar,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _activityDrivingRouteBodyText(
                                activity,
                                AppLocalizations.of(context)!,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.activitiesComments,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  activity.freeComments.trim().isEmpty
                      ? AppLocalizations.of(context)!.commonDash
                      : activity.freeComments.trim(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: activity.done,
                  onChanged: canEditActivity ? (v) async {
                    if (v == null) return;
                    await _toggleDone(ref, context, v);
                  } : null,
                  title: Text(AppLocalizations.of(context)!.activitiesDone),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: canPlanActivity
                      ? () async {
                          final pickedDateTime = await _pickPlannedDateTime(
                            context,
                            tripStartDate: tripAsync.maybeWhen(
                              data: (trip) => trip?.startDate,
                              orElse: () => null,
                            ),
                          );
                          if (pickedDateTime == null) return;
                          if (!context.mounted) return;
                          await _setPlannedDate(
                            ref,
                            context,
                            pickedDateTime,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    activity.plannedAt == null
                        ? AppLocalizations.of(context)!.activitiesPlannedUnset
                        : AppLocalizations.of(context)!.activitiesPlannedOn(
                            DateFormat.yMMMMd(
                              Localizations.localeOf(context).toString(),
                            ).add_Hm().format(activity.plannedAt!.toLocal()),
                          ),
                  ),
                ),
                if (activity.plannedAt != null)
                  TextButton(
                    onPressed: canPlanActivity
                        ? () => _setPlannedDate(ref, context, null)
                        : null,
                    child: Text(
                      AppLocalizations.of(context)!.activitiesRemovePlannedDate,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _VotersSection(
          tripId: tripId,
          activityId: activity.id,
          votes: activity.votes,
          myUid: myUid ?? '',
          currentUserId: myUid,
          tripMemberPublicLabels: tripMemberPublicLabels,
        ),
      ],
    );
  }
}

class _EditBody extends StatefulWidget {
  const _EditBody({
    required this.formKey,
    required this.labelController,
    required this.linkController,
    required this.addressController,
    required this.commentsController,
    required this.category,
    required this.onCategoryChanged,
    required this.activity,
    required this.validateOptionalUrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController labelController;
  final TextEditingController linkController;
  final TextEditingController addressController;
  final TextEditingController commentsController;
  final TripActivityCategory category;
  final void Function(TripActivityCategory)? onCategoryChanged;
  final TripActivity activity;
  final String? Function(String?) validateOptionalUrl;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  @override
  void initState() {
    super.initState();
    widget.linkController.addListener(_onLinkChanged);
  }

  @override
  void dispose() {
    widget.linkController.removeListener(_onLinkChanged);
    super.dispose();
  }

  void _onLinkChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final linkTrimmed = widget.linkController.text.trim();
    final savedLink = widget.activity.linkUrl.trim();
    final showLivePreview =
        linkTrimmed.isNotEmpty && linkTrimmed == savedLink;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppLocalizations.of(context)!.activitiesCategory,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in TripActivityCategory.values)
                FilterChip(
                  avatar: Icon(c.categoryIcon, size: 18),
                  label: Text(c.label(AppLocalizations.of(context)!)),
                  selected: widget.category == c,
                  onSelected: widget.onCategoryChanged == null
                      ? null
                      : (_) => widget.onCategoryChanged!(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: widget.labelController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.activitiesLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return AppLocalizations.of(context)!.activitiesLabelRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.linkController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.activitiesLink,
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            validator: widget.validateOptionalUrl,
          ),
          if (linkTrimmed.isNotEmpty && !showLivePreview) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.activitiesLinkPreviewAfterSave,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (showLivePreview) ...[
            const SizedBox(height: 12),
            LinkPreviewCardFromFirestore(
              url: linkTrimmed,
              preview: widget.activity.linkPreview,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.addressController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.activitiesAddress,
              hintText: AppLocalizations.of(context)!.activitiesAddressHint,
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.commentsController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.activitiesComments,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 6,
          ),
        ],
      ),
    );
  }
}

class _VotersSection extends ConsumerStatefulWidget {
  const _VotersSection({
    required this.tripId,
    required this.activityId,
    required this.votes,
    required this.myUid,
    required this.currentUserId,
    required this.tripMemberPublicLabels,
  });

  final String tripId;
  final String activityId;
  final List<String> votes;
  final String myUid;
  final String? currentUserId;
  final Map<String, String> tripMemberPublicLabels;

  @override
  ConsumerState<_VotersSection> createState() => _VotersSectionState();
}

class _VotersSectionState extends ConsumerState<_VotersSection> {
  bool _loading = false;

  Future<void> _toggle() async {
    if (_loading || widget.myUid.isEmpty) return;
    final hasVoted = widget.votes.contains(widget.myUid);
    setState(() => _loading = true);
    try {
      await ref.read(activitiesRepositoryProvider).voteForActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
            vote: !hasVoted,
          );
    } catch (_) {
      // le stream rétablit l'état
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVoted = widget.myUid.isNotEmpty && widget.votes.contains(widget.myUid);
    final scheme = Theme.of(context).colorScheme;
    final color = hasVoted ? scheme.primary : scheme.onSurfaceVariant;
    final l10n = AppLocalizations.of(context)!;

    final voterIds = widget.votes;
    final idsKey = stableUsersIdsKey(voterIds);
    final usersDataAsync = idsKey.isEmpty
        ? const AsyncValue<Map<String, Map<String, dynamic>>>.data({})
        : ref.watch(usersDataByIdsKeyStreamProvider(idsKey));
    final usersDataById = usersDataAsync.asData?.value ?? const {};

    final voterNames = voterIds.map((id) {
      return resolveTripMemberDisplayLabel(
        memberId: id,
        userData: usersDataById[id],
        tripMemberPublicLabels: widget.tripMemberPublicLabels,
        currentUserId: widget.currentUserId,
        emptyFallback: l10n.roleParticipant,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Tooltip(
              message: hasVoted ? l10n.activitiesUnvote : l10n.activitiesVote,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _loading || widget.myUid.isEmpty ? null : _toggle,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: color,
                          ),
                        )
                      : Icon(
                          hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined,
                          size: 20,
                          color: color,
                        ),
                ),
              ),
            ),
            if (voterIds.isNotEmpty) ...[
              const SizedBox(width: 10),
              _OverlappingBadges(
                voterIds: voterIds,
                usersDataById: usersDataById,
                tripMemberPublicLabels: widget.tripMemberPublicLabels,
                currentUserId: widget.currentUserId,
                fallbackLabel: l10n.roleParticipant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  voterNames.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverlappingBadges extends StatelessWidget {
  const _OverlappingBadges({
    required this.voterIds,
    required this.usersDataById,
    required this.tripMemberPublicLabels,
    required this.currentUserId,
    required this.fallbackLabel,
  });

  final List<String> voterIds;
  final Map<String, Map<String, dynamic>> usersDataById;
  final Map<String, String> tripMemberPublicLabels;
  final String? currentUserId;
  final String fallbackLabel;

  static const _badgeSize = 24.0;
  static const _step = 16.0;

  @override
  Widget build(BuildContext context) {
    final count = voterIds.length;
    final totalWidth = _badgeSize + (count - 1) * _step;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: totalWidth,
      height: _badgeSize + 2,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * _step,
              top: 0,
              child: Container(
                width: _badgeSize + 2,
                height: _badgeSize + 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: surfaceColor,
                ),
                alignment: Alignment.center,
                child: buildProfileBadge(
                  context: context,
                  displayLabel: resolveTripMemberDisplayLabel(
                    memberId: voterIds[i],
                    userData: usersDataById[voterIds[i]],
                    tripMemberPublicLabels: tripMemberPublicLabels,
                    currentUserId: currentUserId,
                    emptyFallback: fallbackLabel,
                  ),
                  userData: usersDataById[voterIds[i]],
                  size: _badgeSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _activityDrivingRouteBodyText(
  TripActivity activity,
  AppLocalizations l10n,
) {
  final route = activity.tripDrivingRoute;

  if (route == null) {
    return l10n.activitiesRouteCalculating;
  }
  switch (route.status) {
    case 'ok':
      final dist = route.distanceText?.trim();
      final dur = route.durationText?.trim();
      if ((dist != null && dist.isNotEmpty) ||
          (dur != null && dur.isNotEmpty)) {
        return [
          if (dist != null && dist.isNotEmpty)
            l10n.activitiesRouteDistance(dist),
          if (dur != null && dur.isNotEmpty)
            l10n.activitiesRouteDuration(dur),
        ].join('\n');
      }
      return l10n.activitiesRouteCalculated;
    case 'missing_trip_address':
      return l10n.activitiesRouteMissingTripAddress;
    case 'no_result':
      final detail = route.detail?.trim() ?? '';
      if (detail.isEmpty) return l10n.activitiesRouteNoResult;
      return l10n.activitiesRouteNoResultWithDetail(detail);
    case 'error':
      final msg = route.errorMessage?.trim() ?? '';
      if (msg.isEmpty) return l10n.activitiesRouteError;
      return l10n.activitiesRouteErrorWithMessage(msg);
    default:
      return l10n.activitiesRouteStatus(route.status);
  }
}
