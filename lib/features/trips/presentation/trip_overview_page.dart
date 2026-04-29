import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/app/theme/neutral_colors.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_announcements_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_placeholder_member.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';

class TripOverviewPage extends ConsumerStatefulWidget {
  const TripOverviewPage({super.key});

  @override
  ConsumerState<TripOverviewPage> createState() => _TripOverviewPageState();
}

class _TripOverviewPageState extends ConsumerState<TripOverviewPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late final TextEditingController _addressController;
  late final TextEditingController _linkController;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _inviteClipboardBusy = false;
  bool _isBannerBusy = false;
  DateTime? _editStartDate;
  DateTime? _editEndDate;
  Stream<Map<String, Map<String, dynamic>>>? _usersDataStreamCache;
  String? _usersDataStreamKey;

  Trip get _trip => TripScope.of(context);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _destinationController = TextEditingController();
    _addressController = TextEditingController();
    _linkController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final trip = TripScope.of(context);
    if (!_isEditing) {
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    _addressController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _startEditing() {
    final trip = TripScope.of(context);
    setState(() {
      _isEditing = true;
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
      _editStartDate = trip.startDate;
      _editEndDate = trip.endDate;
    });
  }

  void _cancelEditing() {
    final trip = TripScope.of(context);
    setState(() {
      _isEditing = false;
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
      _editStartDate = trip.startDate;
      _editEndDate = trip.endDate;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (isEndBeforeStart(_editStartDate, _editEndDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tripsCreateValidationDateOrder,
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final title = _titleController.text.trim();
      final destination = _destinationController.text.trim();
      final address = _addressController.text.trim();
      final linkUrl = _linkController.text.trim();

      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId: _trip.id,
            title: title,
            destination: destination,
            address: address,
            linkUrl: linkUrl,
            startDate: _editStartDate,
            endDate: _editEndDate,
          );

      if (!mounted) return;
      setState(() => _isEditing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _copyInviteCode() async {
    final l10n = AppLocalizations.of(context)!;
    if (_inviteClipboardBusy) return;
    setState(() => _inviteClipboardBusy = true);
    try {
      final token =
          await ref.read(tripsRepositoryProvider).getOrCreateInviteToken(
                tripId: _trip.id,
              );
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewInviteCodeCopied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewInviteCodeCopyError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _inviteClipboardBusy = false);
      }
    }
  }

  void _openParticipantsPage() {
    context.push('/trips/${_trip.id}/participants');
  }

  void _openAnnouncementsPage() {
    context.push('/trips/${_trip.id}/announcements');
  }

  void _openExpensesPage() {
    context.push('/trips/${_trip.id}/expenses');
  }

  void _openTripUserPreferencesPage() {
    context.push('/trips/${_trip.id}/preferences');
  }

  Future<void> _openLinkUrl(String url) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedUrl = Uri.tryParse(url.trim());
    if (parsedUrl == null || !parsedUrl.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkInvalid)),
      );
      return;
    }

    final launched = await launchUrl(
      parsedUrl,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  Future<void> _pickAndUploadBannerImage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isBannerBusy) return;
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _isBannerBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked == null) {
        return;
      }
      if (!mounted) return;

      final screenSize = MediaQuery.sizeOf(context);
      final webCropWidth =
          ((screenSize.width - 140).clamp(260.0, 900.0)).round();
      final webCropHeight =
          ((screenSize.height - 320).clamp(220.0, 700.0)).round();

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: l10n.tripOverviewCropBanner,
            toolbarColor: colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: colorScheme.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: l10n.tripOverviewCropBanner,
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
          if (kIsWeb)
            WebUiSettings(
              context: context,
              presentStyle: WebPresentStyle.dialog,
              size: CropperSize(
                width: webCropWidth,
                height: webCropHeight,
              ),
            ),
        ],
      );
      if (cropped == null) {
        return;
      }
      final imagePath = cropped.path;

      final bytes = await XFile(imagePath).readAsBytes();
      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(imagePath);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      await ref.read(tripsRepositoryProvider).upsertTripBannerImage(
            tripId: _trip.id,
            bytes: bytes,
            fileExt: ext,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewBannerUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  Future<void> _removeBannerImage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isBannerBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountRemovePhotoDialogTitle),
        content: Text(l10n.tripOverviewBannerRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBannerBusy = true);
    try {
      await ref
          .read(tripsRepositoryProvider)
          .removeTripBannerImage(tripId: _trip.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoDeleteError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  String _initialFromLabel(String label) {
    final clean = label.trim();
    if (clean.isEmpty) return '?';
    return clean.substring(0, 1).toUpperCase();
  }

  Stream<Map<String, Map<String, dynamic>>> _usersDataStreamFor(
    List<String> memberIds,
  ) {
    final realIds = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !isTripPlaceholderMemberId(id))
        .toList();
    final sorted = [...realIds]..sort();
    final key = sorted.join('\x1e');
    if (_usersDataStreamKey == key && _usersDataStreamCache != null) {
      return _usersDataStreamCache!;
    }
    _usersDataStreamKey = key;
    _usersDataStreamCache =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(realIds);
    return _usersDataStreamCache!;
  }

  String _photoUrlFromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    final account = (userData['account'] as Map<String, dynamic>?) ?? const {};
    final accountPhoto = (account['photoUrl'] as String?)?.trim() ?? '';
    if (accountPhoto.isNotEmpty) return accountPhoto;
    return (userData['photoUrl'] as String?)?.trim() ?? '';
  }

  DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _agendaDayParam(DateTime day) {
    final local = _dateOnly(day);
    final month = local.month.toString().padLeft(2, '0');
    final dayStr = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$dayStr';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final roomsAsync = ref.watch(tripRoomsStreamProvider(_trip.id));
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(_trip.id));
    final announcementsAsync =
        ref.watch(tripAnnouncementsStreamProvider(_trip.id));
    final activitiesCountersAsync =
        ref.watch(tripNotificationCountersProvider(_trip.id));
    final announcementsLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: _trip.id, channel: TripNotificationChannel.announcements),
      ),
    );
    final activitiesLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: _trip.id, channel: TripNotificationChannel.activities),
      ),
    );
    final rooms = roomsAsync.asData?.value ?? const [];
    final roomsCount = rooms.length;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final myAssignedRoomNames = myUid == null
        ? const <String>[]
        : rooms
            .where((room) => room.assignedMemberIds.contains(myUid))
            .map(
              (room) =>
                  room.name.trim().isEmpty ? l10n.roomsUnnamedRoom : room.name.trim(),
            )
            .toList();
    final roomsDetailLines = myAssignedRoomNames.isEmpty
        ? const <String>[]
        : [
            myAssignedRoomNames.length == 1
                ? l10n.tripOverviewMyRoom
                : l10n.tripOverviewMyRooms,
            myAssignedRoomNames.join(', '),
          ];
    final currentRole = resolveTripPermissionRole(
      trip: _trip,
      userId: myUid,
    );
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final canManageBanner = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.manageBannerMinRole,
    );
    final canShareAccess = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.shareAccessMinRole,
    );
    final canManageTripSettings = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.manageTripSettingsMinRole,
    );
    final canEditGeneralInfo = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.editGeneralInfoMinRole,
    );
    final tripDocStream = FirebaseFirestore.instance
        .collection('trips')
        .doc(_trip.id)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tripDocStream,
      builder: (context, snapshot) {
        final liveData = snapshot.data?.data();
        final liveLinkUrl =
            (liveData?['linkUrl'] as String?) ?? _trip.linkUrl;
        final livePreview =
            (liveData?['linkPreview'] as Map<String, dynamic>?) ?? const {};
        final liveMemberIds =
            ((liveData?['memberIds'] as List<dynamic>?) ?? _trip.memberIds)
                .map((id) => id.toString())
                .toList();
        final liveMemberPublicLabels = Trip.memberPublicLabelsFromFirestore(
          liveData?['memberPublicLabels'],
        );
        final liveBannerImageUrl =
            (liveData?['bannerImageUrl'] as String?)?.trim() ??
                (_trip.bannerImageUrl ?? '').trim();
        final linkUrlForUi =
            _isEditing ? _linkController.text.trim() : liveLinkUrl.trim();
        final photosStorageUrl =
            ((liveData?['photosStorageUrl'] as String?) ?? '').trim();
        final tripDateLabel =
            formatTripDateRange(context, _trip.startDate, _trip.endDate);
        final isTripMember = myUid != null &&
            liveMemberIds
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .contains(myUid);
        final canViewParticipants = canEdit || isTripMember;
        final participantsCount = liveMemberIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .length;
        final today = _dateOnly(DateTime.now());
        final mergedMemberPublicLabels = {
          ..._trip.memberPublicLabels,
          ...liveMemberPublicLabels,
        };
        final usersStream = _usersDataStreamFor(liveMemberIds);

        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, userSnap) {
            final usersDataById = userSnap.data ?? const {};
            final memberLabels = tripMemberLabelsFromUserDocsById(
              usersDataById,
              liveMemberIds,
              tripMemberPublicLabels: mergedMemberPublicLabels,
              currentUserId: myUid,
              emptyFallback: 'Voyageur',
            );
            final participantsPreview = liveMemberIds
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .map((id) {
                  final label = memberLabels[id]?.trim() ?? 'Voyageur';
                  return _ParticipantBadgePreviewEntry(
                    initial: _initialFromLabel(label),
                    photoUrl: _photoUrlFromUserData(usersDataById[id]),
                  );
                })
                .toList();
            final activitiesCounters = activitiesCountersAsync.asData?.value;
            var unreadActivities = 0;
            var unreadAnnouncements = 0;
            if (activitiesCounters != null &&
                activitiesCounters
                    .hasChannel(TripNotificationChannel.activities)) {
              unreadActivities = activitiesCounters
                  .unreadFor(TripNotificationChannel.activities);
            } else if (myUid != null && myUid.isNotEmpty) {
              final allActivities = activitiesAsync.asData?.value;
              final lastReadAt =
                  activitiesLastReadAtAsync.asData?.value?.toUtc();
              if (allActivities != null) {
                unreadActivities = allActivities.where((activity) {
                  if (activity.createdBy == myUid) return false;
                  if (lastReadAt == null) return true;
                  return activity.createdAt.toUtc().isAfter(lastReadAt);
                }).length;
              }
            }
            if (activitiesCounters != null &&
                activitiesCounters
                    .hasChannel(TripNotificationChannel.announcements)) {
              unreadAnnouncements = activitiesCounters
                  .unreadFor(TripNotificationChannel.announcements);
            } else if (myUid != null && myUid.isNotEmpty) {
              final allAnnouncements = announcementsAsync.asData?.value;
              final lastReadAt =
                  announcementsLastReadAtAsync.asData?.value?.toUtc();
              if (allAnnouncements != null) {
                unreadAnnouncements = allAnnouncements.where((announcement) {
                  if (announcement.authorId == myUid) return false;
                  if (lastReadAt == null) return true;
                  return announcement.createdAt.toUtc().isAfter(lastReadAt);
                }).length;
              }
            }

            final activitiesToday = (activitiesAsync.asData?.value ?? const <TripActivity>[])
                .where((activity) => activity.plannedAt != null)
                .where((activity) => _dateOnly(activity.plannedAt!) == today)
                .toList()
              ..sort((a, b) {
                final byPlanned = a.plannedAt!.compareTo(b.plannedAt!);
                if (byPlanned != 0) return byPlanned;
                return b.createdAt.compareTo(a.createdAt);
              });
            final activitiesTodayLabels = activitiesToday
                .map((activity) => activity.label.trim())
                .where((label) => label.isNotEmpty)
                .toList();
            final plannedActivitiesCount =
                (activitiesAsync.asData?.value ?? const <TripActivity>[])
                    .where((activity) => activity.plannedAt != null)
                    .length;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: NeutralColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                _TripBanner(
                  imageUrl: liveBannerImageUrl,
                  busy: _isBannerBusy,
                  onPick: canManageBanner && liveBannerImageUrl.isEmpty
                      ? _pickAndUploadBannerImage
                      : null,
                ),
                if (!_isEditing)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xCC2E206D),
                            Color(0x662E206D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _trip.title.isEmpty
                                  ? l10n.tripOverviewUntitled
                                  : _trip.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _trip.destination.isEmpty
                                  ? l10n.tripOverviewUnknownDestination
                                  : _trip.destination,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                            if (tripDateLabel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.date_range_outlined,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tripDateLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                  if (canViewParticipants)
                                    PopupMenuButton<String>(
                                      tooltip: l10n.tripOverviewActions,
                                      onSelected: (value) {
                                        if (value == 'preferences' &&
                                            isTripMember) {
                                          _openTripUserPreferencesPage();
                                          return;
                                        }
                                        if (value == 'copyCode' && canShareAccess) {
                                          _copyInviteCode();
                                          return;
                                        }
                                        if (value == 'edit' && canEditGeneralInfo) {
                                          _startEditing();
                                          return;
                                        }
                                        if (value == 'settings' &&
                                            canManageTripSettings) {
                                          context.go('/trips/${_trip.id}/settings');
                                          return;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (isTripMember)
                                          PopupMenuItem(
                                            value: 'preferences',
                                            child: Row(
                                              children: [
                                                const Icon(Icons.tune_outlined),
                                                const SizedBox(width: 10),
                                                Text(
                                                  l10n.tripUserPreferencesMenuAction,
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (canShareAccess)
                                          PopupMenuItem(
                                            value: 'copyCode',
                                            child: Row(
                                              children: [
                                                Icon(Icons.vpn_key_outlined),
                                                SizedBox(width: 10),
                                                Text(l10n.tripOverviewCopyCode),
                                              ],
                                            ),
                                          ),
                                        if (canEditGeneralInfo)
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined),
                                                SizedBox(width: 10),
                                                Text(l10n.tripOverviewEditTrip),
                                              ],
                                            ),
                                          ),
                                        if (canManageTripSettings)
                                          PopupMenuItem(
                                            value: 'settings',
                                            child: Row(
                                              children: [
                                                Icon(Icons.settings_outlined),
                                                SizedBox(width: 10),
                                                Text(l10n.tripSettingsTitle),
                                              ],
                                            ),
                                          ),
                                      ],
                                      icon: canEdit && _inviteClipboardBusy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : const Icon(Icons.settings_outlined,
                                              color: Colors.white),
                                    ),
                                ],
                              ),
                            ] else if (canViewParticipants) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Spacer(),
                                  PopupMenuButton<String>(
                                    tooltip: l10n.tripOverviewActions,
                                    onSelected: (value) {
                                      if (value == 'preferences' &&
                                          isTripMember) {
                                        _openTripUserPreferencesPage();
                                        return;
                                      }
                                      if (value == 'copyCode' && canShareAccess) {
                                        _copyInviteCode();
                                        return;
                                      }
                                      if (value == 'edit' && canEditGeneralInfo) {
                                        _startEditing();
                                        return;
                                      }
                                      if (value == 'settings' &&
                                          canManageTripSettings) {
                                        context.go('/trips/${_trip.id}/settings');
                                        return;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (isTripMember)
                                        PopupMenuItem(
                                          value: 'preferences',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.tune_outlined),
                                              const SizedBox(width: 10),
                                              Text(
                                                l10n.tripUserPreferencesMenuAction,
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (canShareAccess)
                                        PopupMenuItem(
                                          value: 'copyCode',
                                          child: Row(
                                            children: [
                                              Icon(Icons.vpn_key_outlined),
                                              SizedBox(width: 10),
                                              Text(l10n.tripOverviewCopyCode),
                                            ],
                                          ),
                                        ),
                                      if (canEditGeneralInfo)
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined),
                                              SizedBox(width: 10),
                                              Text(l10n.tripOverviewEditTrip),
                                            ],
                                          ),
                                        ),
                                      if (canManageTripSettings)
                                        PopupMenuItem(
                                          value: 'settings',
                                          child: Row(
                                            children: [
                                              Icon(Icons.settings_outlined),
                                              SizedBox(width: 10),
                                              Text(l10n.tripSettingsTitle),
                                            ],
                                          ),
                                        ),
                                    ],
                                    icon: canEdit && _inviteClipboardBusy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
                                          )
                                        : const Icon(Icons.settings_outlined,
                                            color: Colors.white),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (canManageBanner)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(999),
                      child: PopupMenuButton<String>(
                        tooltip: l10n.tripOverviewPhotoActions,
                        enabled: !_isBannerBusy,
                        onSelected: (value) {
                          if (value == 'change') {
                            _pickAndUploadBannerImage();
                            return;
                          }
                          if (value == 'remove') {
                            _removeBannerImage();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'change',
                            child: Text(l10n.tripOverviewChangePhoto),
                          ),
                          if (liveBannerImageUrl.isNotEmpty)
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(l10n.commonDelete),
                            ),
                        ],
                        icon: _isBannerBusy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.photo_camera_outlined,
                                color: Colors.white),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _TripOverviewTopSwitch(
                leftLabel: l10n.tripOverviewTopTabAnnouncements,
                rightLabel: l10n.tripOverviewTopTabExpenses,
                leftAlertCount: unreadAnnouncements,
                onLeftTap: _openAnnouncementsPage,
                onRightTap: _openExpensesPage,
                thirdLabel: photosStorageUrl.isNotEmpty ? 'Photos' : null,
                onThirdTap: photosStorageUrl.isNotEmpty
                    ? () => _openLinkUrl(photosStorageUrl)
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (_isEditing) ...[
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l10n.tripsTitleLabel,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.tripOverviewTitleRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _destinationController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l10n.tripsDestinationLabel,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.tripOverviewDestinationRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.tripsStartDateLabel),
                            subtitle:
                                Text(
                                  formatOptionalTripDate(context, _editStartDate),
                                ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_editStartDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setState(() => _editStartDate = null),
                                  ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _editStartDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null && mounted) {
                                      setState(() => _editStartDate = picked);
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _editStartDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && mounted) {
                                setState(() => _editStartDate = picked);
                              }
                            },
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.tripsEndDateLabel),
                            subtitle:
                                Text(
                                  formatOptionalTripDate(context, _editEndDate),
                                ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_editEndDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setState(() => _editEndDate = null),
                                  ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _editEndDate ??
                                          _editStartDate ??
                                          DateTime.now(),
                                      firstDate:
                                          _editStartDate ?? DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null && mounted) {
                                      setState(() => _editEndDate = picked);
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _editEndDate ??
                                    _editStartDate ??
                                    DateTime.now(),
                                firstDate: _editStartDate ?? DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && mounted) {
                                setState(() => _editEndDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _addressController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l10n.tripOverviewAddressLabel,
                              hintText: l10n.tripOverviewAddressHint,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _linkController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: l10n.tripOverviewLinkLabel,
                              hintText: l10n.tripOverviewLinkHint,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.url,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return null;
                              final uri = Uri.tryParse(v);
                              if (uri == null || !uri.isAbsolute) {
                                return l10n.tripOverviewLinkInvalid;
                              }
                              if (uri.scheme != 'http' &&
                                  uri.scheme != 'https') {
                                return l10n.tripOverviewLinkMustStartWithHttp;
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    const SizedBox(height: 10),
                  ],
                  if (canEditGeneralInfo && _isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_isEditing) ...[
                            IconButton(
                              tooltip: l10n.commonCancel,
                              onPressed: _isSaving ? null : _cancelEditing,
                              icon: const Icon(Icons.close),
                            ),
                            IconButton(
                              tooltip: l10n.commonSave,
                              onPressed: _isSaving ? null : _save,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Card(
                    color: NeutralColors.cardSurface,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.tripOverviewTileAccommodation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Icon(
                                Icons.home_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (linkUrlForUi.isNotEmpty) ...[
                            LinkPreviewCardFromFirestore(
                              url: linkUrlForUi,
                              preview: livePreview,
                              showCard: false,
                              showTitleLabel: false,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _InfoRow(
                            label: l10n.tripOverviewAddressLabel,
                            value: _trip.address,
                            actionIcon: Icons.location_on_outlined,
                            onActionPressed: _trip.address.trim().isEmpty
                                ? null
                                : () => openAddressInGoogleMaps(
                                      context,
                                      _trip.address,
                                    ),
                            actionTooltip: l10n.tripOverviewOpenLocation,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final cs = Theme.of(context).colorScheme;
                      final pz = context.planerzColors;
                      const tileSpacing = 10.0;
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final halfTileWidth =
                              (constraints.maxWidth - tileSpacing) / 2;
                          return Wrap(
                            spacing: tileSpacing,
                            runSpacing: tileSpacing,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth,
                                child: _TripAccessTile(
                                  label: l10n.tripOverviewTileParticipants,
                                  icon: Icons.assignment_ind_outlined,
                                  countLabel: '$participantsCount',
                                  backgroundColor: cs.tertiaryContainer,
                                  iconColor: cs.primary,
                                  previewParticipants: participantsPreview,
                                  onTap: _openParticipantsPage,
                                ),
                              ),
                              SizedBox(
                                width: halfTileWidth,
                                child: _TripAccessTile(
                                  label: l10n.tripOverviewTileActivities,
                                  icon: Icons.event_note_outlined,
                                  countLabel: '$plannedActivitiesCount',
                                  alertCount: unreadActivities,
                                  backgroundColor: pz.warningContainer,
                                  iconColor: cs.primary,
                                  detailLines: activitiesTodayLabels,
                                  showDetailBullets: false,
                                  wrapDetailLines: true,
                                  emptyStateMessage:
                                      l10n.tripOverviewTileNoActivitiesToday,
                                  onTap: () => context.go(
                                    '/trips/${_trip.id}/activities?agendaDay=${_agendaDayParam(today)}',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: halfTileWidth,
                                child: _TripAccessTile(
                                  label: l10n.tripOverviewTileRooms,
                                  icon: Icons.bed_outlined,
                                  countLabel: '$roomsCount',
                                  backgroundColor: pz.successContainer,
                                  iconColor: cs.primary,
                                  detailLines: roomsDetailLines,
                                  showDetailBullets: false,
                                  wrapDetailLines: true,
                                  emphasizedDetailLineIndex: 1,
                                  emptyStateMessage:
                                      l10n.tripOverviewTileNoAssignedRoom,
                                  onTap: () =>
                                      context.go('/trips/${_trip.id}/rooms'),
                                ),
                              ),
                              SizedBox(
                                width: halfTileWidth,
                                child: _TripAccessTile(
                                  label: l10n.tripOverviewTileCars,
                                  icon: Icons.directions_car_outlined,
                                  countLabel: '0',
                                  backgroundColor: cs.secondaryContainer,
                                  iconColor: cs.primary,
                                  showDetailBullets: false,
                                  wrapDetailLines: true,
                                  emptyStateMessage:
                                      l10n.tripOverviewTileComingSoon,
                                  onTap: () =>
                                      context.go('/trips/${_trip.id}/cars'),
                                ),
                              ),
                              SizedBox(
                                width: halfTileWidth,
                                child: _TripAccessTile(
                                  label: l10n.tripOverviewTileGames,
                                  icon: Icons.sports_esports_outlined,
                                  countLabel: '0',
                                  backgroundColor: cs.primaryContainer,
                                  iconColor: cs.primary,
                                  showDetailBullets: false,
                                  wrapDetailLines: true,
                                  emptyStateMessage:
                                      l10n.tripOverviewTileComingSoon,
                                  onTap: () {},
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }),
                  ],
                  if (myUid != null &&
                      !canEdit &&
                      liveMemberIds
                          .map((id) => id.trim())
                          .where((id) => id.isNotEmpty)
                          .contains(myUid)) ...[
                    const SizedBox(height: 16),
                    _LeaveTripSection(tripId: _trip.id),
                  ],
                ],
              ),
            ),
          ],
            );
          },
        );
      },
    );
  }
}

class _TripBanner extends StatelessWidget {
  const _TripBanner({
    required this.imageUrl,
    required this.busy,
    required this.onPick,
  });

  final String imageUrl;
  final bool busy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF2F4FD),
              const Color(0xFFD2DAF8),
            ],
          ),
        ),
        child: imageUrl.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                          child: Icon(Icons.broken_image_outlined, size: 42));
                    },
                  ),
                  if (busy)
                    const ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                ],
              )
            : Center(
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2.5)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            onPick == null
                                ? 'Aucune photo'
                                : 'Ajouter une photo de bannière',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
      ),
    );
  }
}

class _LeaveTripSection extends ConsumerStatefulWidget {
  const _LeaveTripSection({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_LeaveTripSection> createState() => _LeaveTripSectionState();
}

class _LeaveTripSectionState extends ConsumerState<_LeaveTripSection> {
  bool _busy = false;

  static String _messageForError(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
  }

  Future<void> _confirmAndLeave() async {
    final l10n = AppLocalizations.of(context)!;
    if (_busy) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripOverviewLeaveTripTitle),
        content: Text(l10n.tripOverviewLeaveTripDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.tripOverviewLeaveAction),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(tripsRepositoryProvider).leaveTripAsMember(
            tripId: widget.tripId,
          );
      if (!mounted) return;
      context.go('/trips');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Card(
      color: NeutralColors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tripOverviewLeaveTripCardTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tripOverviewLeaveTripCardBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _busy || myUid == null ? null : _confirmAndLeave,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.tripOverviewLeaveTripCardTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.actionIcon,
    this.onActionPressed,
    this.actionTooltip,
  });

  final String label;
  final String value;
  final IconData? actionIcon;
  final VoidCallback? onActionPressed;
  final String? actionTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (actionIcon != null)
          IconButton(
            tooltip: actionTooltip,
            onPressed: onActionPressed,
            icon: Icon(actionIcon),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
          ),
      ],
    );
  }
}

class _TripOverviewTopSwitch extends StatelessWidget {
  const _TripOverviewTopSwitch({
    required this.leftLabel,
    required this.rightLabel,
    this.leftAlertCount = 0,
    required this.onLeftTap,
    required this.onRightTap,
    this.thirdLabel,
    this.onThirdTap,
  });

  final String leftLabel;
  final String rightLabel;
  final int leftAlertCount;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;
  final String? thirdLabel;
  final VoidCallback? onThirdTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        );
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: _TripOverviewTopSwitchItem(
              label: leftLabel,
              icon: Icons.campaign_outlined,
              alertCount: leftAlertCount,
              color: cs.primary,
              foregroundColor: cs.onPrimary,
              borderColor: cs.outlineVariant,
              textStyle: labelStyle,
              onTap: onLeftTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TripOverviewTopSwitchItem(
              label: rightLabel,
              icon: Icons.payments_outlined,
              color: cs.tertiary,
              foregroundColor: cs.onTertiary,
              borderColor: cs.outlineVariant,
              textStyle: labelStyle,
              onTap: onRightTap,
            ),
          ),
          if (thirdLabel != null && onThirdTap != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _TripOverviewTopSwitchItem(
                label: thirdLabel!,
                icon: Icons.photo_library_outlined,
                color: cs.secondary,
                foregroundColor: cs.onSecondary,
                borderColor: cs.outlineVariant,
                textStyle: labelStyle,
                onTap: onThirdTap!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TripOverviewTopSwitchItem extends StatelessWidget {
  const _TripOverviewTopSwitchItem({
    required this.label,
    required this.icon,
    this.alertCount = 0,
    required this.color,
    required this.foregroundColor,
    required this.borderColor,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int alertCount;
  final Color color;
  final Color foregroundColor;
  final Color borderColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 0.8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withValues(alpha: 0.75)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(color: foregroundColor),
                ),
              ),
              if (alertCount > 0) ...[
                const SizedBox(width: 6),
                Badge.count(
                  count: alertCount,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TripAccessTile extends StatelessWidget {
  const _TripAccessTile({
    required this.label,
    required this.icon,
    required this.countLabel,
    required this.onTap,
    this.alertCount = 0,
    this.backgroundColor,
    this.iconColor,
    this.previewParticipants = const [],
    this.detailLines = const [],
    this.showDetailBullets = true,
    this.wrapDetailLines = false,
    this.emphasizedDetailLineIndex,
    this.emptyStateMessage,
  });

  final String label;
  final IconData icon;
  final String countLabel;
  final int alertCount;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final List<_ParticipantBadgePreviewEntry> previewParticipants;
  final List<String> detailLines;
  final bool showDetailBullets;
  final bool wrapDetailLines;
  final int? emphasizedDetailLineIndex;
  final String? emptyStateMessage;
  static const double _kTileHeight = 148;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPreview = previewParticipants.isNotEmpty;
    final hasDetails = detailLines.isNotEmpty;
    final visibleDetails = detailLines.take(3).toList();
    final moreDetailsCount = detailLines.length - visibleDetails.length;
    return Card(
      color: NeutralColors.cardSurface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: _kTileHeight,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      countLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Badge.count(
                      count: alertCount,
                      isLabelVisible: alertCount > 0,
                      child: Icon(icon, color: iconColor ?? colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: hasPreview
                        ? _ParticipantBadgesPreview(
                            participants: previewParticipants,
                          )
                        : hasDetails
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < visibleDetails.length; i++)
                                    Text(
                                      showDetailBullets
                                          ? '- ${visibleDetails[i]}'
                                          : visibleDetails[i],
                                      maxLines: wrapDetailLines ? null : 1,
                                      overflow: wrapDetailLines
                                          ? TextOverflow.visible
                                          : TextOverflow.ellipsis,
                                      softWrap: true,
                                      textAlign: TextAlign.center,
                                      style: ((emphasizedDetailLineIndex !=
                                                      null &&
                                                  i == 0)
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                              : emphasizedDetailLineIndex !=
                                                      null
                                                  ? Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodySmall)
                                          ?.copyWith(
                                            color:
                                                emphasizedDetailLineIndex == i
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight: emphasizedDetailLineIndex ==
                                                    i
                                                ? FontWeight.w700
                                                : null,
                                          ),
                                    ),
                                  if (moreDetailsCount > 0)
                                    Text(
                                      '+$moreDetailsCount',
                                      maxLines: wrapDetailLines ? null : 1,
                                      overflow: wrapDetailLines
                                          ? TextOverflow.visible
                                          : TextOverflow.ellipsis,
                                      softWrap: true,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              )
                            : emptyStateMessage != null
                                ? Text(
                                    emptyStateMessage!,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  )
                            : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantBadgesPreview extends StatelessWidget {
  const _ParticipantBadgesPreview({required this.participants});

  final List<_ParticipantBadgePreviewEntry> participants;

  static const int _maxVisible = 10;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(_maxVisible).toList();
    final remaining = participants.length - visible.length;
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final participant in visible)
          CircleAvatar(
            radius: 13,
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            foregroundImage: participant.photoUrl.isEmpty
                ? null
                : NetworkImage(participant.photoUrl),
            child: Text(
              participant.initial,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        if (remaining > 0)
          CircleAvatar(
            radius: 13,
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurfaceVariant,
            child: Text(
              '+$remaining',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _ParticipantBadgePreviewEntry {
  const _ParticipantBadgePreviewEntry({
    required this.initial,
    required this.photoUrl,
  });

  final String initial;
  final String photoUrl;
}
